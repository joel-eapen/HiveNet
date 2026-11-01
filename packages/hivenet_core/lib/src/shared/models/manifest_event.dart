import '../utils/json_helpers.dart';
import 'enums.dart';

/// Owner-authoritative manifest event (PRD §6.10). Ordering uses the
/// per-owner [manifestVersion], never wall-clock [createdAt].
class ManifestEvent {
  const ManifestEvent({
    required this.eventId,
    required this.contentId,
    required this.originNodeId,
    required this.manifestVersion,
    required this.eventType,
    required this.payload,
    required this.createdAt,
    this.signature,
  });

  final String eventId;
  final String contentId;
  final String originNodeId;
  final int manifestVersion;
  final ManifestEventType eventType;
  final Json payload;
  final DateTime createdAt;

  /// Base64 owner signature over the event.
  final String? signature;

  Json toJson() => {
        'eventId': eventId,
        'contentId': contentId,
        'originNodeId': originNodeId,
        'manifestVersion': manifestVersion,
        'eventType': eventType.wire,
        'payload': payload,
        'createdAt': dateToJson(createdAt),
        'signature': signature,
      };

  factory ManifestEvent.fromJson(Json json) => ManifestEvent(
        eventId: json['eventId']! as String,
        contentId: json['contentId']! as String,
        originNodeId: json['originNodeId']! as String,
        manifestVersion: json['manifestVersion']! as int,
        eventType: enumFromWire(
            ManifestEventType.values, json['eventType']! as String),
        payload: Map<String, Object?>.from(json['payload']! as Map),
        createdAt: dateFromJson(json['createdAt']),
        signature: json['signature'] as String?,
      );
}
