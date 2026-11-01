import '../../shared/models/enums.dart';
import '../../shared/models/peer_telemetry.dart';
import '../../shared/utils/json_helpers.dart';
import 'placement_eligibility.dart';

/// What happened to the optional decision model's recommendation.
enum ModelOutcome {
  /// No model configured (or the no-op model): deterministic order was used.
  notUsed,

  /// The recommendation passed validation and was used.
  accepted,

  /// The recommendation named an unknown or duplicate peer and was discarded.
  rejectedInvalid,

  /// The model threw.
  failed,

  /// The model did not answer in time.
  timedOut,
}

/// Debug record of one placement decision (PRD FR-05): the input snapshot, the
/// model's recommendation, the validator result and the final selection.
/// Contains telemetry and metadata only, never image content.
class PlacementAudit {
  const PlacementAudit({
    required this.createdAt,
    required this.sizeBytes,
    required this.importance,
    required this.desiredReplicas,
    required this.inputSnapshot,
    required this.rejected,
    required this.deterministicOrder,
    required this.modelOutcome,
    required this.selected,
    this.modelRecommendation,
    this.modelNote,
  });

  final DateTime createdAt;
  final int sizeBytes;
  final Importance importance;
  final int desiredReplicas;
  final List<PeerTelemetry> inputSnapshot;
  final Map<String, Set<IneligibleReason>> rejected;
  final List<String> deterministicOrder;
  final ModelOutcome modelOutcome;
  final List<String>? modelRecommendation;
  final String? modelNote;
  final List<String> selected;

  Json toJson() => {
        'createdAt': dateToJson(createdAt),
        'sizeBytes': sizeBytes,
        'importance': importance.wire,
        'desiredReplicas': desiredReplicas,
        'inputSnapshot': [for (final p in inputSnapshot) p.toJson()],
        'rejected': {
          for (final e in rejected.entries)
            e.key: [for (final r in e.value) r.name],
        },
        'deterministicOrder': deterministicOrder,
        'modelOutcome': modelOutcome.name,
        'modelRecommendation': modelRecommendation,
        'modelNote': modelNote,
        'selected': selected,
      };
}
