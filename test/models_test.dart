import 'dart:convert';
import 'package:cam_scan/core/analysis/document_analyzer.dart';
import 'package:cam_scan/core/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScannedDocument JSON', () {
    test('loads documents saved by the previous app version', () {
      // Format written by v1.1 (no OCR lines, unused gemmaMetadata).
      final legacy = jsonDecode('''
      {"id":"d1","title":"Scan_10_25_1356","pages":[{"id":"p1","rawImagePath":"/raw.jpg",
       "processedImagePath":"/proc.jpg","corners":{"topLeft":{"dx":1,"dy":2},"topRight":{"dx":3,"dy":2},
       "bottomRight":{"dx":3,"dy":4},"bottomLeft":{"dx":1,"dy":4}},"filterType":"magicColor","rotationDegrees":0,
       "createdAt":"2026-10-25T13:56:00.000","ocrText":null}],"tags":[],"createdAt":"2026-10-25T13:56:00.000",
       "updatedAt":"2026-10-25T13:56:00.000","gemmaMetadata":null}''') as Map<String, dynamic>;
      final doc = ScannedDocument.fromJson(legacy);
      expect(doc.title, 'Scan_10_25_1356');
      expect(doc.pages.single.hasOcr, isFalse);
      expect(doc.pages.single.ocrLines, isEmpty);
      expect(doc.analysis, isNull);
      expect(doc.isFullyRecognized, isFalse);
    });

    test('round-trips OCR lines and analysis', () {
      const text = 'FACTURE N° 12-A\nTotal TTC : 120,000 DT';
      final page = ScannedPage(
        rawImagePath: '/raw.jpg',
        processedImagePath: '/proc.jpg',
        ocrText: text,
        ocrLines: const [OcrLine(text: 'FACTURE N° 12-A', left: 0.1, top: 0.1, right: 0.6, bottom: 0.14, confidence: 0.91)],
        ocrConfidence: 0.91,
      );
      final doc = ScannedDocument(title: 'Doc', pages: [page], analysis: DocumentAnalyzer.analyze(text));
      final copy = ScannedDocument.fromJson(jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
      expect(copy.pages.single.ocrLines.single.text, 'FACTURE N° 12-A');
      expect(copy.pages.single.ocrLines.single.right, 0.6);
      expect(copy.pages.single.ocrConfidence, 0.91);
      expect(copy.analysis!.extractedFields.map((f) => f.key), doc.analysis!.extractedFields.map((f) => f.key));
      expect(copy.analysis!.extractedFields.first.evidence, isNotNull);
    });
  });

  group('ScannedPage', () {
    test('clearOcr removes stale text when the image changes', () {
      final page = ScannedPage(
        rawImagePath: '/raw.jpg',
        ocrText: 'old',
        ocrLines: const [OcrLine(text: 'old', left: 0, top: 0, right: 1, bottom: 1)],
        ocrConfidence: 0.8,
      );
      final edited = page.copyWith(processedImagePath: '/new.jpg', clearOcr: true);
      expect(edited.ocrText, isNull);
      expect(edited.ocrLines, isEmpty);
      expect(edited.ocrConfidence, isNull);
      expect(page.copyWith(rotationDegrees: 90).ocrText, 'old');
    });
  });

  group('combinedText', () {
    test('single page has no page markers; multiple pages are labeled', () {
      final one = ScannedDocument(title: 'a', pages: [ScannedPage(rawImagePath: '/1', ocrText: 'Hello')]);
      expect(one.combinedText, 'Hello');
      final two = ScannedDocument(title: 'b', pages: [
        ScannedPage(rawImagePath: '/1', ocrText: 'First'),
        ScannedPage(rawImagePath: '/2', ocrText: ''),
        ScannedPage(rawImagePath: '/3', ocrText: 'Third'),
      ]);
      expect(two.combinedText, '--- Page 1 ---\nFirst\n\n--- Page 3 ---\nThird');
      expect(two.isFullyRecognized, isTrue);
    });
  });

  group('DocumentCorners', () {
    test('convexity check rejects folded quads', () {
      expect(DocumentCorners.fullImage(100, 100).isConvex, isTrue);
      const folded = DocumentCorners(
        topLeft: Offset(0, 0),
        topRight: Offset(100, 100),
        bottomRight: Offset(100, 0),
        bottomLeft: Offset(0, 100),
      );
      expect(folded.isConvex, isFalse);
    });
  });
}
