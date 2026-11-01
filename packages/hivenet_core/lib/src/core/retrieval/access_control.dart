import '../../shared/models/enums.dart';

class AccessDecision {
  const AccessDecision.granted()
      : granted = true,
        reason = null;
  const AccessDecision.denied(this.reason) : granted = false;

  final bool granted;
  final String? reason;
}

/// Per-image, per-action authorization (PRD FR-09A). Wi-Fi membership, mDNS
/// discovery, pairing and AI placement never imply view permission; each
/// permission is checked independently against an owner-signed, device-bound
/// grant and the latest revocation state held locally.
abstract interface class AccessControl {
  /// [requesterNodeId] must come from the authenticated connection.
  Future<AccessDecision> check({
    required String requesterNodeId,
    required String contentId,
    required PermissionType permission,
  });
}

/// Safe default: denies everything.
class DenyAllAccessControl implements AccessControl {
  const DenyAllAccessControl();

  @override
  Future<AccessDecision> check({
    required String requesterNodeId,
    required String contentId,
    required PermissionType permission,
  }) async =>
      const AccessDecision.denied('Access control not implemented');
}
