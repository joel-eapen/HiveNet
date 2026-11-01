import '../../shared/models/peer_telemetry.dart';
import '../../shared/models/replica_record.dart';

/// Orders eligible replicas (online, trusted, verified) by latency, bandwidth
/// and reliability so the client can fall back to the next host (PRD FR-08).
abstract interface class ReplicaSelector {
  List<ReplicaRecord> rank(
    List<ReplicaRecord> replicas,
    Map<String, PeerTelemetry> telemetryByNodeId,
  );
}

class UnimplementedReplicaSelector implements ReplicaSelector {
  const UnimplementedReplicaSelector();

  @override
  List<ReplicaRecord> rank(
    List<ReplicaRecord> replicas,
    Map<String, PeerTelemetry> telemetryByNodeId,
  ) =>
      throw UnimplementedError('ReplicaSelector: Milestone 5');
}
