import 'dart:io';
import 'package:cam_scan/core/ocr/layout_reconstructor.dart';
import 'package:cam_scan/core/ocr/ocr_engine.dart';
import 'package:image/image.dart' as img;

/// OCR engine for tests: returns [lines] for portrait images and gibberish for
/// landscape ones (simulating text that is sideways in the picture).
class FakeOcrEngine implements OcrEngine {
  final List<OcrLineBox> lines;
  final List<String> calls = [];

  FakeOcrEngine(this.lines);

  @override
  String get name => 'Fake OCR';

  @override
  bool get isAvailable => true;

  @override
  Future<List<OcrLineBox>> recognizeFile(String imagePath) async {
    calls.add(imagePath);
    final image = img.decodeJpg(File(imagePath).readAsBytesSync())!;
    if (image.width > image.height) {
      return const [OcrLineBox(text: 'l1 | ;: ii', left: 10, top: 10, right: 90, bottom: 30, confidence: 0.2)];
    }
    // Scale the fixture boxes (defined for a 1000 px wide page) to this image.
    final s = image.width / 1000;
    return [
      for (final l in lines)
        OcrLineBox(text: l.text, left: l.left * s, top: l.top * s, right: l.right * s, bottom: l.bottom * s, confidence: l.confidence),
    ];
  }

  @override
  Future<void> dispose() async {}
}

/// Writes a JPEG of the given size to [path] and returns the path.
String writeJpeg(String path, {int width = 600, int height = 800}) {
  final image = img.Image(width: width, height: height)..clear(img.ColorRgb8(245, 245, 245));
  File(path).writeAsBytesSync(img.encodeJpg(image));
  return path;
}
