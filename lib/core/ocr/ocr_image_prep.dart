import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../cv/image_buffers.dart';
import '../cv/orientation_detector.dart';

class OcrInput {
  final String path;
  final int width;
  final int height;

  const OcrInput(this.path, this.width, this.height);
}

/// Builds recognizer-friendly images from processed pages (runs in isolates).
class OcrImagePrep {
  /// Text recognizers need roughly 20+ px per character; small pages are upscaled.
  static const int minLongSide = 2000;
  static const int maxLongSide = 3600;

  /// Pixel size of a JPEG without decoding it, or null if it is not a readable JPEG.
  static ({int width, int height})? jpegSize(String path) {
    final info = img.JpegDecoder().startDecode(File(path).readAsBytesSync());
    return info == null ? null : (width: info.width, height: info.height);
  }

  /// Grayscale, shadow-free, contrast-stretched copy of [sourcePath], resized into
  /// [minLongSide]..[maxLongSide] (or to at most [maxDimension] when given).
  static OcrInput prepare(String sourcePath, String outputPath, {int? maxDimension}) {
    final gray = _normalizedGray(_decode(sourcePath), maxDimension: maxDimension);
    _writeGray(gray.pixels, gray.width, gray.height, outputPath);
    return OcrInput(outputPath, gray.width, gray.height);
  }

  /// Small copies of [sourcePath] at 0/90/180/270° for orientation trials (decoded once).
  static Map<int, String> prepareRotationTrials(String sourcePath, String outputPrefix, {int maxDimension = 1600}) {
    final gray = _normalizedGray(_decode(sourcePath), maxDimension: maxDimension);
    final base = ImageBuffers.fromGray(gray.width, gray.height, gray.pixels);
    final result = <int, String>{};
    for (final rotation in const [0, 90, 180, 270]) {
      final path = '${outputPrefix}_r$rotation.jpg';
      File(path).writeAsBytesSync(img.encodeJpg(ImageBuffers.rotate(base, rotation), quality: 90));
      result[rotation] = path;
    }
    return result;
  }

  static OrientationEstimate estimateOrientation(String sourcePath) => TextOrientationDetector.detect(_decode(sourcePath));

  static img.Image _decode(String path) {
    final decoded = img.decodeImage(File(path).readAsBytesSync());
    if (decoded == null) throw StateError('Cannot decode $path');
    return decoded;
  }

  static ({Uint8List pixels, int width, int height}) _normalizedGray(img.Image image, {int? maxDimension}) {
    final w = image.width;
    final h = image.height;
    var gray = ImageBuffers.normalizeIllumination(ImageBuffers.luminance(image), w, h);

    final low = ImageBuffers.percentile(gray, 0.005);
    final range = max(1, 250 - low);
    for (int i = 0; i < gray.length; i++) {
      gray[i] = ((gray[i] - low) * 255 ~/ range).clamp(0, 255);
    }

    final longSide = max(w, h);
    final target = maxDimension != null ? min(longSide, maxDimension) : longSide.clamp(minLongSide, maxLongSide);
    if (target == longSide) return (pixels: gray, width: w, height: h);
    final s = target / longSide;
    final outW = max(1, (w * s).round());
    final outH = max(1, (h * s).round());
    return (pixels: ImageBuffers.resizeGray(gray, w, h, outW, outH), width: outW, height: outH);
  }

  static void _writeGray(Uint8List gray, int width, int height, String path) {
    File(path).writeAsBytesSync(img.encodeJpg(ImageBuffers.fromGray(width, height, gray), quality: 92));
  }
}
