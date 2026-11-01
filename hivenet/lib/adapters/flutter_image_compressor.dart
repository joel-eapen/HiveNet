import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:hivenet_core/hivenet_core.dart';

/// Compresses on the sender before any bytes leave the device (PRD FR-03),
/// using `flutter_image_compress`.
///
/// Behaviour confirmed on two Android phones (Android 13 and 17):
/// - the plugin's min width/height are LOWER bounds, so the longest side is
///   capped here by computing the exact target size from the input;
/// - orientation tags are applied and EXIF (including GPS) is removed;
/// - JPEG, PNG and HEIC inputs all decode.
///
/// Output bytes differ between phone models, so the content ID must be taken
/// from the bytes this produces, once, on the uploading device.
class FlutterImageCompressor implements ImageCompressor {
  const FlutterImageCompressor({this.config = const CompressionConfig()});

  final CompressionConfig config;

  @override
  Future<CompressedImage> compress(CompressionRequest request) async {
    final input = File(request.sourcePath);
    if (!await input.exists()) {
      throw const HiveError(
        code: HiveErrorCode.compressionFailed,
        message: 'HiveNet could not read this image. It was not uploaded.',
      );
    }

    final inputBytes = await input.readAsBytes();
    int inW;
    int inH;
    try {
      final codec = await ui.instantiateImageCodec(inputBytes);
      final frame = await codec.getNextFrame();
      inW = frame.image.width;
      inH = frame.image.height;
      frame.image.dispose();
      codec.dispose();
    } catch (_) {
      throw const HiveError(
        code: HiveErrorCode.unsupportedImage,
        message: 'This image format is not supported on this device.',
      );
    }

    final maxSide = config.maxDimensionFor(request.importance);
    final scale = (maxSide / (inW > inH ? inW : inH)).clamp(0.0, 1.0); // never upscale
    final targetW = (inW * scale).round();
    final targetH = (inH * scale).round();

    final out = await FlutterImageCompress.compressWithFile(
      request.sourcePath,
      minWidth: targetW,
      minHeight: targetH,
      quality: config.qualityFor(request.importance),
      format: CompressFormat.jpeg,
      keepExif: !config.stripGpsMetadata,
      autoCorrectionAngle: true,
    );
    if (out == null || out.isEmpty) {
      throw const HiveError(
        code: HiveErrorCode.compressionFailed,
        message: 'HiveNet could not prepare this image. The original was not uploaded.',
      );
    }

    // Report the real output size, after any rotation.
    final codec = await ui.instantiateImageCodec(out);
    final frame = await codec.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();
    codec.dispose();

    await File(request.outputPath).parent.create(recursive: true);
    await File(request.outputPath).writeAsBytes(out, flush: true);
    return CompressedImage(
      path: request.outputPath,
      mimeType: 'image/jpeg',
      sizeBytes: out.length,
      width: w,
      height: h,
    );
  }
}
