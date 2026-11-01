import '../../shared/models/peer_telemetry.dart';
import 'storage_router.dart';

/// Optional AI placement ranker (PRD FR-05; Laya preferred, Jev alternative).
///
/// FR-09A: this interface is deliberately limited to ordering peers that the
/// deterministic filter already accepted. It has no method that grants access,
/// distributes keys or makes authorization decisions, and must not gain one.
abstract interface class DecisionModelAdapter {
  /// Returns node IDs ordered best-first. Receives telemetry and upload
  /// metadata only, never image content. Output is re-validated by the
  /// deterministic validator before use.
  Future<List<String>> rank(
    PlacementRequest request,
    List<PeerTelemetry> eligible,
  );
}

/// Default adapter: preserves input order. Used when no model is configured or
/// the endpoint is unavailable.
class NoopDecisionModel implements DecisionModelAdapter {
  const NoopDecisionModel();

  @override
  Future<List<String>> rank(
    PlacementRequest request,
    List<PeerTelemetry> eligible,
  ) async =>
      [for (final peer in eligible) peer.nodeId];
}
