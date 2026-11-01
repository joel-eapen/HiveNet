import '../utils/json_helpers.dart';
import 'enums.dart';

/// A paired device (PRD §6.6). `publicKey` is base64; never a private key.
class TrustedDevice {
  const TrustedDevice({
    required this.nodeId,
    required this.publicKey,
    required this.fingerprint,
    required this.displayName,
    required this.pairedAt,
    required this.trustStatus,
    this.revokedAt,
  });

  final String nodeId;
  final String publicKey;
  final String fingerprint;
  final String displayName;
  final DateTime pairedAt;
  final DateTime? revokedAt;
  final TrustStatus trustStatus;

  Json toJson() => {
        'nodeId': nodeId,
        'publicKey': publicKey,
        'fingerprint': fingerprint,
        'displayName': displayName,
        'pairedAt': dateToJson(pairedAt),
        'revokedAt': optionalDateToJson(revokedAt),
        'trustStatus': trustStatus.wire,
      };

  factory TrustedDevice.fromJson(Json json) => TrustedDevice(
        nodeId: json['nodeId']! as String,
        publicKey: json['publicKey']! as String,
        fingerprint: json['fingerprint']! as String,
        displayName: json['displayName']! as String,
        pairedAt: dateFromJson(json['pairedAt']),
        revokedAt: optionalDateFromJson(json['revokedAt']),
        trustStatus:
            enumFromWire(TrustStatus.values, json['trustStatus']! as String),
      );
}

/// Owner-signed, device-bound grant (PRD §6.7, §13.3).
class AccessGrant {
  const AccessGrant({
    required this.contentId,
    required this.granteeNodeId,
    required this.permission,
    required this.grantedBy,
    required this.grantVersion,
    required this.keyVersion,
    required this.createdAt,
    this.expiresAt,
    this.revokedAt,
    this.signature,
  });

  final String contentId;
  final String granteeNodeId;
  final PermissionType permission;
  final String grantedBy;
  final int grantVersion;
  final int keyVersion;
  final DateTime createdAt;

  /// Bounded validity window for the offline-revocation trade-off (§13.3).
  final DateTime? expiresAt;
  final DateTime? revokedAt;

  /// Base64 owner signature over the grant fields.
  final String? signature;

  bool isActiveAt(DateTime now) =>
      revokedAt == null && (expiresAt == null || now.isBefore(expiresAt!));

  Json toJson() => {
        'contentId': contentId,
        'granteeNodeId': granteeNodeId,
        'permission': permission.wire,
        'grantedBy': grantedBy,
        'grantVersion': grantVersion,
        'keyVersion': keyVersion,
        'createdAt': dateToJson(createdAt),
        'expiresAt': optionalDateToJson(expiresAt),
        'revokedAt': optionalDateToJson(revokedAt),
        'signature': signature,
      };

  factory AccessGrant.fromJson(Json json) => AccessGrant(
        contentId: json['contentId']! as String,
        granteeNodeId: json['granteeNodeId']! as String,
        permission:
            enumFromWire(PermissionType.values, json['permission']! as String),
        grantedBy: json['grantedBy']! as String,
        grantVersion: json['grantVersion']! as int,
        keyVersion: json['keyVersion']! as int,
        createdAt: dateFromJson(json['createdAt']),
        expiresAt: optionalDateFromJson(json['expiresAt']),
        revokedAt: optionalDateFromJson(json['revokedAt']),
        signature: json['signature'] as String?,
      );
}

/// Public half of a device key (PRD §6.8).
class DeviceKey {
  const DeviceKey({
    required this.nodeId,
    required this.publicKey,
    required this.keyAlgorithm,
    required this.fingerprint,
    required this.createdAt,
    this.rotatedAt,
    this.revokedAt,
  });

  final String nodeId;
  final String publicKey;
  final String keyAlgorithm;
  final String fingerprint;
  final DateTime createdAt;
  final DateTime? rotatedAt;
  final DateTime? revokedAt;

  Json toJson() => {
        'nodeId': nodeId,
        'publicKey': publicKey,
        'keyAlgorithm': keyAlgorithm,
        'fingerprint': fingerprint,
        'createdAt': dateToJson(createdAt),
        'rotatedAt': optionalDateToJson(rotatedAt),
        'revokedAt': optionalDateToJson(revokedAt),
      };

  factory DeviceKey.fromJson(Json json) => DeviceKey(
        nodeId: json['nodeId']! as String,
        publicKey: json['publicKey']! as String,
        keyAlgorithm: json['keyAlgorithm']! as String,
        fingerprint: json['fingerprint']! as String,
        createdAt: dateFromJson(json['createdAt']),
        rotatedAt: optionalDateFromJson(json['rotatedAt']),
        revokedAt: optionalDateFromJson(json['revokedAt']),
      );
}

/// An image key wrapped for exactly one recipient device (PRD §6.9).
/// `wrappedKey` is ciphertext; plaintext keys are never modelled here.
class WrappedImageKey {
  const WrappedImageKey({
    required this.contentId,
    required this.recipientNodeId,
    required this.wrappedKey,
    required this.keyVersion,
    required this.createdAt,
    this.expiresAt,
    this.revokedAt,
  });

  final String contentId;
  final String recipientNodeId;
  final String wrappedKey;
  final int keyVersion;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? revokedAt;

  Json toJson() => {
        'contentId': contentId,
        'recipientNodeId': recipientNodeId,
        'wrappedKey': wrappedKey,
        'keyVersion': keyVersion,
        'createdAt': dateToJson(createdAt),
        'expiresAt': optionalDateToJson(expiresAt),
        'revokedAt': optionalDateToJson(revokedAt),
      };

  factory WrappedImageKey.fromJson(Json json) => WrappedImageKey(
        contentId: json['contentId']! as String,
        recipientNodeId: json['recipientNodeId']! as String,
        wrappedKey: json['wrappedKey']! as String,
        keyVersion: json['keyVersion']! as int,
        createdAt: dateFromJson(json['createdAt']),
        expiresAt: optionalDateFromJson(json['expiresAt']),
        revokedAt: optionalDateFromJson(json['revokedAt']),
      );
}
