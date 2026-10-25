import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../analysis/document_analyzer.dart';
import '../cv/cv_isolate_service.dart';
import '../models/document.dart';
import '../storage/document_repository.dart';
import 'layout_reconstructor.dart';
import 'ocr_engine.dart';
import 'ocr_image_prep.dart';

/// How readable an OCR result is: rotated or garbled text yields few plausible words.
class OcrQuality {
  final int tokens;
  final int plausible;
  final double? meanConfidence;
  final double score;

  const OcrQuality(this.tokens, this.plausible, this.meanConfidence, this.score);

  double get plausibleRatio => tokens == 0 ? 0 : plausible / tokens;

  bool get looksGood => plausible >= 8 && plausibleRatio >= 0.6 && (meanConfidence ?? 1) >= 0.6;

  static final RegExp _word = RegExp(r"^[(\[«]?[A-Za-zÀ-ÖØ-öø-ÿ'’\-]{2,}[.,;:!?)\]»]*$");
  static final RegExp _vowel = RegExp(r'[aeiouyàâäéèêëîïôöùûüAEIOUYÀÂÄÉÈÊËÎÏÔÖÙÛÜ]');
  static final RegExp _number = RegExp(r'^[(\[]?[\d.,:/\-%€$]*\d[\d.,:/\-%€$]*[)\]]?[.,;:]?$');

  static OcrQuality of(List<OcrLineBox> lines) {
    int tokens = 0;
    int plausible = 0;
    double score = 0;
    double confidenceSum = 0;
    int confidenceCount = 0;
    for (final line in lines) {
      final confidence = line.confidence;
      if (confidence != null) {
        confidenceSum += confidence;
        confidenceCount++;
      }
      for (final token in line.text.split(RegExp(r'\s+'))) {
        if (token.isEmpty) continue;
        tokens++;
        final isWord = _word.hasMatch(token) && _vowel.hasMatch(token);
        final isNumber = _number.hasMatch(token) && RegExp(r'\d.*\d').hasMatch(token);
        if (isWord || isNumber) {
          plausible++;
          score += token.length * (confidence ?? 0.75);
        }
      }
    }
    return OcrQuality(tokens, plausible, confidenceCount == 0 ? null : confidenceSum / confidenceCount, score);
  }
}

class OcrProgress {
  final int done;
  final int total;

  const OcrProgress(this.done, this.total);
}

/// Runs on-device OCR for document pages and keeps the stored documents up to date.
class OcrService {
  static final OcrService instance = OcrService._();
  OcrService._();

  OcrEngine engine = OcrEngine.platformDefault();

  /// Per-document progress of running OCR jobs (document id → pages done / total).
  final ValueNotifier<Map<String, OcrProgress>> progress = ValueNotifier(const {});
  final Map<String, Future<void>> _running = {};

  bool get isAvailable => engine.isAvailable;

  bool isRunning(String docId) => _running.containsKey(docId);

  /// Recognizes every page without text (all pages when [force]), saving after each
  /// page, then stores the document analysis. Concurrent calls share one job.
  Future<void> processDocument(String docId, {bool force = false}) {
    final existing = _running[docId];
    if (existing != null) return existing;
    final job = _process(docId, force).whenComplete(() {
      _running.remove(docId);
      _setProgress(docId, null);
    });
    _running[docId] = job;
    return job;
  }

  Future<void> _process(String docId, bool force) async {
    final repo = DocumentRepository.instance;
    final doc = repo.byId(docId);
    if (doc == null) return;
    if (engine.isAvailable) {
      final pending = doc.pages.where((page) => force || !page.hasOcr).map((page) => page.id).toList();
      for (int i = 0; i < pending.length; i++) {
        _setProgress(docId, OcrProgress(i, pending.length));
        ScannedPage? page;
        for (final candidate in repo.byId(docId)?.pages ?? const <ScannedPage>[]) {
          if (candidate.id == pending[i]) page = candidate;
        }
        if (page == null || page.processedImagePath == null) continue;
        try {
          final original = page;
          final updated = await recognizePage(original);
          bool applied = false;
          await repo.updateDocument(docId, (current) {
            final pages = current.pages.map((candidate) {
              // Discard the result if the page was edited while OCR was running.
              if (candidate.id != original.id || candidate.processedImagePath != original.processedImagePath) return candidate;
              applied = true;
              return updated;
            }).toList();
            return current.copyWith(pages: pages, clearAnalysis: true);
          });
          if (updated.processedImagePath != original.processedImagePath) {
            await repo.deleteFiles([applied ? original.processedImagePath : updated.processedImagePath]);
          }
        } catch (e, st) {
          debugPrint('OCR failed for page ${page.id}: $e\n$st');
        }
      }
    }
    await refreshAnalysis(docId);
  }

  /// Recomputes and stores the analysis once every page has been recognized.
  Future<void> refreshAnalysis(String docId) async {
    final doc = DocumentRepository.instance.byId(docId);
    if (doc == null || !doc.isFullyRecognized) return;
    final analysis = DocumentAnalyzer.analyze(doc.combinedText);
    await DocumentRepository.instance.updateDocument(docId, (d) => d.copyWith(analysis: analysis));
  }

