import 'dart:typed_data';

class Chunk {
  const Chunk({required this.index, required this.bytes});
  final int index;
  final Uint8List bytes;
}

/// Splits files into chunks and assembles received chunks into a temporary
/// file, tracking progress so interrupted transfers can resume (PRD §9).
abstract interface class ChunkManager {
  /// Streams chunks of [path] starting at [startIndex]. Reads incrementally
  /// to avoid loading whole files into memory.
  Stream<Chunk> readChunks(String path, {int chunkSize, int startIndex});

  Future<void> writeChunk(String transferId, Chunk chunk);

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
}
