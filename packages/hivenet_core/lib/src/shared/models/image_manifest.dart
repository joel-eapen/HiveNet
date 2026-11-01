import '../utils/json_helpers.dart';
import 'enums.dart';

/// Gallery metadata for one image (PRD §6.2). Contains no key material and no
/// original bytes. `encryptionMetadata` holds only non-secret parameters such
/// as the cipher name and nonce.
class ImageManifest {
  const ImageManifest({
    required this.contentId,
    required this.ownerNodeId,
    required this.fileName,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.width,
    required this.height,
    required this.importance,
    required this.visibility,
    required this.desiredReplicationFactor,
    required this.createdAt,
    required this.manifestVersion,
    required this.availabilityStatus,
    this.thumbnailReference,
    this.ciphertextHash,
    this.encryptionMetadata = const {},
  });

  final String contentId;
  final String ownerNodeId;
  final String fileName;
  final String mimeType;
  final int fileSizeBytes;
  final int width;
  final int height;
  final String? thumbnailReference;
  final Importance importance;
  final ImageVisibility visibility;
  final int desiredReplicationFactor;
  final DateTime createdAt;

  /// Monotonic per-owner version (PRD FR-07).
  final int manifestVersion;
  final AvailabilityStatus availabilityStatus;
  final String? ciphertextHash;
  final Json encryptionMetadata;

  Json toJson() => {
        'contentId': contentId,
        'ownerNodeId': ownerNodeId,
        'fileName': fileName,
        'mimeType': mimeType,
        'fileSizeBytes': fileSizeBytes,
        'width': width,
        'height': height,
        'thumbnailReference': thumbnailReference,
        'importance': importance.wire,
        'visibility': visibility.wire,
        'desiredReplicationFactor': desiredReplicationFactor,
        'createdAt': dateToJson(createdAt),
        'manifestVersion': manifestVersion,
        'availabilityStatus': availabilityStatus.wire,
        'ciphertextHash': ciphertextHash,
        'encryptionMetadata': encryptionMetadata,
      };

  factory ImageManifest.fromJson(Json json) => ImageManifest(
        contentId: json['contentId']! as String,
        ownerNodeId: json['ownerNodeId']! as String,
        fileName: json['fileName']! as String,
        mimeType: json['mimeType']! as String,
        fileSizeBytes: json['fileSizeBytes']! as int,
        width: json['width']! as int,
        height: json['height']! as int,
        thumbnailReference: json['thumbnailReference'] as String?,
        importance:
            enumFromWire(Importance.values, json['importance']! as String),
        visibility: enumFromWire(
            ImageVisibility.values, json['visibility']! as String),
        desiredReplicationFactor: json['desiredReplicationFactor']! as int,
        createdAt: dateFromJson(json['createdAt']),
        manifestVersion: json['manifestVersion']! as int,
        availabilityStatus: enumFromWire(
            AvailabilityStatus.values, json['availabilityStatus']! as String),
        ciphertextHash: json['ciphertextHash'] as String?,
        encryptionMetadata:
            Map<String, Object?>.from(json['encryptionMetadata'] as Map? ?? {}),
      );
}
