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

    // A photo handed over by the system picker can arrive cut off (seen on a
    // vivo phone with screenshots). Decoders reject it with an unhelpful
    // message, so say what is actually wrong.
    if (looksTruncated(inputBytes)) {
      throw HiveError(
        code: HiveErrorCode.unsupportedImage,
        message: 'This photo is incomplete: the phone only provided part of the '
            'file. Pick it again, or pick a different photo.',
        technicalDetails: 'missing end-of-image marker (${inputBytes.length} bytes)',
      );
    }
    int inW;
    int inH;
    try {
      final codec = await ui.instantiateImageCodec(inputBytes);
      final frame = await codec.getNextFrame();
      inW = frame.image.width;
      inH = frame.image.height;
      frame.image.dispose();
      codec.dispose();
    } catch (e) {
      throw HiveError(
        code: HiveErrorCode.unsupportedImage,
        message: 'This image format is not supported on this device.',
        // Keep the engine's own message: it says why the decode failed.
        technicalDetails: '${e.runtimeType}: $e (input ${inputBytes.length} bytes)',
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

/// True when [bytes] is a JPEG or PNG that ends before its end marker, which
/// means the copy of the file is incomplete. Other formats are not judged.
bool looksTruncated(List<int> bytes) {
  bool endsWith(List<int> tail) {
    if (bytes.length < tail.length) return false;
    // Some writers pad with zero bytes after the end marker; look a little back.
    final window = bytes.length < 64 ? bytes.length : 64;
    for (var start = bytes.length - tail.length; start >= bytes.length - window; start--) {
      var match = true;
      for (var i = 0; i < tail.length; i++) {
        if (bytes[start + i] != tail[i]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  final isJpeg = bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  if (isJpeg) return !endsWith(const [0xFF, 0xD9]);

  final isPng = bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
  // PNG ends with an IEND chunk: "IEND" followed by its 4-byte CRC.
  if (isPng) return !endsWith(const [0x49, 0x45, 0x4E, 0x44]);

  return false;
}
