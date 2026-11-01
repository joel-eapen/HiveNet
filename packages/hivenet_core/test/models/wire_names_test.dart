import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

/// Locks wire names. Changing one is a protocol break: bump the protocol
/// version deliberately instead of editing this test casually.
void main() {
  Map<String, String> wires<T extends WireEnum>(List<T> values) =>
      {for (final v in values) (v as Enum).name: v.wire};

  test('Importance', () {
    expect(wires(Importance.values), {'normal': 'normal', 'important': 'important'});
  });

  test('ImageVisibility', () {
    expect(wires(ImageVisibility.values), {
      'private': 'private',
      'selectedDevices': 'selected_devices',
      'networkShared': 'network_shared',
    });
  });

  test('UploadState', () {
    expect(wires(UploadState.values), {
      'created': 'CREATED',
      'reserving': 'RESERVING',
      'transferring': 'TRANSFERRING',
      'verifying': 'VERIFYING',
      'committing': 'COMMITTING',
      'replicating': 'REPLICATING',
      'completed': 'COMPLETED',
      'retryPending': 'RETRY_PENDING',
      'failed': 'FAILED',
      'underReplicated': 'UNDER_REPLICATED',
    });
  });

  test('ReplicaState', () {
    expect(wires(ReplicaState.values), {
      'storedVerified': 'stored_verified',
      'onlineServable': 'online_servable',
      'temporarilyUnavailable': 'temporarily_unavailable',
      'missing': 'missing',
      'corrupted': 'corrupted',
    });
  });

  test('AvailabilityStatus', () {
    expect(wires(AvailabilityStatus.values), {
      'available': 'available',
      'temporarilyUnavailable': 'temporarily_unavailable',
      'underReplicated': 'under_replicated',
      'pending': 'pending',
      'deleted': 'deleted',
    });
  });

  test('PeerStatus, TrustStatus, PermissionType', () {
    expect(wires(PeerStatus.values), {
      'discovered': 'discovered',
      'online': 'online',
      'temporarilyUnavailable': 'temporarily_unavailable',
      'offline': 'offline',
    });
    expect(wires(TrustStatus.values),
        {'unpaired': 'unpaired', 'paired': 'paired', 'revoked': 'revoked'});
    expect(wires(PermissionType.values), {
      'view': 'view',
      'retrieve': 'retrieve',
      'storeEncrypted': 'store_encrypted',
    });
  });

  test('MessageType covers every PRD message', () {
    const prdMessages = {
      'STORAGE_RESERVE', 'STORAGE_ACCEPT', 'STORAGE_REJECT', 'UPLOAD_BEGIN',
      'CHUNK_DATA', 'CHUNK_ACK', 'UPLOAD_COMMIT', 'REPLICA_COMMITTED',
      'GET_IMAGE', 'IMAGE_LOCATE', 'IMAGE_AVAILABLE', 'ACCESS_CHECK',
      'ACCESS_GRANTED', 'ACCESS_DENIED', 'IMAGE_BEGIN', 'IMAGE_COMPLETE',
      'IMAGE_VERIFY', 'IMAGE_NOT_FOUND', 'TRANSFER_RESUME', 'ACCESS_REQUEST',
      'ACCESS_GRANT', 'ACCESS_REVOKE', 'KEY_REQUEST', 'KEY_DELIVERY',
    };
    final actual = MessageType.values.map((m) => m.wire).toSet();
    expect(actual.containsAll(prdMessages), isTrue,
        reason: 'missing: ${prdMessages.difference(actual)}');
    expect(actual.length, MessageType.values.length, reason: 'duplicate wire');
  });

  test('every enum has unique wire names and round-trips', () {
    for (final values in <List<WireEnum>>[
      Importance.values, ImageVisibility.values, UploadState.values,
      ReplicaState.values, AvailabilityStatus.values, PeerStatus.values,
      TrustStatus.values, PermissionType.values, DevicePlatform.values,
      TransferDirection.values, TransferStatus.values,
      ManifestEventType.values, MessageType.values, HiveErrorCode.values,
    ]) {
      expect(values.map((v) => v.wire).toSet().length, values.length);
      for (final v in values) {
        expect(enumFromWire(values, v.wire), same(v));
      }
    }
  });

  test('unknown wire value throws', () {
    expect(() => enumFromWire(Importance.values, 'nope'),
        throwsFormatException);
  });
}
