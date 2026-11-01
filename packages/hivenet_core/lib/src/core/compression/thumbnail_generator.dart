import 'image_compressor.dart';

/// Produces a 320-480 px thumbnail (PRD FR-03). Thumbnails are image content:
/// they must be encrypted or follow the image's view policy (FR-09A).
abstract interface class ThumbnailGenerator {
  Future<CompressedImage> generate({
    required String sourcePath,
    required String outputPath,
  });
}

class UnimplementedThumbnailGenerator implements ThumbnailGenerator {
  const UnimplementedThumbnailGenerator();

  @override
  Future<CompressedImage> generate({
    required String sourcePath,
    required String outputPath,
  }) =>
      throw UnimplementedError('ThumbnailGenerator: Milestone 3');
}
