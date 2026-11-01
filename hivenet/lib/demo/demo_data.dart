import 'package:hivenet_core/hivenet_core.dart';

/// Fixture data for demo mode ONLY. Never import this from production
/// repositories; the UI shows a "Demo data" banner whenever it is in use.
abstract final class DemoData {
  static final DateTime _now = DateTime.utc(2026, 11, 1, 10);

  static const String ownerNodeId = 'node-demo-joel';

  static final List<ImageManifest> images = [
    ImageManifest(
      contentId: '3fa9c1d27be04e5a91f0aa11c0de0001',
      ownerNodeId: ownerNodeId,
      fileName: 'campus-sunrise.jpg',
      mimeType: 'image/jpeg',
      fileSizeBytes: 1843200,
      width: 2048,
      height: 1365,
      importance: Importance.normal,
      visibility: ImageVisibility.networkShared,
      desiredReplicationFactor: 2,
      createdAt: _now,
      manifestVersion: 1,
      availabilityStatus: AvailabilityStatus.available,
    ),
    ImageManifest(
      contentId: 'ab51e8f03c9d4a7b8e22bb33d1ef0002',
      ownerNodeId: ownerNodeId,
      fileName: 'whiteboard-design.jpg',
      mimeType: 'image/jpeg',
      fileSizeBytes: 912384,
      width: 2560,
      height: 1440,
      importance: Importance.important,
      visibility: ImageVisibility.selectedDevices,
      desiredReplicationFactor: 3,
      createdAt: _now.subtract(const Duration(hours: 3)),
      manifestVersion: 2,
      availabilityStatus: AvailabilityStatus.underReplicated,
    ),
    ImageManifest(
      contentId: '7c20d4a91e6b43f2a0c5cc44e2f00003',
      ownerNodeId: 'node-demo-tushar',
      fileName: 'team-photo.jpg',
      mimeType: 'image/jpeg',
      fileSizeBytes: 2201600,
      width: 2048,
      height: 1536,
      importance: Importance.normal,
      visibility: ImageVisibility.private,
      desiredReplicationFactor: 2,
      createdAt: _now.subtract(const Duration(days: 1)),
      manifestVersion: 1,
      availabilityStatus: AvailabilityStatus.temporarilyUnavailable,
    ),
  ];

  static final List<PeerTelemetry> peers = [
    PeerTelemetry(
      nodeId: 'node-demo-tushar',
      deviceName: "Tushar's Pixel",
      protocolVersion: kProtocolVersion,
      ipAddresses: const ['192.168.1.21'],
      port: 45678,
      availableStorageBytes: 12 * 1024 * 1024 * 1024,
      totalStorageBytes: 20 * 1024 * 1024 * 1024,
      reservedStorageBytes: 0,
      activeTransfers: 0,
      lastSeen: _now,
      status: PeerStatus.online,
      measuredLatencyMs: 14,
      reliabilityScore: 92,
    ),
    PeerTelemetry(
      nodeId: 'node-demo-kesav',
      deviceName: "Kesav's iPhone",
      protocolVersion: kProtocolVersion,
      ipAddresses: const ['192.168.1.34'],
      port: 45678,
      availableStorageBytes: 6 * 1024 * 1024 * 1024,
      totalStorageBytes: 10 * 1024 * 1024 * 1024,
      reservedStorageBytes: 0,
      activeTransfers: 0,
      lastSeen: _now.subtract(const Duration(minutes: 4)),
      status: PeerStatus.temporarilyUnavailable,
      measuredLatencyMs: 32,
      reliabilityScore: 80,
    ),
  ];

  static final List<TransferRecord> transfers = [
    TransferRecord(
      transferId: 'demo-transfer-1',
      contentId: images.first.contentId,
      sourceNodeId: ownerNodeId,
      destinationNodeId: 'node-demo-tushar',
      direction: TransferDirection.upload,
      status: TransferStatus.transferring,
      bytesTransferred: 700000,
      totalBytes: 1843200,
      startedAt: _now,
      updatedAt: _now,
    ),
  ];

  static ImageManifest? imageById(String contentId) {
    for (final image in images) {
      if (image.contentId == contentId) return image;
    }
    return null;
  }

  static PeerTelemetry? peerById(String nodeId) {
    for (final peer in peers) {
      if (peer.nodeId == nodeId) return peer;
    }
    return null;
  }
}
