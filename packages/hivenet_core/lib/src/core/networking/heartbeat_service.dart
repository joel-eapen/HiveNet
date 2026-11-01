import '../../shared/models/enums.dart';

class PeerStatusChange {
  const PeerStatusChange(this.nodeId, this.status);
  final String nodeId;
  final PeerStatus status;
}

/// Heartbeat/lease tracking (PRD FR-02, FR-11). A peer that misses the
/// configured threshold becomes offline; stale telemetry never proves a peer
/// can accept a write.
abstract interface class HeartbeatService {
  Stream<PeerStatusChange> get statusChanges;
  Future<void> start();
  Future<void> stop();
  void recordHeartbeat(String nodeId);
}

class UnimplementedHeartbeatService implements HeartbeatService {
  const UnimplementedHeartbeatService();

  @override
  Stream<PeerStatusChange> get statusChanges => const Stream.empty();

  @override
  Future<void> start() =>
      throw UnimplementedError('HeartbeatService: Milestone 2');

  @override
  Future<void> stop() async {}

  @override
  void recordHeartbeat(String nodeId) =>
      throw UnimplementedError('HeartbeatService: Milestone 2');
}
