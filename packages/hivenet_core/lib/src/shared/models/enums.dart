/// Shared enums for the HiveNet contract.
///
/// Every enum carries a stable [WireEnum.wire] name used in JSON, SQLite and
/// protocol messages. Renaming a Dart identifier must never change the wire
/// name; `test/models/wire_names_test.dart` locks these values.
library;

abstract interface class WireEnum {
  String get wire;
}

/// Looks up the enum value whose wire name is [wire].
T enumFromWire<T extends WireEnum>(List<T> values, String wire) {
  for (final value in values) {
    if (value.wire == wire) return value;
  }
  throw FormatException('Unknown $T wire value: "$wire"');
}

/// PRD FR-04.
enum Importance implements WireEnum {
  normal('normal'),
  important('important');

  const Importance(this.wire);
  @override
  final String wire;

  /// Desired replica count: 2 for normal, 3 for important (FR-04).
  int get desiredReplicationFactor => this == normal ? 2 : 3;
}

/// PRD FR-09 / FR-09A visibility modes. Named `ImageVisibility` to avoid
/// clashing with Flutter's `Visibility` widget.
enum ImageVisibility implements WireEnum {
  private('private'),
  selectedDevices('selected_devices'),
  networkShared('network_shared');

  const ImageVisibility(this.wire);
  @override
  final String wire;
}

/// PRD §13.1 upload state machine.
enum UploadState implements WireEnum {
  created('CREATED'),
  reserving('RESERVING'),
  transferring('TRANSFERRING'),
  verifying('VERIFYING'),
  committing('COMMITTING'),
  replicating('REPLICATING'),
  completed('COMPLETED'),
  retryPending('RETRY_PENDING'),
  failed('FAILED'),
  underReplicated('UNDER_REPLICATED');

  const UploadState(this.wire);
  @override
  final String wire;

  /// States reachable from each state. `completed` is reachable only from
  /// `replicating`, so success can never skip verification (no false success).
  static const Map<UploadState, Set<UploadState>> allowedTransitions = {
    created: {reserving, failed},
    reserving: {transferring, retryPending, failed, underReplicated},
    transferring: {verifying, retryPending, failed},
    verifying: {committing, retryPending, failed},
    committing: {replicating, retryPending, failed},
    replicating: {completed, underReplicated, retryPending, failed},
    retryPending: {reserving, failed, underReplicated},
    underReplicated: {reserving, replicating, failed},
    completed: {},
    failed: {},
  };

  bool canTransitionTo(UploadState next) =>
      allowedTransitions[this]!.contains(next);

  bool get isTerminal => allowedTransitions[this]!.isEmpty;
}

/// PRD §13.2. Durable and reachability states are kept separate.
enum ReplicaState implements WireEnum {
  storedVerified('stored_verified'),
  onlineServable('online_servable'),
  temporarilyUnavailable('temporarily_unavailable'),
  missing('missing'),
  corrupted('corrupted');

  const ReplicaState(this.wire);
  @override
  final String wire;
}

/// PRD FR-07 gallery availability states.
enum AvailabilityStatus implements WireEnum {
  available('available'),
  temporarilyUnavailable('temporarily_unavailable'),
  underReplicated('under_replicated'),
  pending('pending'),
  deleted('deleted');

  const AvailabilityStatus(this.wire);
  @override
  final String wire;
}

/// Peer reachability. A backgrounded or suspended peer is
/// `temporarilyUnavailable` once its lease expires (PRD §10.1).
enum PeerStatus implements WireEnum {
  discovered('discovered'),
  online('online'),
  temporarilyUnavailable('temporarily_unavailable'),
  offline('offline');

  const PeerStatus(this.wire);
  @override
  final String wire;
}

enum TrustStatus implements WireEnum {
  unpaired('unpaired'),
  paired('paired'),
  revoked('revoked');

  const TrustStatus(this.wire);
  @override
  final String wire;
}

/// PRD §6.7. Permissions are independent: none implies another (FR-09A).
enum PermissionType implements WireEnum {
  view('view'),
  retrieve('retrieve'),
  storeEncrypted('store_encrypted');

  const PermissionType(this.wire);
  @override
  final String wire;
}

enum DevicePlatform implements WireEnum {
  android('android'),
  ios('ios');

  const DevicePlatform(this.wire);
  @override
  final String wire;
}

enum TransferDirection implements WireEnum {
  upload('upload'),
  download('download');

  const TransferDirection(this.wire);
  @override
  final String wire;
}

enum TransferStatus implements WireEnum {
  queued('queued'),
  connecting('connecting'),
  transferring('transferring'),
  verifying('verifying'),
  completed('completed'),
  paused('paused'),
  failed('failed');

  const TransferStatus(this.wire);
  @override
  final String wire;
}

enum ManifestEventType implements WireEnum {
  created('created'),
  updated('updated'),
  accessGranted('access_granted'),
  accessRevoked('access_revoked'),
  tombstone('tombstone');

  const ManifestEventType(this.wire);
  @override
  final String wire;
}

/// Logical peer protocol messages (FR-06, FR-08, FR-09B).
enum MessageType implements WireEnum {
  // Storage (FR-06)
  storageReserve('STORAGE_RESERVE'),
  storageAccept('STORAGE_ACCEPT'),
  storageReject('STORAGE_REJECT'),
  uploadBegin('UPLOAD_BEGIN'),
  uploadCommit('UPLOAD_COMMIT'),
  replicaCommitted('REPLICA_COMMITTED'),
  // Retrieval (FR-08)
  getImage('GET_IMAGE'),
  imageLocate('IMAGE_LOCATE'),
  imageAvailable('IMAGE_AVAILABLE'),
  imageBegin('IMAGE_BEGIN'),
  imageComplete('IMAGE_COMPLETE'),
  imageVerify('IMAGE_VERIFY'),
  imageNotFound('IMAGE_NOT_FOUND'),
  transferResume('TRANSFER_RESUME'),
  // Shared by upload and retrieval
  chunkData('CHUNK_DATA'),
  chunkAck('CHUNK_ACK'),
  // Access control (FR-08, FR-09B)
  accessRequest('ACCESS_REQUEST'),
  accessCheck('ACCESS_CHECK'),
  accessGrant('ACCESS_GRANT'),
  accessRevoke('ACCESS_REVOKE'),
  accessGranted('ACCESS_GRANTED'),
  accessDenied('ACCESS_DENIED'),
  keyRequest('KEY_REQUEST'),
  keyDelivery('KEY_DELIVERY'),
  // Liveness and pairing
  heartbeat('HEARTBEAT'),
  pairRequest('PAIR_REQUEST'),
  pairConfirm('PAIR_CONFIRM'),
  error('ERROR');

  const MessageType(this.wire);
  @override
  final String wire;
}

/// Backend error codes mapped to user-facing messages in the frontend.
enum HiveErrorCode implements WireEnum {
  noPeersAvailable('no_peers_available'),
  insufficientReplicaTargets('insufficient_replica_targets'),
  peerDisconnected('peer_disconnected'),
  accessDenied('access_denied'),
  keyUnavailable('key_unavailable'),
  integrityMismatch('integrity_mismatch'),
  unsupportedImage('unsupported_image'),
  compressionFailed('compression_failed'),
  storageFull('storage_full'),
  backendUnavailable('backend_unavailable'),
  malformedMessage('malformed_message'),
  oversizedMessage('oversized_message'),
  unauthenticated('unauthenticated');

  const HiveErrorCode(this.wire);
  @override
  final String wire;
}
