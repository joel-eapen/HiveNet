import '../utils/json_helpers.dart';
import 'enums.dart';

/// Evidence of a believed replica location (PRD §6.3). Not proof the peer is
/// online: revalidate before retrieval.
class ReplicaRecord {
  const ReplicaRecord({
    required this.contentId,
    required this.nodeId,
    required this.state,
    required this.verified,
    this.ciphertextHash,
    this.storedAt,
    this.lastVerifiedAt,
    this.lastSeenAt,
  });

  final String contentId;
  final String nodeId;
  final ReplicaState state;
  final bool verified;
  final String? ciphertextHash;
  final DateTime? storedAt;
  final DateTime? lastVerifiedAt;
  final DateTime? lastSeenAt;

  Json toJson() => {
        'contentId': contentId,
        'nodeId': nodeId,
        'state': state.wire,
        'verified': verified,
        'ciphertextHash': ciphertextHash,
        'storedAt': optionalDateToJson(storedAt),
        'lastVerifiedAt': optionalDateToJson(lastVerifiedAt),
        'lastSeenAt': optionalDateToJson(lastSeenAt),
      };

  factory ReplicaRecord.fromJson(Json json) => ReplicaRecord(
        contentId: json['contentId']! as String,
        nodeId: json['nodeId']! as String,
        state: enumFromWire(ReplicaState.values, json['state']! as String),
        verified: json['verified']! as bool,
        ciphertextHash: json['ciphertextHash'] as String?,
        storedAt: optionalDateFromJson(json['storedAt']),
        lastVerifiedAt: optionalDateFromJson(json['lastVerifiedAt']),
        lastSeenAt: optionalDateFromJson(json['lastSeenAt']),
      );
}
