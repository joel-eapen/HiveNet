import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase db;
  final t = DateTime.utc(2026, 11, 1);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('creates all ten PRD §6 tables', () async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%'")
        .get();
    expect(rows.map((r) => r.read<String>('name')).toSet(), {
      'nodes', 'image_files', 'replicas', 'upload_jobs', 'transfers',
      'trusted_devices', 'access_grants', 'device_keys',
      'wrapped_image_keys', 'manifest_events',
    });
  });

  test('nodes', () async {
    await db.nodesDao.upsert(NodesCompanion.insert(
        nodeId: 'n1', deviceName: 'Pixel', platform: 'android', port: 1,
        protocolVersion: 1, status: 'online'));
    expect((await db.nodesDao.byId('n1'))!.deviceName, 'Pixel');
  });

  test('image files', () async {
    await db.filesDao.upsert(ImageFilesCompanion.insert(
        contentId: 'c1', ownerNodeId: 'n1', fileName: 'a.jpg',
        mimeType: 'image/jpeg', fileSizeBytes: 10, width: 1, height: 1,
        importance: 'normal', visibility: 'private',
        desiredReplicationFactor: 2, createdAt: t, manifestVersion: 1,
        availabilityStatus: 'pending'));
    expect((await db.filesDao.byContentId('c1'))!.fileName, 'a.jpg');
  });

  test('replicas count only verified ones', () async {
    await db.replicasDao.upsert(ReplicasCompanion.insert(
        contentId: 'c1', nodeId: 'n1', status: 'stored_verified',
        verified: const Value(true)));
    await db.replicasDao.upsert(ReplicasCompanion.insert(
        contentId: 'c1', nodeId: 'n2', status: 'stored_verified'));
    expect((await db.replicasDao.forContent('c1')).length, 2);
    expect(await db.replicasDao.verifiedCount('c1'), 1);
  });

  test('upload jobs: unfinished excludes terminal states', () async {
    for (final (id, s) in [('a', 'TRANSFERRING'), ('b', 'COMPLETED'), ('c', 'FAILED')]) {
      await db.uploadJobsDao.upsert(UploadJobsCompanion.insert(
          jobId: id, status: s, requestedReplicationFactor: 2, createdAt: t));
    }
    final open = await db.uploadJobsDao.unfinished();
    expect(open.map((j) => j.jobId), ['a']);
  });

  test('transfers', () async {
    await db.transfersDao.upsert(TransfersCompanion.insert(
        transferId: 't1', contentId: 'c1', sourceNodeId: 'a',
        destinationNodeId: 'b', direction: 'upload', status: 'queued',
        totalBytes: 5, startedAt: t, updatedAt: t));
    expect((await db.transfersDao.byId('t1'))!.bytesTransferred, 0);
  });

  test('trusted devices', () async {
    await db.trustedDevicesDao.upsert(TrustedDevicesCompanion.insert(
        nodeId: 'n1', publicKey: 'pk', fingerprint: 'fp',
        displayName: 'Tushar', pairedAt: t, trustStatus: 'paired'));
    expect((await db.trustedDevicesDao.byNodeId('n1'))!.displayName, 'Tushar');
  });

  test('access grants are independent per permission', () async {
    for (final p in ['view', 'store_encrypted']) {
      await db.accessGrantsDao.upsert(AccessGrantsCompanion.insert(
          contentId: 'c1', granteeNodeId: 'n2', permission: p,
          grantedBy: 'n1', grantVersion: 1, createdAt: t));
    }
    expect((await db.accessGrantsDao.forContent('c1')).length, 2);
  });

  test('manifest events ordered by version, unique per origin/content/version',
      () async {
    for (final v in [3, 1, 2]) {
      await db.manifestEventsDao.upsert(ManifestEventsCompanion.insert(
          eventId: 'e$v', contentId: 'c1', originNodeId: 'n1',
          manifestVersion: v, eventType: 'updated', payload: '{}',
          createdAt: t));
    }
    final since = await db.manifestEventsDao.since('n1', 1);
    expect(since.map((e) => e.manifestVersion), [2, 3]);
    expect(
        () => db.manifestEventsDao.upsert(ManifestEventsCompanion.insert(
            eventId: 'dup', contentId: 'c1', originNodeId: 'n1',
            manifestVersion: 2, eventType: 'updated', payload: '{}',
            createdAt: t)),
        throwsA(isA<Exception>()));
  });

  test('device keys and wrapped keys round trip', () async {
    await db.into(db.deviceKeys).insert(DeviceKeysCompanion.insert(
        nodeId: 'n1', publicKey: 'pk', keyAlgorithm: 'ed25519',
        fingerprint: 'fp', createdAt: t));
    await db.into(db.wrappedImageKeys).insert(WrappedImageKeysCompanion.insert(
        contentId: 'c1', recipientNodeId: 'n2', wrappedKey: 'wk',
        keyVersion: 1, createdAt: t));
    expect((await db.select(db.deviceKeys).get()).length, 1);
    expect((await db.select(db.wrappedImageKeys).get()).length, 1);
  });
}
