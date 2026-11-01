import 'dart:math';

import '../../shared/models/peer_telemetry.dart';

/// How much each factor counts toward a peer's score. They should add up to 1.
///
/// Defaults (starting points to tune on real devices, not measured optima):
///
/// | factor    | weight | why                                                    |
/// |-----------|--------|--------------------------------------------------------|
/// | capacity  | 0.25   | room to keep storing, so the peer does not fill up     |
/// | latency   | 0.20   | quick to respond                                       |
/// | battery   | 0.20   | a phone about to die loses the copy it holds           |
/// | uptime    | 0.20   | has actually been reachable, and has been running a while |
/// | bandwidth | 0.10   | transfers finish sooner                                |
/// | load      | 0.05   | prefer peers that are not busy with other transfers    |
class ScoreWeights {
  const ScoreWeights({
    this.capacity = 0.25,
    this.latency = 0.20,
    this.battery = 0.20,
    this.uptime = 0.20,
    this.bandwidth = 0.10,
    this.load = 0.05,
  });

  final double capacity;
  final double latency;
  final double battery;
  final double uptime;
  final double bandwidth;
  final double load;

  double get total => capacity + latency + battery + uptime + bandwidth + load;
}

/// Normalization settings. Defaults are starting points to tune on real devices.
class ScoreConfig {
  const ScoreConfig({
    this.weights = const ScoreWeights(),
    this.latencyCeilingMs = 500,
    this.bandwidthTargetBytesPerSecond = 12500000, // about 100 Mbit/s
    this.sessionUptimeTarget = const Duration(hours: 1),
    this.lowBatteryPercent = 20,
    this.maxActiveTransfers = 2,
    this.observedAvailabilityShare = 0.7,
    this.unknownScore = 50,
  });

  final ScoreWeights weights;

  /// Latency at or above this scores 0; 0 ms scores 100.
  final int latencyCeilingMs;

  /// Throughput at or above this scores 100.
  final int bandwidthTargetBytesPerSecond;

  /// A peer whose app has run this long without a break gets full marks for
  /// session length.
  final Duration sessionUptimeTarget;

  /// Below this a peer on battery is penalized hard (its score is halved).
  final int lowBatteryPercent;

  /// Transfers at which the load factor reaches 0.
  final int maxActiveTransfers;

  /// Of the uptime factor, how much comes from "answered recent checks" and how
  /// much from "app has been running a while" (the rest).
  final double observedAvailabilityShare;

  /// Used when a measurement is missing: neither a reward nor a penalty for a
  /// peer that simply has not reported it yet.
  final double unknownScore;
}

/// The factors (each 0..100) and their weighted total, kept so a decision can
/// be explained afterwards.
class ScoreBreakdown {
  const ScoreBreakdown({
    required this.capacity,
    required this.latency,
    required this.battery,
    required this.uptime,
    required this.bandwidth,
    required this.load,
    required this.total,
  });

  final double capacity;
  final double latency;
  final double battery;
  final double uptime;
  final double bandwidth;
  final double load;
  final double total;

  Map<String, double> toJson() => {
        'capacity': capacity,
        'latency': latency,
        'battery': battery,
        'uptime': uptime,
        'bandwidth': bandwidth,
        'load': load,
        'total': total,
      };
}

abstract interface class NodeScorer {
  /// 0..100 for an already-eligible peer. Higher is a better place to store.
  double score(PeerTelemetry peer);

  ScoreBreakdown breakdown(PeerTelemetry peer);
}

/// Scores a peer from its reported numbers alone, in plain code. The same input
/// always gives the same score; nothing is learned, guessed or sent anywhere.
class DeterministicNodeScorer implements NodeScorer {
  const DeterministicNodeScorer([this.config = const ScoreConfig()]);

  final ScoreConfig config;

  @override
  double score(PeerTelemetry peer) => breakdown(peer).total;

  @override
  ScoreBreakdown breakdown(PeerTelemetry peer) {
    final c = _capacity(peer);
    final l = _latency(peer);
    final bat = _battery(peer);
    final up = _uptime(peer);
    final bw = _bandwidth(peer);
    final ld = _load(peer);
    final w = config.weights;
    final total = w.capacity * c +
        w.latency * l +
        w.battery * bat +
        w.uptime * up +
        w.bandwidth * bw +
        w.load * ld;
    return ScoreBreakdown(
      capacity: c,
      latency: l,
      battery: bat,
      uptime: up,
      bandwidth: bw,
      load: ld,
      total: total.clamp(0, 100).toDouble(),
    );
  }

  /// Share of the peer's shared space that is free after its own reservations.
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

  /// Plugged in is best. On battery the score follows the level, and halves
  /// below [ScoreConfig.lowBatteryPercent] so a nearly empty phone is avoided.
  double _battery(PeerTelemetry p) {
    if (p.isCharging == true) return 100;
    final level = p.batteryPercent;
    if (level == null) return config.unknownScore;
    final clamped = level.clamp(0, 100).toDouble();
    return clamped < config.lowBatteryPercent ? clamped / 2 : clamped;
  }

  /// Blend of "answered recent availability checks" and "app has been running
  /// without a break". Whichever is unknown is left out; if both are, neutral.
  double _uptime(PeerTelemetry p) {
    final observed = p.reliabilityScore?.clamp(0, 100).toDouble();
    final seconds = p.uptimeSeconds;
    final session = seconds == null
        ? null
        : (100 * seconds / config.sessionUptimeTarget.inSeconds).clamp(0, 100).toDouble();
    if (observed != null && session != null) {
      final share = config.observedAvailabilityShare;
      return share * observed + (1 - share) * session;
    }
    return observed ?? session ?? config.unknownScore;
  }

  double _bandwidth(PeerTelemetry p) {
    final bw = p.bandwidthEstimate;
    if (bw == null) return config.unknownScore;
    return (100 * bw / config.bandwidthTargetBytesPerSecond).clamp(0, 100).toDouble();
  }

  /// Idle is best; at the transfer limit this is 0.
  double _load(PeerTelemetry p) =>
      (100 * (1 - p.activeTransfers / config.maxActiveTransfers)).clamp(0, 100).toDouble();
}

class UnimplementedNodeScorer implements NodeScorer {
  const UnimplementedNodeScorer();

  @override
  double score(PeerTelemetry peer) =>
      throw UnimplementedError('NodeScorer: use DeterministicNodeScorer');

  @override
  ScoreBreakdown breakdown(PeerTelemetry peer) =>
      throw UnimplementedError('NodeScorer: use DeterministicNodeScorer');
}
