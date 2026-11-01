import '../../shared/models/enums.dart';

class CompressionRequest {
  const CompressionRequest({
    required this.sourcePath,
    required this.outputPath,
    required this.importance,
  });

  final String sourcePath;
  final String outputPath;
  final Importance importance;
}

/// Result of compression. File-based so large images are not held in memory.
class CompressedImage {
  const CompressedImage({
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
    required this.width,
    required this.height,
  });

  final String path;
  final String mimeType;
  final int sizeBytes;
  final int width;
  final int height;
}

/// Compresses an image on the sender before any bytes leave the device
/// (PRD FR-03). Implemented in the app with `flutter_image_compress`.
///
/// Must normalize orientation, resize without upscaling, strip GPS metadata,
/// and throw a `HiveError` (compressionFailed / unsupportedImage) on failure so
/// the original is never uploaded.
abstract interface class ImageCompressor {
  Future<CompressedImage> compress(CompressionRequest request);
}

class UnimplementedImageCompressor implements ImageCompressor {
  const UnimplementedImageCompressor();

  @override
  Future<CompressedImage> compress(CompressionRequest request) =>
      throw UnimplementedError('ImageCompressor: Milestone 3');
}
