/// Stages shown to the user while retrieving an image (PRD FR-08, frontend
/// PRD 7.4).
enum RetrievalStage {
  checkingAccess,
  locatingReplica,
  downloading,
  verifying,
  decrypting,
  ready,
  denied,
  unavailable,
  failed,
}

class RetrievalSession {
  const RetrievalSession({
    required this.requestId,
    required this.contentId,
    required this.stage,
    this.progress = 0,
    this.localPath,
    this.hostNodeId,
  });

  final String requestId;
  final String contentId;
  final RetrievalStage stage;
  final double progress;

  /// Set only when [stage] is `ready` (decrypted and verified).
  final String? localPath;
  final String? hostNodeId;
}

/// Orchestrates: access check -> key delivery -> locate -> select host ->
/// download -> verify -> decrypt, retrying another replica on host failure.
abstract interface class ImageRequestManager {
  Stream<RetrievalSession> request(String contentId);
  Future<void> cancel(String requestId);
}

class UnimplementedImageRequestManager implements ImageRequestManager {
  const UnimplementedImageRequestManager();

  @override
  Stream<RetrievalSession> request(String contentId) =>
      throw UnimplementedError('ImageRequestManager: Milestone 5');

  @override
  Future<void> cancel(String requestId) =>
      throw UnimplementedError('ImageRequestManager: Milestone 5');
}
