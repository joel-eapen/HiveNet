import 'dart:async';
import 'dart:io';

import '../../shared/models/enums.dart';
import '../../shared/models/hive_error.dart';
import '../../shared/models/jobs.dart';
import '../../shared/models/replica_record.dart';
import 'replica_transport.dart';
import 'replication_manager.dart';
import 'replication_store.dart';
import 'storage_router.dart';

class ReplicationConfig {
  const ReplicationConfig({
    this.reserveTimeout = const Duration(seconds: 15),
    this.uploadTimeout = const Duration(minutes: 10),
    this.commitTimeout = const Duration(minutes: 1),
  });

  final Duration reserveTimeout;
  final Duration uploadTimeout;
  final Duration commitTimeout;
}

/// Drives an upload job through the PRD section 13.1 state machine:
///
/// ```text
/// CREATED -> RESERVING -> TRANSFERRING -> VERIFYING -> COMMITTING
///         -> REPLICATING -> COMPLETED
/// ```
///
/// What each state means here:
/// - RESERVING: ask every target to hold space.
/// - TRANSFERRING: send the object to the targets that accepted.
/// - VERIFYING: each target verifies the whole object and commits it atomically.
/// - COMMITTING: compare each target's reported hash with the expected one.
/// - REPLICATING: record the replicas and count the verified ones.
///
/// Rules that hold in every path:
/// - `COMPLETED` only when verified replicas >= the requested factor. A hash
///   mismatch, an unreachable peer or a rejection never counts.
/// - With some but not enough replicas the job ends `UNDER_REPLICATED`; with
///   none it ends `RETRY_PENDING`. Neither is reported as success.
/// - Every transition is saved before it is emitted, and the job is safe to
///   run again: peers that already hold a verified replica are skipped, and a
///   job found mid-flight after a restart first steps back to RETRY_PENDING.
class DefaultReplicationManager implements ReplicationManager {
  DefaultReplicationManager({
    required this.transport,
    required this.store,
    this.config = const ReplicationConfig(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReplicaTransport transport;
  final ReplicationStore store;
  final ReplicationConfig config;
  final DateTime Function() _clock;

  @override
  Stream<UploadJob> replicate(
    UploadJob job,
    PlacementPlan plan,
    ReplicationSource source,
  ) async* {
    if (job.contentId != null && job.contentId != source.contentId) {
      throw ArgumentError('Job ${job.jobId} is for ${job.contentId}, '
          'not ${source.contentId}');
    }
    var current = job.contentId == null ? job.withContentId(source.contentId) : job;

    // Completed and failed jobs are final: running them again changes nothing.
    if (current.status.isTerminal) {
      yield current;
      return;
    }

    // A job found mid-flight (the app died during an upload) is restarted
    // from the top. Nothing in flight is trusted; only stored replicas count.
    const restingStates = {
      UploadState.created,
      UploadState.retryPending,
      UploadState.underReplicated,
    };
    if (!restingStates.contains(current.status)) {
      current = await _move(current, UploadState.retryPending);
      yield current;
    }
    current = await _move(current, UploadState.reserving);
    yield current;

    if (!File(source.objectPath).existsSync()) {
      current = await _move(current, UploadState.failed,
          reason: 'the encrypted object to upload is missing');
      yield current;
      return;
    }

    final desired = current.requestedReplicationFactor;
    final alreadyHeld = await store.verifiedReplicaNodeIds(source.contentId);
    final needed = desired - alreadyHeld.length;
    final targets = [
      for (final id in plan.targetNodeIds)
        if (!alreadyHeld.contains(id)) id,
    ].take(needed < 0 ? 0 : needed).toList();
    final failures = <String>[];

    // ---- RESERVING
    final reserved = <String>[];
    await Future.wait([
      for (final id in targets)
        _attempt(id, failures, () async {
          final outcome = await transport
              .reserve(
                nodeId: id,
                jobId: current.jobId,
                contentId: source.contentId,
                sizeBytes: source.sizeBytes,
              )
              .timeout(config.reserveTimeout);
          if (outcome.accepted) {
            reserved.add(id);
          } else {
            failures.add('$id: rejected (${outcome.reason ?? 'no reason'})');
          }
        }),
    ]);
    if (targets.isNotEmpty && reserved.isEmpty) {
      yield await _rest(current, alreadyHeld.length, failures);
      return;
    }
    if (targets.isEmpty && alreadyHeld.length < desired) {
      failures.add('no eligible storage peers');
      yield await _rest(current, alreadyHeld.length, failures);
      return;
    }

    // ---- TRANSFERRING
    current = await _move(current, UploadState.transferring);
    yield current;
    final uploaded = <String>[];
    await Future.wait([
      for (final id in reserved)
        _attempt(id, failures, () async {
          await transport
              .upload(nodeId: id, jobId: current.jobId, source: source)
              .timeout(config.uploadTimeout);
          uploaded.add(id);
        }, onFailure: () => _abort(id, current.jobId)),
    ]);
    if (targets.isNotEmpty && uploaded.isEmpty) {
      yield await _rest(current, alreadyHeld.length, failures);
      return;
    }

    // ---- VERIFYING: the peers verify and commit.
    current = await _move(current, UploadState.verifying);
    yield current;
    final reportedHash = <String, String>{};
    await Future.wait([
      for (final id in uploaded)
        _attempt(id, failures, () async {
          reportedHash[id] = await transport
              .commit(
                nodeId: id,
                jobId: current.jobId,
                contentId: source.contentId,
              )
              .timeout(config.commitTimeout);
        }, onFailure: () => _abort(id, current.jobId)),
    ]);
    if (targets.isNotEmpty && reportedHash.isEmpty) {
      yield await _rest(current, alreadyHeld.length, failures);
      return;
    }

    // ---- COMMITTING: trust the peer's answer only if it matches.
    current = await _move(current, UploadState.committing);
    yield current;
    final expected = source.ciphertextHash.toLowerCase();
    final verified = <String>[];
    final now = _clock().toUtc();
    for (final entry in reportedHash.entries) {
      final matches = entry.value.toLowerCase() == expected;
      if (matches) {
        verified.add(entry.key);
      } else {
        failures.add('${entry.key}: stored object failed hash verification');
      }
      await store.saveReplica(ReplicaRecord(
        contentId: source.contentId,
        nodeId: entry.key,
        state: matches ? ReplicaState.storedVerified : ReplicaState.corrupted,
        verified: matches,
        ciphertextHash: entry.value,
        storedAt: now,
        lastVerifiedAt: now,
        lastSeenAt: now,
      ));
    }

    // ---- REPLICATING: count what is really there.
    current = await _move(current, UploadState.replicating);
    yield current;
    final total = alreadyHeld.length + verified.length;
    if (total >= desired) {
      current = await _move(current, UploadState.completed);
      yield current;
    } else {
      yield await _rest(current, total, failures);
    }
  }

  /// Not implemented here: repair needs the manifest list and a router, which
  /// arrive with Milestone 7. It will call [replicate] with a plan that
  /// excludes peers already holding a replica.
  @override
  Future<void> repairUnderReplicated() =>
      throw UnimplementedError('Replica repair: Milestone 7');

  // ------------------------------------------------------------- helpers

  /// Runs one peer operation. A failure is recorded for that peer and does not
  /// stop the others.
  Future<void> _attempt(
    String nodeId,
    List<String> failures,
    Future<void> Function() body, {
    Future<void> Function()? onFailure,
  }) async {
    try {
      await body();
    } catch (e) {
      failures.add('$nodeId: ${_describe(e)}');
      if (onFailure != null) await onFailure();
    }
  }

  Future<void> _abort(String nodeId, String jobId) async {
    try {
      await transport.abort(nodeId: nodeId, jobId: jobId);
    } catch (_) {
      // Best effort: the peer's reservation expires on its own.
    }
  }

  /// Moves to the state that honestly describes a job that could not reach its
  /// replica target: under-replicated if any verified replica exists,
  /// otherwise waiting to retry.
  Future<UploadJob> _rest(
    UploadJob job,
    int verifiedCount,
    List<String> failures,
  ) =>
      _move(
        job,
        verifiedCount > 0 ? UploadState.underReplicated : UploadState.retryPending,
        reason: failures.isEmpty ? null : failures.join('; '),
      );

  Future<UploadJob> _move(UploadJob job, UploadState next, {String? reason}) async {
    final moved = job.transitionTo(next, failureReason: reason);
    await store.saveJob(moved);
    return moved;
  }

  /// Short, safe description for the job's failure reason. No paths, keys or
  /// raw exception text.
  String _describe(Object e) {
    if (e is HiveError) return e.code.wire;
    if (e is TimeoutException) return 'timed out';
    if (e is SocketException) return 'unreachable';
    return e.runtimeType.toString();
  }
}
