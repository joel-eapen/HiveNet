import '../../shared/models/peer_telemetry.dart';

/// Deterministic fallback weights (PRD FR-05):
/// `Score(n) = 0.35*C + 0.30*L + 0.20*U + 0.15*B`. Configurable and to be
/// benchmarked. A ranking aid only; hard eligibility checks come first.
class ScoreWeights {
  const ScoreWeights({
    this.capacity = 0.35,
    this.latency = 0.30,
    this.reliability = 0.20,
    this.bandwidth = 0.15,
  });

  final double capacity;
  final double latency;
  final double reliability;
  final double bandwidth;
}

abstract interface class NodeScorer {
  /// Returns 0..100 for an already-eligible peer.
  double score(PeerTelemetry peer);
}

class UnimplementedNodeScorer implements NodeScorer {
  const UnimplementedNodeScorer();

  @override
  double score(PeerTelemetry peer) =>
      throw UnimplementedError('NodeScorer: Milestone 4');
}
