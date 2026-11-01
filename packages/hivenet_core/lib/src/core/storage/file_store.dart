/// Filesystem object store (PRD FR-06, FR-10). Replicas are committed with an
/// atomic temp-to-final move after the hash is verified, so incomplete files
/// never appear as valid replicas.
abstract interface class FileStore {
  Future<bool> exists(String contentId);

  /// Atomically moves a verified temporary file into the content-addressed
  /// path. Fails if the file does not match [expectedCiphertextHash].
  Future<void> commit({
    required String temporaryPath,
    required String contentId,
    required String expectedCiphertextHash,
  });

  Stream<List<int>> openRead(String contentId, {int start = 0});
  Future<void> delete(String contentId);
  Future<int> usedBytes();
}

class UnimplementedFileStore implements FileStore {
  const UnimplementedFileStore();

  @override
  Future<bool> exists(String contentId) =>
      throw UnimplementedError('FileStore: Milestone 3');

  @override
  Future<void> commit({
    required String temporaryPath,
    required String contentId,
    required String expectedCiphertextHash,
  }) =>
      throw UnimplementedError('FileStore: Milestone 3');

  @override
  Stream<List<int>> openRead(String contentId, {int start = 0}) =>
      throw UnimplementedError('FileStore: Milestone 3');

  @override
  Future<void> delete(String contentId) =>
      throw UnimplementedError('FileStore: Milestone 3');

  @override
  Future<int> usedBytes() =>
      throw UnimplementedError('FileStore: Milestone 3');
}
