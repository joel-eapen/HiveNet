import 'package:hivenet_core/hivenet_core.dart';

/// Will wrap `flutter_image_compress` (PRD FR-03, Milestone 3).
///
/// Not implemented yet. Milestone 0 must first confirm on physical devices
/// that the package yields identical output formats on Android and iOS and
/// decide how HEIC is handled.
class FlutterImageCompressor implements ImageCompressor {
  const FlutterImageCompressor();

  @override
  Future<CompressedImage> compress(CompressionRequest request) =>
      throw UnimplementedError('FlutterImageCompressor: Milestone 3');
}
