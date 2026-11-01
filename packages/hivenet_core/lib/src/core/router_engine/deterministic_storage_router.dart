import 'dart:async';

import '../../shared/models/peer_telemetry.dart';
import 'decision_model_adapter.dart';
import 'node_scorer.dart';
import 'placement_audit.dart';
import 'placement_eligibility.dart';
import 'storage_router.dart';

/// Placement in four steps (PRD FR-05):
///
/// 1. Hard eligibility filter ([filterEligible]).
/// 2. Deterministic score ranking ([NodeScorer]).
/// 3. Optional [DecisionModelAdapter] re-ranking, validated before use.
/// 4. Take the top `desiredReplicas`.
///
/// Guarantees that hold whatever the model does:
/// - only peers that passed step 1 can be selected;
/// - the same inputs give the same plan when no model reorders them;
/// - a slow, failing or misbehaving model costs at most [modelTimeout] and the
///   plan falls back to the deterministic order. Upload is never blocked.
class DeterministicStorageRouter implements StorageRouter {
  DeterministicStorageRouter({
    required this.trustedNodeIds,
    NodeScorer? scorer,
    DecisionModelAdapter? decisionModel,
    this.policy = const EligibilityPolicy(),
    this.modelTimeout = const Duration(seconds: 2),
    DateTime Function()? clock,
    this.onAudit,
  })  : scorer = scorer ?? const DeterministicNodeScorer(),
        decisionModel = decisionModel ?? const NoopDecisionModel(),
        _clock = clock ?? DateTime.now;

  /// Paired, non-revoked peers. Looked up per plan so revocations apply
  /// immediately.
  final Future<Set<String>> Function() trustedNodeIds;
  final NodeScorer scorer;
  final DecisionModelAdapter decisionModel;
  final EligibilityPolicy policy;
  final Duration modelTimeout;
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

    // Highest score first; node id breaks ties so the order is reproducible.
    final ranked = [...result.eligible]..sort((a, b) {
        final byScore = scorer.score(b).compareTo(scorer.score(a));
        return byScore != 0 ? byScore : a.nodeId.compareTo(b.nodeId);
      });
    final deterministicOrder = [for (final p in ranked) p.nodeId];

    final model = await _consultModel(request, ranked, deterministicOrder);
    final order = model.order ?? deterministicOrder;

    final selected = order.take(request.desiredReplicas).toList();
    final audit = PlacementAudit(
      createdAt: now,
      sizeBytes: request.sizeBytes,
      importance: request.importance,
      desiredReplicas: request.desiredReplicas,
      inputSnapshot: unique,
      rejected: result.rejected,
      deterministicOrder: deterministicOrder,
      modelOutcome: model.outcome,
      modelRecommendation: model.recommendation,
      modelNote: model.note,
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

  Future<_ModelResult> _consultModel(
    PlacementRequest request,
    List<PeerTelemetry> ranked,
    List<String> deterministicOrder,
  ) async {
    if (decisionModel is NoopDecisionModel || ranked.length < 2) {
      return const _ModelResult(ModelOutcome.notUsed);
    }

    List<String> recommendation;
    try {
      recommendation =
          await decisionModel.rank(request, ranked).timeout(modelTimeout);
    } on TimeoutException {
      return const _ModelResult(ModelOutcome.timedOut,
          note: 'model did not answer in time');
    } catch (e) {
      return _ModelResult(ModelOutcome.failed, note: e.runtimeType.toString());
    }

    // Validator: the model may only reorder peers that already passed the
    // hard filter. Anything else discards the whole recommendation.
    final allowed = deterministicOrder.toSet();
    final seen = <String>{};
    for (final id in recommendation) {
      if (!allowed.contains(id)) {
        return _ModelResult(ModelOutcome.rejectedInvalid,
            recommendation: recommendation,
            note: 'recommended a peer that is not eligible');
      }
      if (!seen.add(id)) {
        return _ModelResult(ModelOutcome.rejectedInvalid,
            recommendation: recommendation,
            note: 'recommended the same peer twice');
      }
    }

    // A partial ranking is fine: unmentioned peers follow in score order.
    final merged = [
      ...recommendation,
      ...deterministicOrder.where((id) => !seen.contains(id)),
    ];
    return _ModelResult(ModelOutcome.accepted,
        order: merged, recommendation: recommendation);
  }
}

class _ModelResult {
  const _ModelResult(this.outcome, {this.order, this.recommendation, this.note});

  final ModelOutcome outcome;
  final List<String>? order;
  final List<String>? recommendation;
  final String? note;
}
