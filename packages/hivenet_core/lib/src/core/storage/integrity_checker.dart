/// SHA-256 verification for `ciphertextHash` and `contentId` (PRD FR-03,
/// FR-08). Returns lowercase hex digests.
abstract interface class IntegrityChecker {
  /// Hashes a file by streaming it, not by reading it fully into memory.
  Future<String> sha256OfFile(String path);

  Future<String> sha256OfBytes(List<int> bytes);

  Future<bool> verifyFile(String path, String expectedSha256);
}

class UnimplementedIntegrityChecker implements IntegrityChecker {
  const UnimplementedIntegrityChecker();

  @override
  Future<String> sha256OfFile(String path) =>
      throw UnimplementedError('IntegrityChecker: Milestone 3');

  @override
  Future<String> sha256OfBytes(List<int> bytes) =>
      throw UnimplementedError('IntegrityChecker: Milestone 3');

  @override
  Future<bool> verifyFile(String path, String expectedSha256) =>
      throw UnimplementedError('IntegrityChecker: Milestone 3');
}
