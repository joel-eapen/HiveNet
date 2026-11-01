import 'dart:typed_data';

class Chunk {
  const Chunk({required this.index, required this.bytes, this.isLast = false});
  final int index;
  final Uint8List bytes;

  /// True for the final chunk of an object. Only the last chunk may be
  /// shorter than the chunk size.
  final bool isLast;
}

/// Splits files into chunks and assembles received chunks into a temporary
/// file, tracking progress so interrupted transfers can resume (PRD §9).
abstract interface class ChunkManager {
  /// Streams chunks of [path] starting at [startIndex]. Reads incrementally
  /// to avoid loading whole files into memory.
  Stream<Chunk> readChunks(String path, {int chunkSize, int startIndex});

  /// Writes [chunk] into the transfer's partial file. Chunks must arrive in
  /// order; re-sending an earlier index is allowed (retries are idempotent) and
  /// a gap is rejected.
  Future<void> writeChunk(String transferId, Chunk chunk);

  /// Path of the transfer's partial file, to pass to `FileStore.commit` once
  /// every chunk has arrived.
  String pathFor(String transferId);

  /// Deletes the partial file (cancelled or failed transfer).
  Future<void> discard(String transferId);

  /// Next chunk index still missing, used for `TRANSFER_RESUME`.
  Future<int> nextExpectedIndex(String transferId);
}

class UnimplementedChunkManager implements ChunkManager {
  const UnimplementedChunkManager();

  @override
  Stream<Chunk> readChunks(String path,
          {int chunkSize = 1024 * 1024, int startIndex = 0}) =>
      throw UnimplementedError('ChunkManager: Milestone 3');

  @override
  Future<void> writeChunk(String transferId, Chunk chunk) =>
      throw UnimplementedError('ChunkManager: Milestone 3');

  @override
  Future<int> nextExpectedIndex(String transferId) =>
      throw UnimplementedError('ChunkManager: Milestone 3');

  @override
  String pathFor(String transferId) =>
      throw UnimplementedError('ChunkManager: Milestone 3');

  @override
  Future<void> discard(String transferId) =>
      throw UnimplementedError('ChunkManager: Milestone 3');
}
