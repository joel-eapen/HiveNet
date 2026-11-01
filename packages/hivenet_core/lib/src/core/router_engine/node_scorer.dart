import 'dart:math';

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

  double get total => capacity + latency + reliability + bandwidth;
}

/// Normalization settings. The defaults are starting points to benchmark on
/// real devices, not tuned values.
class ScoreConfig {
  const ScoreConfig({
    this.weights = const ScoreWeights(),
    this.latencyCeilingMs = 500,
    this.bandwidthTargetBytesPerSecond = 12500000, // about 100 Mbit/s
    this.unknownScore = 50,
  });

  final ScoreWeights weights;

  /// Latency at or above this scores 0; 0 ms scores 100.
  final int latencyCeilingMs;

  /// Throughput at or above this scores 100.
  final int bandwidthTargetBytesPerSecond;

  /// Used for a missing latency or bandwidth measurement: neither a reward nor
  /// a penalty for a peer that simply has not been measured yet.
  final double unknownScore;
}

/// The four normalized components (each 0..100) and their weighted total.
class ScoreBreakdown {
  const ScoreBreakdown({
    required this.capacity,
    required this.latency,
    required this.reliability,
    required this.bandwidth,
    required this.total,
  });

  final double capacity;
  final double latency;
  final double reliability;
  final double bandwidth;
  final double total;
}

abstract interface class NodeScorer {
  /// Returns 0..100 for an already-eligible peer.
  double score(PeerTelemetry peer);
}

/// Weighted score from telemetry alone, so the same input always gives the same
/// output. Always available locally; no network or model involved.
class DeterministicNodeScorer implements NodeScorer {
  const DeterministicNodeScorer([this.config = const ScoreConfig()]);

  final ScoreConfig config;

  @override
  double score(PeerTelemetry peer) => breakdown(peer).total;

  ScoreBreakdown breakdown(PeerTelemetry peer) {
    final c = _capacity(peer);
    final l = _latency(peer);
    final u = peer.reliabilityScore.clamp(0, 100).toDouble();
    final b = _bandwidth(peer);
    final w = config.weights;
    final total = w.capacity * c + w.latency * l + w.reliability * u + w.bandwidth * b;
    return ScoreBreakdown(
      capacity: c,
      latency: l,
      reliability: u,
      bandwidth: b,
      total: total.clamp(0, 100).toDouble(),
    );
  }

  /// Share of the peer's disk that is free after its own reservations.
  double _capacity(PeerTelemetry p) {
    if (p.totalStorageBytes <= 0) return 0;
    final free = max(0, p.availableStorageBytes - p.reservedStorageBytes);
    return (100 * free / p.totalStorageBytes).clamp(0, 100).toDouble();
  }

  double _latency(PeerTelemetry p) {
    final ms = p.measuredLatencyMs;
    if (ms == null) return config.unknownScore;
    return (100 * (1 - ms / config.latencyCeilingMs)).clamp(0, 100).toDouble();
  }

  double _bandwidth(PeerTelemetry p) {
    final bw = p.bandwidthEstimate;
    if (bw == null) return config.unknownScore;
    return (100 * bw / config.bandwidthTargetBytesPerSecond)
        .clamp(0, 100)
        .toDouble();
  }
}

class UnimplementedNodeScorer implements NodeScorer {
  const UnimplementedNodeScorer();

  @override
  double score(PeerTelemetry peer) =>
      throw UnimplementedError('NodeScorer: use DeterministicNodeScorer');
}
