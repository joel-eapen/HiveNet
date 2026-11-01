import '../../shared/models/enums.dart';
import '../../shared/models/peer_telemetry.dart';
import 'placement_audit.dart';

class PlacementRequest {
  const PlacementRequest({
    required this.sizeBytes,
    required this.importance,
    this.excludeNodeIds = const {},
  });

  /// Metadata only. Image content is never sent to a decision model.
  final int sizeBytes;
  final Importance importance;
  final Set<String> excludeNodeIds;

  int get desiredReplicas => importance.desiredReplicationFactor;
}

class PlacementPlan {
  const PlacementPlan({
    required this.targetNodeIds,
    required this.desiredReplicas,
    this.audit,
  });

  /// Distinct storage peers, best first.
  final List<String> targetNodeIds;
  final int desiredReplicas;

  /// How this plan was reached, for debugging. Null for hand-built plans.
  final PlacementAudit? audit;

  /// True when too few eligible peers exist. The upload must then stay
  /// `pending` or `under_replicated`, never report full success.
  bool get isShortfall => targetNodeIds.length < desiredReplicas;
}

/// Chooses where to store copies: filter out unfit peers, score the rest, take
/// the best. Plain code, always available locally (PRD FR-05).
abstract interface class StorageRouter {
  Future<PlacementPlan> plan(
    PlacementRequest request,
    List<PeerTelemetry> candidates,
  );
}

class UnimplementedStorageRouter implements StorageRouter {
  const UnimplementedStorageRouter();

  @override
  Future<PlacementPlan> plan(
    PlacementRequest request,
    List<PeerTelemetry> candidates,
  ) =>
      throw UnimplementedError('StorageRouter: Milestone 4');
}
