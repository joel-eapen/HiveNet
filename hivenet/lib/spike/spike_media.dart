// THROWAWAY Milestone 0 spike code.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// What the picker actually delivered, judged by file signature, not by name.
String detectFormat(Uint8List head) {
  bool starts(List<int> sig, [int at = 0]) {
    if (head.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (head[at + i] != sig[i]) return false;
    }
    return true;
  }

  if (starts([0xFF, 0xD8, 0xFF])) return 'JPEG';
  if (starts([0x89, 0x50, 0x4E, 0x47])) return 'PNG';
  if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8)) {
    return 'WebP';
  }
  if (starts([0x66, 0x74, 0x79, 0x70], 4)) {
    final brand = String.fromCharCodes(head.sublist(8, 12.clamp(0, head.length)));
    return 'ISO-BMFF/HEIF (brand "$brand")';
  }
  return 'unknown';
}

class CompressOutcome {
  CompressOutcome({
    required this.bytes,
    required this.width,
    required this.height,
    required this.sha256,
    required this.containsExif,
    required this.inputFormat,
    required this.inputBytes,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final String sha256;
  final bool containsExif;
  final String inputFormat;
  final int inputBytes;
}

/// Compresses with the PRD FR-03 "normal" policy (quality 80, 2048 px) and
/// reports what actually came out, because the point is to find platform
/// differences, not to assume there are none.
Future<CompressOutcome> compressForSpike(String path) async {
  final input = File(path);
  final head = await input.openRead(0, 16).fold<List<int>>([], (a, b) => a..addAll(b));
  final inputFormat = detectFormat(Uint8List.fromList(head));

  // FINDING: flutter_image_compress's minWidth/minHeight are lower bounds on
  // the output, not a maximum, so passing 2048/2048 left a 3000x2000 image
  // unchanged. To cap the longest side we must read the input size ourselves
  // and pass the exact target as the "min" values.
  final inputCodec = await ui.instantiateImageCodec(await input.readAsBytes());
  final inputFrame = await inputCodec.getNextFrame();
  final inW = inputFrame.image.width;
  final inH = inputFrame.image.height;
  inputFrame.image.dispose();
  inputCodec.dispose();
  const maxSide = 2048;
  final scale = (maxSide / (inW > inH ? inW : inH)).clamp(0.0, 1.0); // never upscale
  final targetW = (inW * scale).round();
  final targetH = (inH * scale).round();

  final out = await FlutterImageCompress.compressWithFile(
    path,
    minWidth: targetW,
    minHeight: targetH,
    quality: 80,
    format: CompressFormat.jpeg,
    keepExif: false,
    autoCorrectionAngle: true,
  );
  if (out == null || out.isEmpty) {
    throw StateError('compressor returned no data for a $inputFormat input');
  }

  final codec = await ui.instantiateImageCodec(out);
  final frame = await codec.getNextFrame();
  final w = frame.image.width;
  final h = frame.image.height;
  frame.image.dispose();
  codec.dispose();

  // A JPEG APP1 "Exif\0\0" marker in the first 64 KiB means metadata survived.
  final scan = out.length < 65536 ? out : out.sublist(0, 65536);
  var exif = false;
  for (var i = 0; i + 5 < scan.length; i++) {
    if (scan[i] == 0x45 && scan[i + 1] == 0x78 && scan[i + 2] == 0x69 &&
        scan[i + 3] == 0x66 && scan[i + 4] == 0 && scan[i + 5] == 0) {
      exif = true;
      break;
    }
  }

  return CompressOutcome(
    bytes: out,
    width: w,
    height: h,
    sha256: sha256.convert(out).toString(),
    containsExif: exif,
    inputFormat: inputFormat,
    inputBytes: await input.length(),
  );
}

/// Draws a test PNG so compression can be checked without a photo library.
/// A coloured corner marker makes orientation mistakes visible.
Future<File> generateTestPng(Directory dir, {int width = 3000, int height = 2000}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final shader = ui.Gradient.linear(
    const ui.Offset(0, 0),
    ui.Offset(width.toDouble(), height.toDouble()),
    const [ui.Color(0xFF0F766E), ui.Color(0xFFF59E0B)],
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..shader = shader,
  );
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 400, 400),
      ui.Paint()..color = const ui.Color(0xFFDC2626));
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('${dir.path}/spike_test_${width}x$height.png');
  await file.writeAsBytes(data!.buffer.asUint8List());
  return file;
}

/// Decodes bytes and returns "WxH", proving the platform can display them.
Future<String> decodeDimensions(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final text = '${frame.image.width}x${frame.image.height}';
  frame.image.dispose();
  codec.dispose();
  return text;
}
