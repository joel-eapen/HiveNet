import '../../shared/models/peer_telemetry.dart';
import 'node_scorer.dart';
import 'placement_audit.dart';
import 'placement_eligibility.dart';
import 'storage_router.dart';

/// Chooses storage peers with plain code (PRD FR-05):
///
/// 1. Hard filter: drop peers that are untrusted, offline, stale, overloaded,
///    too full, on a nearly empty battery, or on another protocol version.
/// 2. Score the rest from storage, latency, bandwidth, battery, uptime and load.
/// 3. Take the highest scores.
///
/// No model, no network call, no randomness: the same inputs give the same
/// plan, and every decision can be explained from its [PlacementAudit].
class DeterministicStorageRouter implements StorageRouter {
  DeterministicStorageRouter({
    required this.trustedNodeIds,
    NodeScorer? scorer,
    this.policy = const EligibilityPolicy(),
    DateTime Function()? clock,
    this.onAudit,
  })  : scorer = scorer ?? const DeterministicNodeScorer(),
        _clock = clock ?? DateTime.now;

  /// Paired, non-revoked peers. Looked up per plan so revocations apply
  /// immediately.
  final Future<Set<String>> Function() trustedNodeIds;
  final NodeScorer scorer;
  final EligibilityPolicy policy;
  final DateTime Function() _clock;

  /// Receives every decision record, for logging or a debug screen.
  final void Function(PlacementAudit audit)? onAudit;

  @override
  Future<PlacementPlan> plan(
    PlacementRequest request,
    List<PeerTelemetry> candidates,
  ) async {
    final now = _clock();
    final unique = _newestPerNode(candidates);
    final result = filterEligible(
      request: request,
      candidates: unique,
      trustedNodeIds: await trustedNodeIds(),
      now: now,
      policy: policy,
    );

    final scores = {for (final p in result.eligible) p.nodeId: scorer.breakdown(p)};

    // Highest score first; the node id breaks ties so the order is reproducible.
    final ranked = [...result.eligible]..sort((a, b) {
        final bySore = scores[b.nodeId]!.total.compareTo(scores[a.nodeId]!.total);
        return bySore != 0 ? bySore : a.nodeId.compareTo(b.nodeId);
      });
    final ranking = [for (final p in ranked) p.nodeId];
    final selected = ranking.take(request.desiredReplicas).toList();

    final audit = PlacementAudit(
      createdAt: now,
      sizeBytes: request.sizeBytes,
      importance: request.importance,
      desiredReplicas: request.desiredReplicas,
      inputSnapshot: unique,
      rejected: result.rejected,
      scores: scores,
      ranking: ranking,
      selected: selected,
    );
    onAudit?.call(audit);

    return PlacementPlan(
      targetNodeIds: selected,
      desiredReplicas: request.desiredReplicas,
      audit: audit,
    );
  }

  /// Keeps one entry per node, preferring the freshest report.
  List<PeerTelemetry> _newestPerNode(List<PeerTelemetry> candidates) {
    final byId = <String, PeerTelemetry>{};
    for (final p in candidates) {
      final existing = byId[p.nodeId];
      if (existing == null || p.lastSeen.isAfter(existing.lastSeen)) {
        byId[p.nodeId] = p;
      }
    }
    return byId.values.toList();
  }
}
