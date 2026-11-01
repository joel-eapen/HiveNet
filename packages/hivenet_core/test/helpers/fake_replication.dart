import 'dart:async';

import 'package:hivenet_core/hivenet_core.dart';

/// In-memory [ReplicationStore] that records every save in order.
class MemoryReplicationStore implements ReplicationStore {
  final Map<String, UploadJob> jobs = {};
  final List<UploadState> history = [];
  final List<ReplicaRecord> replicas = [];

  @override
  Future<void> saveJob(UploadJob job) async {
    jobs[job.jobId] = job;
    history.add(job.status);
  }

  @override
  Future<void> saveReplica(ReplicaRecord replica) async {
    replicas.removeWhere(
        (r) => r.contentId == replica.contentId && r.nodeId == replica.nodeId);
    replicas.add(replica);
  }

  @override
  Future<Set<String>> verifiedReplicaNodeIds(String contentId) async => {
        for (final r in replicas)
          if (r.contentId == contentId && r.verified) r.nodeId,
      };

  @override
  Future<List<UploadJob>> unfinishedJobs() async =>
      [for (final j in jobs.values) if (!j.status.isTerminal) j];
}

/// Scriptable peer behaviour. By default every peer cooperates and reports the
/// expected hash.
class FakeTransport implements ReplicaTransport {
  FakeTransport(this.expectedHash);

  final String expectedHash;

  final Map<String, ReserveOutcome> reserveResult = {};
  final Set<String> reserveThrows = {};
  final Set<String> uploadThrows = {};
  final Set<String> uploadHangs = {};
  final Set<String> commitThrows = {};
  final Map<String, String> commitHash = {};

  final List<String> calls = [];
  final List<String> aborted = [];

  @override
  Future<ReserveOutcome> reserve({
    required String nodeId,
    required String jobId,
    required String contentId,
    required int sizeBytes,
  }) async {
    calls.add('reserve:$nodeId');
    if (reserveThrows.contains(nodeId)) throw StateError('unreachable');
    return reserveResult[nodeId] ?? const ReserveOutcome.accepted();
  }

  @override
  Future<void> upload({
    required String nodeId,
    required String jobId,
    required ReplicationSource source,
  }) async {
    calls.add('upload:$nodeId');
    if (uploadHangs.contains(nodeId)) return Completer<void>().future;
    if (uploadThrows.contains(nodeId)) throw StateError('connection lost');
  }

  @override
  Future<String> commit({
    required String nodeId,
    required String jobId,
    required String contentId,
  }) async {
    calls.add('commit:$nodeId');
    if (commitThrows.contains(nodeId)) throw StateError('commit failed');
    return commitHash[nodeId] ?? expectedHash;
  }

  @override
  Future<void> abort({required String nodeId, required String jobId}) async {
    aborted.add(nodeId);
  }
}