  /// OCR for one page. A page whose text turns out to be rotated is turned
  /// upright, so the returned page may point to a new processed image.
  Future<ScannedPage> recognizePage(ScannedPage page) async {
    final repo = DocumentRepository.instance;
    final tmp = (await repo.tempDirectory()).path;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final temps = <String>[];
    final createdImages = <String>[];
    var current = page;
    try {
      // Layout-based orientation check first: ML Kit half-reads sideways text, so a
      // "readable" result alone does not prove the page is upright.
      final source = current.processedImagePath!;
      final estimate = await Isolate.run(() => OcrImagePrep.estimateOrientation(source));
      if (estimate.isReliable && estimate.rotation != 0) {
        current = await _rotate(current, estimate.rotation, createdImages);
      }

      var input = await _inputFor(current, p.join(tmp, 'ocr_${page.id}_$stamp.jpg'), temps);
      var lines = await engine.recognizeFile(input.path);
      var quality = OcrQuality.of(lines);

      // Still gibberish or tilted lines: compare OCR in all four orientations.
      if (!quality.looksGood || _linesLookRotated(lines)) {
        final fix = await _bestRotation(current.processedImagePath!, p.join(tmp, 'trial_${page.id}_$stamp'), temps);
        if (fix != 0) {
          final rotated = await _rotate(current, fix, createdImages);
          final rotatedInput = await _inputFor(rotated, p.join(tmp, 'ocr_${page.id}_${stamp}_fixed.jpg'), temps);
          final rotatedLines = await engine.recognizeFile(rotatedInput.path);
          final rotatedQuality = OcrQuality.of(rotatedLines);
          if (rotatedQuality.score > quality.score) {
            current = rotated;
            input = rotatedInput;
            lines = rotatedLines;
            quality = rotatedQuality;
          }
        }
      }

      final layout = LayoutReconstructor.reconstruct(lines);
      final w = input.width.toDouble();
      final h = input.height.toDouble();
      return current.copyWith(
        ocrText: layout.text,
        ocrLines: layout.lines
            .map((l) => OcrLine(
                  text: l.text,
                  left: (l.left / w).clamp(0.0, 1.0),
                  top: (l.top / h).clamp(0.0, 1.0),
                  right: (l.right / w).clamp(0.0, 1.0),
                  bottom: (l.bottom / h).clamp(0.0, 1.0),
                  confidence: l.confidence,
                ))
            .toList(),
        ocrConfidence: quality.meanConfidence,
      );
    } catch (_) {
      await repo.deleteFiles(createdImages);
      rethrow;
    } finally {
      await repo.deleteFiles(temps);
      // Intermediate rotated images (all but the final one) are no longer needed.
      await repo.deleteFiles(createdImages.where((path) => path != current.processedImagePath));
    }
  }

  static const _normalizedFilters = {ScanFilterType.magicColor, ScanFilterType.sharpBW, ScanFilterType.grayscale};

  /// The image to recognize: the processed page itself when its filter already
  /// removed shadows and it has a good size, otherwise a prepared grayscale copy.
  Future<OcrInput> _inputFor(ScannedPage page, String preparedPath, List<String> temps) async {
    final source = page.processedImagePath!;
    if (_normalizedFilters.contains(page.filterType)) {
      final size = await Isolate.run(() => OcrImagePrep.jpegSize(source));
      if (size != null) {
        final longSide = size.width > size.height ? size.width : size.height;
        if (longSide >= OcrImagePrep.minLongSide && longSide <= OcrImagePrep.maxLongSide) {
          return OcrInput(source, size.width, size.height);
        }
      }
    }
    final input = await Isolate.run(() => OcrImagePrep.prepare(source, preparedPath));
    temps.add(input.path);
    return input;
  }

  /// ML Kit reports each line's tilt; upright text is close to 0°.
  static bool _linesLookRotated(List<OcrLineBox> lines) {
    final angles = lines.map((l) => l.angle?.abs()).whereType<double>().toList()..sort();
    if (angles.length < 5) return false;
    return angles[angles.length ~/ 2] > 30;
  }

  /// The extra clockwise rotation that clearly improves recognition, or 0.
  Future<int> _bestRotation(String source, String prefix, List<String> temps) async {
    final trials = await Isolate.run(() => OcrImagePrep.prepareRotationTrials(source, prefix));
    temps.addAll(trials.values);
    final scores = <int, OcrQuality>{};
    for (final entry in trials.entries) {
      scores[entry.key] = OcrQuality.of(await engine.recognizeFile(entry.value));
    }
    final base = scores[0]!;
    final best = scores.entries.reduce((a, b) => a.value.score >= b.value.score ? a : b);
    if (best.key != 0 && best.value.plausible >= 8 && best.value.score > base.score * 1.4) return best.key;
    return 0;
  }

  Future<ScannedPage> _rotate(ScannedPage page, int degrees, List<String> createdImages) async {
    final output = await DocumentRepository.instance.newProcessedPath(page.id);
    await CvIsolateService.rotateImageFileAsync(page.processedImagePath!, output, degrees);
    createdImages.add(output);
    return page.copyWith(
      processedImagePath: output,
      rotationDegrees: (page.rotationDegrees + degrees) % 360,
      clearOcr: true,
    );
  }

  void _setProgress(String docId, OcrProgress? value) {
    final next = Map<String, OcrProgress>.of(progress.value);
    if (value == null) {
      next.remove(docId);
    } else {
      next[docId] = value;
    }
    progress.value = next;
  }
}
