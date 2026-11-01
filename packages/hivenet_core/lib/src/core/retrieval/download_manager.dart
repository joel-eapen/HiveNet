import '../../shared/models/jobs.dart';

/// Chunked, resumable download from one host (PRD FR-08). Verifies
/// `ciphertextHash`, then decryption and `contentId`, before anything is
/// displayed. Tampered data is discarded.
abstract interface class DownloadManager {
  Stream<TransferRecord> download({
    required String contentId,
    required String hostNodeId,
    required String destinationPath,
  });

  Future<void> cancel(String transferId);
}

class UnimplementedDownloadManager implements DownloadManager {
  const UnimplementedDownloadManager();

  @override
  Stream<TransferRecord> download({
    required String contentId,
    required String hostNodeId,
    required String destinationPath,
  }) =>
      throw UnimplementedError('DownloadManager: Milestone 5');

  @override
  Future<void> cancel(String transferId) =>
      throw UnimplementedError('DownloadManager: Milestone 5');
}
