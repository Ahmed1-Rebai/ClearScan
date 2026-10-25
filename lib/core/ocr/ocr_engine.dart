import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'layout_reconstructor.dart';

/// A text recognizer that turns an image file into line boxes (pixel coordinates).
abstract class OcrEngine {
  String get name;
  bool get isAvailable;
  Future<List<OcrLineBox>> recognizeFile(String imagePath);
  Future<void> dispose();

  factory OcrEngine.platformDefault() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) return MlKitOcrEngine();
    return const UnavailableOcrEngine();
  }
}

/// Google ML Kit Text Recognition v2, Latin script (English, French, Spanish, German, ...).
/// On Android the model is bundled in the app, so recognition is fully offline.
class MlKitOcrEngine implements OcrEngine {
  TextRecognizer? _recognizer;

  @override
  String get name => 'ML Kit Text Recognition v2 (on-device)';

  @override
  bool get isAvailable => true;

  @override
  Future<List<OcrLineBox>> recognizeFile(String imagePath) async {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    final result = await _recognizer!.processImage(InputImage.fromFilePath(imagePath));
    final lines = <OcrLineBox>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final box = line.boundingBox;
        double? confidence = line.confidence;
        if (confidence == null) {
          final known = line.elements.map((e) => e.confidence).whereType<double>().toList();
          if (known.isNotEmpty) confidence = known.reduce((a, b) => a + b) / known.length;
        }
        lines.add(OcrLineBox(
          text: line.text,
          left: box.left,
          top: box.top,
          right: box.right,
          bottom: box.bottom,
          confidence: confidence,
          angle: line.angle,
        ));
      }
    }
    return lines;
  }

  @override
  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}

class UnavailableOcrEngine implements OcrEngine {
  const UnavailableOcrEngine();

  @override
  String get name => 'Not available on this platform';

  @override
  bool get isAvailable => false;

  @override
  Future<List<OcrLineBox>> recognizeFile(String imagePath) =>
      throw UnsupportedError('On-device OCR is only available on Android and iOS.');

  @override
  Future<void> dispose() async {}
}
