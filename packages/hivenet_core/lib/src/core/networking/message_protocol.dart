import '../../shared/models/enums.dart';
import '../../shared/models/protocol_constants.dart';
import '../../shared/utils/json_helpers.dart';

/// Envelope for every peer message (PRD FR-09B): protocol version,
/// request/operation ID, sender identity, content ID and a typed payload.
///
/// [senderNodeId] is a claim only. Receivers must bind it to the authenticated
/// connection and must not trust it on its own.
class MessageEnvelope {
  const MessageEnvelope({
    required this.type,
    required this.requestId,
    required this.senderNodeId,
    this.contentId,
    this.payload = const {},
    this.protocolVersion = kProtocolVersion,
  });

  final int protocolVersion;
  final MessageType type;
  final String requestId;
  final String senderNodeId;
  final String? contentId;
  final Json payload;

  Json toJson() => {
        'v': protocolVersion,
        'type': type.wire,
        'requestId': requestId,
        'sender': senderNodeId,
        'contentId': contentId,
        'payload': payload,
      };

  factory MessageEnvelope.fromJson(Json json) => MessageEnvelope(
        protocolVersion: json['v']! as int,
        type: enumFromWire(MessageType.values, json['type']! as String),
        requestId: json['requestId']! as String,
        senderNodeId: json['sender']! as String,
        contentId: json['contentId'] as String?,
        payload: Map<String, Object?>.from(json['payload'] as Map? ?? {}),
      );
}
