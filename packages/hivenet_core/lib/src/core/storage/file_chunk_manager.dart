import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'chunk_manager.dart';
import 'storage_layout.dart';

/// File-backed [ChunkManager].
///
/// Partial data lives at `StorageLayout.incompleteTransferPath`, never in the
/// object store, so an unfinished transfer cannot be mistaken for a replica.
///
/// Progress is derived from the partial file's length: with a fixed chunk size,
/// `length ~/ chunkSize` is the next chunk to receive. That survives app
/// restarts without a separate progress file.
class FileChunkManager implements ChunkManager {
  FileChunkManager(this.layout, {this.chunkSize = 1024 * 1024}) {
    if (chunkSize <= 0) throw ArgumentError.value(chunkSize, 'chunkSize');
  }

  final StorageLayout layout;

  /// Size of every chunk except possibly the last. Must match on both sides.
  final int chunkSize;

  @override
  String pathFor(String transferId) => layout.incompleteTransferPath(transferId);

  @override
  Stream<Chunk> readChunks(
    String path, {
    int? chunkSize,
    int startIndex = 0,
  }) async* {
    final size = chunkSize ?? this.chunkSize;
    if (size <= 0) throw ArgumentError.value(size, 'chunkSize');
    if (startIndex < 0) throw ArgumentError.value(startIndex, 'startIndex');

    final raf = await File(path).open();
    try {
      final total = await raf.length();
      var offset = startIndex * size;
      var index = startIndex;
      await raf.setPosition(min(offset, total));
      while (offset < total) {
        final want = min(size, total - offset);
        final bytes = await raf.read(want);
        if (bytes.length != want) {
          throw FileSystemException('File changed while reading', path);
        }
        offset += bytes.length;
        yield Chunk(index: index, bytes: bytes, isLast: offset >= total);
        index++;
      }
    } finally {
      await raf.close();
    }
  }

  @override
  Future<void> writeChunk(String transferId, Chunk chunk) async {
    final bytes = chunk.bytes;
    if (chunk.index < 0) throw ArgumentError.value(chunk.index, 'index');
    if (bytes.length > chunkSize) {
      throw ArgumentError('Chunk of ${bytes.length} bytes exceeds $chunkSize');
    }
    if (!chunk.isLast && bytes.length != chunkSize) {
      throw ArgumentError(
        'Only the last chunk may be shorter than $chunkSize bytes',
      );
    }

    final expected = await nextExpectedIndex(transferId);
    if (chunk.index > expected) {
      throw StateError(
        'Chunk ${chunk.index} arrived but $expected is still missing',
      );
    }

    final file = File(pathFor(transferId));
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.append);
    try {
      // Cut back to the start of this chunk first. That makes a retry of an
      // already-written chunk idempotent and drops a half-written tail left by
      // a crash. Appending then lands exactly at index * chunkSize.
      await raf.truncate(chunk.index * chunkSize);
      await raf.writeFrom(bytes);
    } finally {
      await raf.close();
    }
  }

  @override
  Future<int> nextExpectedIndex(String transferId) async {
    final file = File(pathFor(transferId));
    if (!await file.exists()) return 0;
    return (await file.length()) ~/ chunkSize;
  }

  @override
  Future<void> discard(String transferId) async {
    final file = File(pathFor(transferId));
    if (await file.exists()) await file.delete();
  }
}
