import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivenet/app/providers.dart';
import 'package:hivenet_core/hivenet_core.dart';

PeerTelemetry peer(String id) => PeerTelemetry(
      nodeId: id,
      deviceName: id,
      protocolVersion: kProtocolVersion,
      ipAddresses: const [],
      port: 1,
      availableStorageBytes: 10 * 1024 * 1024 * 1024,
      totalStorageBytes: 20 * 1024 * 1024 * 1024,
      reservedStorageBytes: 0,
      activeTransfers: 0,
      lastSeen: DateTime.now().toUtc(),
      status: PeerStatus.online,
      measuredLatencyMs: 10,
      reliabilityScore: 90,
    );

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  final t = DateTime.utc(2026, 11, 1);

  Future<void> trust(String id, TrustStatus status, {DateTime? revokedAt}) =>
      db.trustedDevicesDao.upsert(TrustedDevicesCompanion.insert(
        nodeId: id,
        publicKey: 'pk',
        fingerprint: 'fp',
        displayName: id,
        pairedAt: t,
        trustStatus: status.wire,
        revokedAt: Value(revokedAt),
      ));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  const request = PlacementRequest(sizeBytes: 1024 * 1024, importance: Importance.normal);

  test('only paired, non-revoked devices can be chosen as storage peers', () async {
    await trust('paired', TrustStatus.paired);
    await trust('revoked', TrustStatus.revoked, revokedAt: t);
    // 'stranger' is online but was never paired.
    final plan = await container
        .read(storageRouterProvider)
        .plan(request, [peer('paired'), peer('revoked'), peer('stranger')]);
    expect(plan.targetNodeIds, ['paired']);
    expect(plan.isShortfall, isTrue);
  });

  test('revoking a device removes it from the next plan', () async {
    await trust('a', TrustStatus.paired);
    await trust('b', TrustStatus.paired);
    final router = container.read(storageRouterProvider);
    expect((await router.plan(request, [peer('a'), peer('b')])).targetNodeIds,
        unorderedEquals(['a', 'b']));

    await trust('b', TrustStatus.revoked, revokedAt: t);
    expect((await router.plan(request, [peer('a'), peer('b')])).targetNodeIds, ['a']);
  });

  test('the AI ranker is the no-op model unless one is configured', () {
    expect(container.read(decisionModelProvider), isA<NoopDecisionModel>());
  });

  test('replication store and quota manager are real implementations', () async {
    expect(container.read(replicationStoreProvider), isA<DriftReplicationStore>());
    expect(container.read(nodeScorerProvider), isA<DeterministicNodeScorer>());
  });
}
