import 'dart:io';

import '../../shared/models/enums.dart';
import '../../shared/models/hive_error.dart';
import 'file_store.dart';
import 'integrity_checker.dart';
import 'storage_layout.dart';

/// File-backed [FileStore] rooted at a [StorageLayout].
///
/// A replica exists only at `objects/<xx>/<contentId>.enc`, and a file reaches
/// that path only through [commit], after its hash has been verified. Anything
/// still in the temporary directory is, by construction, not a replica.
class LocalFileStore implements FileStore {
  LocalFileStore(this.layout, this.integrity);

  final StorageLayout layout;
  final IntegrityChecker integrity;

  @override
  Future<bool> exists(String contentId) =>
      File(layout.objectPath(contentId)).exists();

  /// Verifies, flushes, then renames into place.
  ///
  /// The rename is atomic because the temporary and object directories are on
  /// the same volume. If it fails the previous object (if any) is untouched.
  @override
  Future<void> commit({
    required String temporaryPath,
    required String contentId,
    required String expectedCiphertextHash,
  }) async {
    final destination = layout.objectPath(contentId); // validates the id
    _requireInsideTemporaryDir(temporaryPath);

    final temp = File(temporaryPath);
    final actual = await integrity.sha256OfFile(temporaryPath);
    if (actual != expectedCiphertextHash.toLowerCase()) {
      // Corrupt data must never linger or be resumed.
      await temp.delete();
      throw HiveError(
        code: HiveErrorCode.integrityMismatch,
        message: 'The received data failed verification and was discarded.',
        technicalDetails: 'expected $expectedCiphertextHash, got $actual',
      );
    }

    // Force the bytes to disk before the rename makes them visible. Dart cannot
    // fsync the directory itself, so a crash right after the rename may still
    // lose the directory entry; startup integrity checks cover that case.
    final raf = await temp.open(mode: FileMode.append);
    try {
      await raf.flush();
    } finally {
      await raf.close();
    }

    await File(destination).parent.create(recursive: true);
    await temp.rename(destination);
  }

  @override
  Stream<List<int>> openRead(String contentId, {int start = 0}) =>
      File(layout.objectPath(contentId)).openRead(start);

  @override
  Future<void> delete(String contentId) async {
    final file = File(layout.objectPath(contentId));
    if (await file.exists()) await file.delete();
  }

  /// Total size of committed objects. Temporary files are not counted.
  @override
  Future<int> usedBytes() async {
    final dir = Directory(layout.objectsDir);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.enc')) {
        total += await entity.length();
      }
    }
    return total;
  }

  void _requireInsideTemporaryDir(String path) {
    final normalized = Uri.file(path).normalizePath().toFilePath();
    final prefix = '${layout.incompleteTransfersDir}${Platform.pathSeparator}';
    if (!normalized.startsWith(prefix)) {
      throw ArgumentError.value(
        path,
        'temporaryPath',
        'must be inside the incomplete-transfers directory',
      );
    }
  }
}
