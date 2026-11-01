import 'dart:typed_data';
import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

PeerTelemetry peer(String id) => PeerTelemetry(
      nodeId: id, deviceName: id, protocolVersion: 1, ipAddresses: const [],
      port: 1, availableStorageBytes: 1, totalStorageBytes: 1,
      reservedStorageBytes: 0, activeTransfers: 0,
      lastSeen: DateTime.utc(2026), status: PeerStatus.online,
    );

void main() {
  group('config matches the PRD', () {
    test('compression policy (FR-03)', () {
      const c = CompressionConfig();
      expect(c.qualityFor(Importance.normal), 80);
      expect(c.qualityFor(Importance.important), 90);
      expect(c.maxDimensionFor(Importance.normal), 2048);
      expect(c.maxDimensionFor(Importance.important), 2560);
      expect(c.thumbnailMinDimension, 320);
      expect(c.thumbnailMaxDimension, 480);
      expect(c.stripGpsMetadata, isTrue);
    });

    test('network constants (FR-02, §5, §9)', () {
      const n = NetworkConfig();
      expect(n.serviceType, '_hivenet._tcp');
      expect(n.heartbeatInterval, const Duration(seconds: 5));
      expect(n.chunkSizeBytes, 1048576);
      expect(n.maxConcurrentUploadsPerPeer, 2);
      expect(n.offlineTimeout > n.heartbeatInterval, isTrue);
    });

    test('score weights sum to 1', () {
      const w = ScoreWeights();
      expect([w.capacity, w.latency, w.battery, w.uptime, w.bandwidth, w.load],
          [0.25, 0.20, 0.20, 0.20, 0.10, 0.05]);
      expect(w.total, closeTo(1.0, 1e-9));
    });

    test('replication factors (FR-04)', () {
      expect(Importance.normal.desiredReplicationFactor, 2);
      expect(Importance.important.desiredReplicationFactor, 3);
    });
  });

  group('StorageLayout (FR-10)', () {
    const layout = StorageLayout('/data/HiveNet');

    test('builds PRD paths', () {
      expect(layout.objectPath('ab12cd'), '/data/HiveNet/objects/ab/ab12cd.enc');
      expect(layout.thumbnailPath('ab12cd'), '/data/HiveNet/thumbnails/ab12cd.webp');
      expect(layout.databasePath, '/data/HiveNet/database/hivenet.sqlite');
      expect(layout.retrievedCacheDir, '/data/HiveNet/cache/retrieved');
      expect(layout.incompleteTransferPath('t1'),
          '/data/HiveNet/temporary/incomplete-transfers/t1.part');
    });

    test('rejects path traversal from untrusted ids', () {
      expect(() => layout.objectPath('../../etc/passwd'), throwsArgumentError);
      expect(() => layout.objectPath('a/b'), throwsArgumentError);
      expect(() => layout.objectPath('a'), throwsArgumentError);
      expect(() => layout.incompleteTransferPath('..'), throwsArgumentError);
    });
  });

  group('stubs', () {
    test('unbuilt services throw UnimplementedError', () {
      expect(() => const UnimplementedStorageRouter()
          .plan(const PlacementRequest(sizeBytes: 1, importance: Importance.normal), []),
          throwsUnimplementedError);
      expect(() => const UnimplementedEncryptionService().encrypt(Uint8List(0)),
          throwsUnimplementedError);
      expect(() => const UnimplementedSocketClient().connect('h', 1),
          throwsUnimplementedError);
      expect(() => const UnimplementedFileStore().exists('c'),
          throwsUnimplementedError);
      expect(() => const UnimplementedMessageFraming().encode(
          const MessageEnvelope(type: MessageType.heartbeat, requestId: 'r', senderNodeId: 'n')),
          throwsUnimplementedError);
    });
  });

  group('access control default', () {
    test('denies every permission', () async {
      for (final p in PermissionType.values) {
        final d = await const DenyAllAccessControl()
            .check(requesterNodeId: 'n', contentId: 'c', permission: p);
        expect(d.granted, isFalse);
      }
    });
  });

  test('PlacementPlan flags shortfall instead of success', () {
    const plan = PlacementPlan(targetNodeIds: ['a'], desiredReplicas: 2);
    expect(plan.isShortfall, isTrue);
    const ok = PlacementPlan(targetNodeIds: ['a', 'b'], desiredReplicas: 2);
    expect(ok.isShortfall, isFalse);
  });
}
