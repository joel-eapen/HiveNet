import '../../shared/models/enums.dart';
import '../../shared/models/peer_telemetry.dart';
import '../../shared/utils/json_helpers.dart';
import 'node_scorer.dart';
import 'placement_eligibility.dart';

/// Why a placement came out the way it did (PRD FR-05): who was considered, who
/// was ruled out and why, each candidate's score, and who was chosen. Telemetry
/// and numbers only, never image content.
class PlacementAudit {
  const PlacementAudit({
    required this.createdAt,
    required this.sizeBytes,
    required this.importance,
    required this.desiredReplicas,
    required this.inputSnapshot,
    required this.rejected,
    required this.scores,
    required this.ranking,
    required this.selected,
  });

  final DateTime createdAt;
  final int sizeBytes;
  final Importance importance;
  final int desiredReplicas;
  final List<PeerTelemetry> inputSnapshot;

  /// nodeId -> every reason it was ruled out.
  final Map<String, Set<IneligibleReason>> rejected;

  /// nodeId -> score breakdown, for every peer that passed the hard filter.
  final Map<String, ScoreBreakdown> scores;

  /// Eligible node ids, best score first.
  final List<String> ranking;
  final List<String> selected;

  Json toJson() => {
        'createdAt': dateToJson(createdAt),
        'sizeBytes': sizeBytes,
        'importance': importance.wire,
        'desiredReplicas': desiredReplicas,
        'inputSnapshot': [for (final p in inputSnapshot) p.toJson()],
        'rejected': {
          for (final e in rejected.entries) e.key: [for (final r in e.value) r.name],
        },
        'scores': {for (final e in scores.entries) e.key: e.value.toJson()},
        'ranking': ranking,
        'selected': selected,
      };
}
