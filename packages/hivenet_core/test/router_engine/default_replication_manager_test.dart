import 'dart:io';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

import '../helpers/fake_replication.dart';

void main() {
  const hash = 'aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44';
  const contentId = 'c0ffee00c0ffee00';
  late Directory tmp;
  late File objectFile;
  late ReplicationSource source;
  late FakeTransport transport;
  late MemoryReplicationStore store;
  late DefaultReplicationManager manager;

  UploadJob newJob({int factor = 2, UploadState status = UploadState.created, String? id}) =>
      UploadJob(
        jobId: id ?? 'job-1',
        status: status,
        requestedReplicationFactor: factor,
        createdAt: DateTime.utc(2026, 11, 1),
      );

  PlacementPlan plan(List<String> ids, {int desired = 2}) =>
      PlacementPlan(targetNodeIds: ids, desiredReplicas: desired);

  /// Runs a job to rest and returns every state it emitted, in order.
  Future<List<UploadJob>> run(UploadJob job, PlacementPlan p) =>
      manager.replicate(job, p, source).toList();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('hn_repl');
    objectFile = File('${tmp.path}/object.enc')..writeAsBytesSync([1, 2, 3, 4]);
    source = ReplicationSource(
        contentId: contentId, objectPath: objectFile.path, ciphertextHash: hash, sizeBytes: 4);
    transport = FakeTransport(hash);
    store = MemoryReplicationStore();
    manager = DefaultReplicationManager(
      transport: transport,
      store: store,
      config: const ReplicationConfig(
        reserveTimeout: Duration(milliseconds: 200),
        uploadTimeout: Duration(milliseconds: 200),
        commitTimeout: Duration(milliseconds: 200),
      ),
      clock: () => DateTime.utc(2026, 11, 1, 12),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('success', () {
    test('walks the PRD state machine and completes with two verified replicas', () async {
      final states = await run(newJob(), plan(['a', 'b']));
      expect(states.map((j) => j.status), [
        UploadState.reserving,
        UploadState.transferring,
        UploadState.verifying,
        UploadState.committing,
        UploadState.replicating,
        UploadState.completed,
      ]);
      expect(states.last.completedAt, isNotNull);
      expect(states.last.contentId, contentId);
      expect(store.replicas.where((r) => r.verified).map((r) => r.nodeId),
          unorderedEquals(['a', 'b']));
    });

    test('every emitted state was persisted first, in order', () async {
      final states = await run(newJob(), plan(['a', 'b']));
      expect(store.history, states.map((j) => j.status).toList());
      expect(store.jobs['job-1']!.status, UploadState.completed);
    });

    test('uses the destination flow: reserve, upload, commit for each peer', () async {
      await run(newJob(), plan(['a', 'b']));
      for (final id in ['a', 'b']) {
        final mine = transport.calls.where((c) => c.endsWith(':$id')).toList();
        expect(mine, ['reserve:$id', 'upload:$id', 'commit:$id']);
      }
    });

    test('replicas are recorded as verified with the hash and time', () async {
      await run(newJob(), plan(['a', 'b']));
      final r = store.replicas.first;
      expect(r.state, ReplicaState.storedVerified);
      expect(r.verified, isTrue);
      expect(r.ciphertextHash, hash);
      expect(r.storedAt, DateTime.utc(2026, 11, 1, 12));
    });

    test('three replicas for an important image', () async {
      final states = await run(newJob(factor: 3), plan(['a', 'b', 'c'], desired: 3));
      expect(states.last.status, UploadState.completed);
      expect(store.replicas.where((r) => r.verified), hasLength(3));
    });

    test('a hash reported in upper case still matches', () async {
      transport.commitHash['a'] = hash.toUpperCase();
      transport.commitHash['b'] = hash.toUpperCase();
      expect((await run(newJob(), plan(['a', 'b']))).last.status, UploadState.completed);
    });
  });

  group('no false success', () {
    test('one peer rejecting the reservation leaves the job under-replicated', () async {
      transport.reserveResult['b'] = const ReserveOutcome.rejected('storage_full');
      final last = (await run(newJob(), plan(['a', 'b']))).last;
      expect(last.status, UploadState.underReplicated);
      expect(last.failureReason, contains('b: rejected (storage_full)'));
      expect(store.replicas.where((r) => r.verified).map((r) => r.nodeId), ['a']);
    });

    test('every peer rejecting leaves the job waiting to retry, not failed', () async {
      for (final id in ['a', 'b']) {
        transport.reserveResult[id] = const ReserveOutcome.rejected('busy');
      }
      final states = await run(newJob(), plan(['a', 'b']));
      expect(states.last.status, UploadState.retryPending);
      expect(states.last.failureReason, isNotNull);
      expect(store.replicas, isEmpty);
    });

    test('an unreachable peer during reserve is dropped', () async {
      transport.reserveThrows.add('b');
      final last = (await run(newJob(), plan(['a', 'b']))).last;
      expect(last.status, UploadState.underReplicated);
      expect(last.failureReason, contains('b:'));
    });

    test('a connection lost mid-upload drops that peer and aborts it', () async {
      transport.uploadThrows.add('b');
      final last = (await run(newJob(), plan(['a', 'b']))).last;
      expect(last.status, UploadState.underReplicated);
      expect(transport.aborted, ['b']);
      expect(transport.calls, isNot(contains('commit:b')));
    });

    test('a peer that never finishes uploading is timed out, not waited on forever', () async {
      transport.uploadHangs.add('b');
      final last = (await run(newJob(), plan(['a', 'b']))).last;
      expect(last.status, UploadState.underReplicated);
      expect(last.failureReason, contains('b: timed out'));
    });

    test('a peer reporting a different hash is NOT counted as a replica', () async {
      transport.commitHash['b'] = 'f' * 64;
      final last = (await run(newJob(), plan(['a', 'b']))).last;
      expect(last.status, UploadState.underReplicated);
      expect(last.failureReason, contains('failed hash verification'));
      final b = store.replicas.firstWhere((r) => r.nodeId == 'b');
      expect(b.verified, isFalse);
      expect(b.state, ReplicaState.corrupted);
      expect(await store.verifiedReplicaNodeIds(contentId), {'a'});
    });

    test('a failing commit drops the peer and aborts it', () async {
      transport.commitThrows.add('a');
      final last = (await run(newJob(), plan(['a', 'b']))).last;
      expect(last.status, UploadState.underReplicated);
      expect(transport.aborted, ['a']);
    });

    test('all peers failing at commit leaves nothing counted', () async {
      transport.commitThrows.addAll(['a', 'b']);
      final last = (await run(newJob(), plan(['a', 'b']))).last;
      expect(last.status, UploadState.retryPending);
      expect(store.replicas, isEmpty);
    });

    test('no eligible peers at all stays pending with a clear reason', () async {
      final states = await run(newJob(), plan([]));
      expect(states.last.status, UploadState.retryPending);
      expect(states.last.failureReason, contains('no eligible storage peers'));
      expect(transport.calls, isEmpty);
    });

    test('an important image with only two peers stays under-replicated', () async {
      final last = (await run(newJob(factor: 3), plan(['a', 'b'], desired: 3))).last;
      expect(last.status, UploadState.underReplicated);
      expect(last.status, isNot(UploadState.completed));
    });

    test('completed is never emitted unless enough replicas are verified', () async {
      for (final failing in [<String>[], ['a'], ['b'], ['a', 'b']]) {
        transport = FakeTransport(hash);
        for (final id in failing) {
          transport.commitHash[id] = '0' * 64;
        }
        store = MemoryReplicationStore();
        manager = DefaultReplicationManager(transport: transport, store: store);
        final last = (await run(newJob(id: 'j-${failing.join()}'), plan(['a', 'b']))).last;
        final verified = store.replicas.where((r) => r.verified).length;
        expect(last.status == UploadState.completed, verified >= 2,
            reason: 'failing=$failing verified=$verified');
      }
    });
  });

  group('restart and retry', () {
    test('a job found mid-transfer after a restart steps back and restarts', () async {
      final stuck = newJob(status: UploadState.transferring).withContentId(contentId);
      final states = await run(stuck, plan(['a', 'b']));
      expect(states.map((j) => j.status).take(2),
          [UploadState.retryPending, UploadState.reserving]);
      expect(states.last.status, UploadState.completed);
    });

    test('every in-flight state can be resumed', () async {
      for (final s in [
        UploadState.reserving, UploadState.transferring, UploadState.verifying,
        UploadState.committing, UploadState.replicating,
      ]) {
        transport = FakeTransport(hash);
        store = MemoryReplicationStore();
        manager = DefaultReplicationManager(transport: transport, store: store);
        final states = await run(newJob(status: s), plan(['a', 'b']));
        expect(states.last.status, UploadState.completed, reason: s.name);
      }
    });

    test('a retry skips peers that already hold a verified replica', () async {
      final first = await run(newJob(), plan(['a', 'b']));
      expect(first.last.status, UploadState.completed);

      // Pretend b lost nothing but the job is re-run after an under-replicated
      // outcome: only the missing replica should be sent.
      transport = FakeTransport(hash);
      store = MemoryReplicationStore()
        ..replicas.add(ReplicaRecord(
            contentId: contentId, nodeId: 'a', state: ReplicaState.storedVerified, verified: true));
      manager = DefaultReplicationManager(transport: transport, store: store);
      final again = await run(newJob(status: UploadState.underReplicated), plan(['a', 'b', 'c']));
      expect(again.last.status, UploadState.completed);
      expect(transport.calls.where((c) => c.endsWith(':a')), isEmpty,
          reason: 'a already holds the object');
      expect(transport.calls.where((c) => c.startsWith('upload:')), ['upload:b']);
    });

    test('a retry from retry-pending can finish the job', () async {
      transport.reserveResult['a'] = const ReserveOutcome.rejected('busy');
      transport.reserveResult['b'] = const ReserveOutcome.rejected('busy');
      final first = await run(newJob(), plan(['a', 'b']));
      expect(first.last.status, UploadState.retryPending);

      transport.reserveResult.clear();
      final retry = await run(first.last, plan(['a', 'b']));
      expect(retry.last.status, UploadState.completed);
    });

    test('running a completed job again changes nothing', () async {
      final done = (await run(newJob(), plan(['a', 'b']))).last;
      final callsBefore = transport.calls.length;
      final again = await run(done, plan(['a', 'b']));
      expect(again, hasLength(1));
      expect(again.single.status, UploadState.completed);
      expect(transport.calls.length, callsBefore);
    });

    test('a failed job stays failed', () async {
      final failed = newJob().transitionTo(UploadState.failed, failureReason: 'x');
      final again = await run(failed, plan(['a', 'b']));
      expect(again.single.status, UploadState.failed);
      expect(transport.calls, isEmpty);
    });

    test('unfinishedJobs lets a restart find what to resume', () async {
      await store.saveJob(newJob(status: UploadState.transferring, id: 'x'));
      await store.saveJob(newJob(status: UploadState.completed, id: 'y'));
      expect((await store.unfinishedJobs()).map((j) => j.jobId), ['x']);
    });
  });

  group('guards', () {
    test('a missing encrypted object fails the job instead of retrying forever', () async {
      objectFile.deleteSync();
      final last = (await run(newJob(), plan(['a', 'b']))).last;
      expect(last.status, UploadState.failed);
      expect(last.failureReason, contains('missing'));
      expect(transport.calls, isEmpty);
    });

    test('a job for a different object is refused', () async {
      final other = newJob().withContentId('some-other-object');
      expect(() => run(other, plan(['a', 'b'])), throwsArgumentError);
    });

    test('failure reasons carry no file paths or raw exception text', () async {
      transport.uploadThrows.add('b');
      final last = (await run(newJob(), plan(['a', 'b']))).last;
      expect(last.failureReason, isNot(contains(tmp.path)));
      expect(last.failureReason, isNot(contains('connection lost')));
    });

    test('repair is not implemented yet and says so', () {
      expect(() => manager.repairUnderReplicated(), throwsUnimplementedError);
    });
  });
}
