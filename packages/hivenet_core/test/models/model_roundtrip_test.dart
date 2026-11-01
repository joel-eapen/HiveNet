import 'dart:convert';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

/// Encodes through real JSON text so we also catch non-encodable values.
Json viaJson(Json json) => jsonDecode(jsonEncode(json)) as Json;

void main() {
  final t = DateTime.utc(2026, 11, 1, 12);

  test('PeerTelemetry', () {
    final m = PeerTelemetry(
      nodeId: 'n1', deviceName: 'Pixel', protocolVersion: 1,
      ipAddresses: const ['192.168.1.5'], port: 45678,
      availableStorageBytes: 100, totalStorageBytes: 200,
      reservedStorageBytes: 10, activeTransfers: 1, lastSeen: t,
      status: PeerStatus.online, measuredLatencyMs: 12,
      bandwidthEstimate: 5000, reliabilityScore: 88.5,
    );
    final json = viaJson(m.toJson());
    expect(PeerTelemetry.fromJson(json).toJson(), json);
  });

  test('ImageManifest', () {
    final m = ImageManifest(
      contentId: 'abc123', ownerNodeId: 'n1', fileName: 'a.jpg',
      mimeType: 'image/jpeg', fileSizeBytes: 1000, width: 10, height: 20,
      importance: Importance.important,
      visibility: ImageVisibility.selectedDevices,
      desiredReplicationFactor: 3, createdAt: t, manifestVersion: 4,
      availabilityStatus: AvailabilityStatus.underReplicated,
      thumbnailReference: 'thumb', ciphertextHash: 'h',
      encryptionMetadata: const {'cipher': 'AES-256-GCM'},
    );
    final json = viaJson(m.toJson());
    expect(ImageManifest.fromJson(json).toJson(), json);
  });

  test('manifest JSON contains no key material fields', () {
    final keys = ImageManifest(
      contentId: 'abc', ownerNodeId: 'n', fileName: 'f', mimeType: 'm',
      fileSizeBytes: 1, width: 1, height: 1, importance: Importance.normal,
      visibility: ImageVisibility.private, desiredReplicationFactor: 2,
      createdAt: t, manifestVersion: 1,
      availabilityStatus: AvailabilityStatus.pending,
    ).toJson().keys.map((k) => k.toLowerCase());
    expect(keys.any((k) => k.contains('key') || k.contains('secret')), isFalse);
  });

  test('ReplicaRecord', () {
    final m = ReplicaRecord(
      contentId: 'c', nodeId: 'n', state: ReplicaState.storedVerified,
      verified: true, ciphertextHash: 'h', storedAt: t, lastVerifiedAt: t,
      lastSeenAt: t,
    );
    final json = viaJson(m.toJson());
    expect(ReplicaRecord.fromJson(json).toJson(), json);
  });

  test('UploadJob and TransferRecord', () {
    final job = UploadJob(
      jobId: 'j', contentId: 'c', status: UploadState.retryPending,
      requestedReplicationFactor: 2, createdAt: t, failureReason: 'offline',
    );
    final jj = viaJson(job.toJson());
    expect(UploadJob.fromJson(jj).toJson(), jj);

    final tr = TransferRecord(
      transferId: 't', contentId: 'c', sourceNodeId: 'a',
      destinationNodeId: 'b', direction: TransferDirection.upload,
      status: TransferStatus.transferring, bytesTransferred: 50,
      totalBytes: 200, startedAt: t, updatedAt: t,
    );
    final tj = viaJson(tr.toJson());
    expect(TransferRecord.fromJson(tj).toJson(), tj);
    expect(tr.progress, 0.25);
  });

  test('TrustedDevice, DeviceKey, WrappedImageKey', () {
    final d = TrustedDevice(
      nodeId: 'n', publicKey: 'pk', fingerprint: 'fp', displayName: 'Tushar',
      pairedAt: t, trustStatus: TrustStatus.paired,
    );
    final dj = viaJson(d.toJson());
    expect(TrustedDevice.fromJson(dj).toJson(), dj);

    final k = DeviceKey(
      nodeId: 'n', publicKey: 'pk', keyAlgorithm: 'ed25519',
      fingerprint: 'fp', createdAt: t,
    );
    final kj = viaJson(k.toJson());
    expect(DeviceKey.fromJson(kj).toJson(), kj);

    final w = WrappedImageKey(
      contentId: 'c', recipientNodeId: 'n', wrappedKey: 'wk', keyVersion: 1,
      createdAt: t, expiresAt: t.add(const Duration(days: 1)),
    );
    final wj = viaJson(w.toJson());
    expect(WrappedImageKey.fromJson(wj).toJson(), wj);
  });

  test('AccessGrant and activity window', () {
    final g = AccessGrant(
      contentId: 'c', granteeNodeId: 'n', permission: PermissionType.view,
      grantedBy: 'owner', grantVersion: 2, keyVersion: 1, createdAt: t,
      expiresAt: t.add(const Duration(hours: 1)), signature: 'sig',
    );
    final json = viaJson(g.toJson());
    expect(AccessGrant.fromJson(json).toJson(), json);
    expect(g.isActiveAt(t), isTrue);
    expect(g.isActiveAt(t.add(const Duration(hours: 2))), isFalse);
    final revoked = AccessGrant(
      contentId: 'c', granteeNodeId: 'n', permission: PermissionType.view,
      grantedBy: 'owner', grantVersion: 3, keyVersion: 1, createdAt: t,
      revokedAt: t,
    );
    expect(revoked.isActiveAt(t), isFalse);
  });

  test('ManifestEvent, HiveError, MessageEnvelope', () {
    final e = ManifestEvent(
      eventId: 'e', contentId: 'c', originNodeId: 'n', manifestVersion: 2,
      eventType: ManifestEventType.tombstone, payload: const {'x': 1},
      createdAt: t, signature: 's',
    );
    final ej = viaJson(e.toJson());
    expect(ManifestEvent.fromJson(ej).toJson(), ej);

    const err = HiveError(
      code: HiveErrorCode.storageFull, message: 'full', isRetryable: true);
    final rj = viaJson(err.toJson());
    expect(HiveError.fromJson(rj).toJson(), rj);

    const msg = MessageEnvelope(
      type: MessageType.getImage, requestId: 'r', senderNodeId: 'n',
      contentId: 'c', payload: {'a': 'b'},
    );
    final mj = viaJson(msg.toJson());
    expect(MessageEnvelope.fromJson(mj).toJson(), mj);
    expect(msg.protocolVersion, kProtocolVersion);
  });
}
