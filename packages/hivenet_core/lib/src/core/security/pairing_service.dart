import '../../shared/models/security_models.dart';

/// Contents of the pairing QR code. Contains the public identity and a
/// one-time secret for this pairing only, never long-lived keys.
class PairingInvite {
  const PairingInvite({
    required this.nodeId,
    required this.fingerprint,
    required this.host,
    required this.port,
    required this.oneTimeSecret,
  });

  final String nodeId;
  final String fingerprint;
  final String host;
  final int port;
  final String oneTimeSecret;
}

enum PairingStatus {
  waitingForScan,
  connecting,
  confirmationRequired,
  identityMismatch,
  paired,
  failed,
}

class PairingSession {
  const PairingSession({
    required this.sessionId,
    required this.status,
    this.peerDisplayName,
    this.peerFingerprint,
  });

  final String sessionId;
  final PairingStatus status;

  /// Both devices show the fingerprint and require explicit confirmation.
  final String? peerDisplayName;
  final String? peerFingerprint;
}

/// QR pairing with a manual IP/port fallback (PRD FR-01). Manual entry still
/// performs identity verification; it is not a way around pairing.
abstract interface class PairingService {
  Future<PairingInvite> createInvite();
  Stream<PairingSession> accept(PairingInvite invite);
  Future<TrustedDevice> confirm(String sessionId);
  Future<void> revoke(String nodeId);
}

class UnimplementedPairingService implements PairingService {
  const UnimplementedPairingService();

  @override
  Future<PairingInvite> createInvite() =>
      throw UnimplementedError('PairingService: Milestone 2');

  @override
  Stream<PairingSession> accept(PairingInvite invite) =>
      throw UnimplementedError('PairingService: Milestone 2');

  @override
  Future<TrustedDevice> confirm(String sessionId) =>
      throw UnimplementedError('PairingService: Milestone 2');

  @override
  Future<void> revoke(String nodeId) =>
      throw UnimplementedError('PairingService: Milestone 2');
}
