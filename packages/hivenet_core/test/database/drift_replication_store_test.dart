import 'dart:io';

import 'package:drift/native.dart';
import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase db;
  late DriftReplicationStore store;
  final t = DateTime.utc(2026, 11, 1, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftReplicationStore(db);
  });
  tearDown(() => db.close());

  UploadJob job(String id, UploadState s, {String? contentId, String? reason}) => UploadJob(
        jobId: id,
        contentId: contentId,
        status: s,
        requestedReplicationFactor: 2,
        createdAt: t,
        failureReason: reason,
      );

  test('a job round-trips through the database', () async {
    await store.saveJob(job('j1', UploadState.retryPending, contentId: 'c1', reason: 'b: timed out'));
    final back = (await store.unfinishedJobs()).single;
    expect(back.jobId, 'j1');
    expect(back.contentId, 'c1');
    expect(back.status, UploadState.retryPending);
    expect(back.requestedReplicationFactor, 2);
    expect(back.failureReason, 'b: timed out');
    expect(back.createdAt, t);
  });

  test('saving a job again updates it rather than duplicating', () async {
    await store.saveJob(job('j1', UploadState.created));
    await store.saveJob(job('j1', UploadState.transferring));
    final all = await store.unfinishedJobs();
    expect(all, hasLength(1));
    expect(all.single.status, UploadState.transferring);
  });

  test('completed and failed jobs are not returned for resuming', () async {
    await store.saveJob(job('a', UploadState.completed));
    await store.saveJob(job('b', UploadState.failed));
    await store.saveJob(job('c', UploadState.underReplicated));
    await store.saveJob(job('d', UploadState.verifying));
    expect((await store.unfinishedJobs()).map((j) => j.jobId), unorderedEquals(['c', 'd']));
  });

  test('only verified replicas are reported as held', () async {
    await store.saveReplica(ReplicaRecord(
        contentId: 'c1', nodeId: 'a', state: ReplicaState.storedVerified, verified: true, storedAt: t));
    await store.saveReplica(ReplicaRecord(
        contentId: 'c1', nodeId: 'b', state: ReplicaState.corrupted, verified: false));
    await store.saveReplica(ReplicaRecord(
        contentId: 'other', nodeId: 'z', state: ReplicaState.storedVerified, verified: true));
    expect(await store.verifiedReplicaNodeIds('c1'), {'a'});
    expect(await store.verifiedReplicaNodeIds('nothing'), isEmpty);
  });

  test('a replica later found corrupted stops counting', () async {
    await store.saveReplica(ReplicaRecord(
        contentId: 'c1', nodeId: 'a', state: ReplicaState.storedVerified, verified: true));
    await store.saveReplica(ReplicaRecord(
        contentId: 'c1', nodeId: 'a', state: ReplicaState.corrupted, verified: false));
    expect(await store.verifiedReplicaNodeIds('c1'), isEmpty);
  });

  test('the manager works end to end against the real database', () async {
    final manager = DefaultReplicationManager(
      transport: _AlwaysOk('h' * 64),
      store: store,
    );
    final tmp = await _tempObject();
    final source = ReplicationSource(
        contentId: 'c9', objectPath: tmp, ciphertextHash: 'h' * 64, sizeBytes: 3);
    final states = await manager
        .replicate(job('j9', UploadState.created),
            const PlacementPlan(targetNodeIds: ['a', 'b'], desiredReplicas: 2), source)
        .toList();
    expect(states.last.status, UploadState.completed);
    expect(await store.verifiedReplicaNodeIds('c9'), {'a', 'b'});
    expect(await store.unfinishedJobs(), isEmpty);
  });
}

class _AlwaysOk implements ReplicaTransport {
  _AlwaysOk(this.hash);
  final String hash;
  @override
  Future<ReserveOutcome> reserve({required String nodeId, required String jobId, required String contentId, required int sizeBytes}) async =>
      const ReserveOutcome.accepted();
  @override
  Future<void> upload({required String nodeId, required String jobId, required ReplicationSource source}) async {}
  @override
  Future<String> commit({required String nodeId, required String jobId, required String contentId, required String ciphertextHash}) async => hash;
  @override
  Future<void> abort({required String nodeId, required String jobId}) async {}
}

Future<String> _tempObject() async {
  final dir = await Directory.systemTemp.createTemp('hn_obj');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}/o.enc')..writeAsBytesSync([1, 2, 3]);
  return file.path;
}
