import 'dart:io';
import 'package:cam_scan/core/models/document.dart';
import 'package:cam_scan/core/models/document_analysis.dart';
import 'package:cam_scan/core/ocr/layout_reconstructor.dart';
import 'package:cam_scan/core/ocr/ocr_service.dart';
import 'package:cam_scan/core/storage/document_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/fakes.dart';

void main() {
  late Directory dir;
  final repo = DocumentRepository.instance;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clearscan_test_');
    repo.useBaseDirectoryForTesting(dir);
    await repo.initialize();
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  ScannedPage pageWithImages(String name, {int width = 600, int height = 800}) {
    Directory(p.join(dir.path, 'scans', 'raw')).createSync(recursive: true);
    Directory(p.join(dir.path, 'scans', 'processed')).createSync(recursive: true);
    return ScannedPage(
      rawImagePath: writeJpeg(p.join(dir.path, 'scans', 'raw', '$name.jpg'), width: width, height: height),
      processedImagePath: writeJpeg(p.join(dir.path, 'scans', 'processed', '$name.jpg'), width: width, height: height),
      corners: DocumentCorners.fullImage(width.toDouble(), height.toDouble()),
    );
  }

  group('DocumentRepository', () {
    test('persists documents and reloads them from disk', () async {
      final doc = ScannedDocument(title: 'Persisted', pages: [pageWithImages('a')]);
      await repo.saveDocument(doc);
      repo.useBaseDirectoryForTesting(dir);
      await repo.initialize();
      expect(repo.byId(doc.id)?.title, 'Persisted');
      expect(File(p.join(dir.path, 'documents_index.json.tmp')).existsSync(), isFalse, reason: 'atomic write leaves no temp file');
    });

    test('updateDocument applies the change to the latest version and notifies', () async {
      final doc = ScannedDocument(title: 'Before', pages: [pageWithImages('b')]);
      await repo.saveDocument(doc);
      int notifications = 0;
      void listener() => notifications++;
      repo.addListener(listener);
      await repo.updateDocument(doc.id, (d) => d.copyWith(title: 'After'));
      repo.removeListener(listener);
      expect(repo.byId(doc.id)!.title, 'After');
      expect(notifications, 1);
    });

    test('deleteDocument removes page images', () async {
      final page = pageWithImages('c');
      final doc = ScannedDocument(title: 'Delete me', pages: [page]);
      await repo.saveDocument(doc);
      await repo.deleteDocument(doc.id);
      expect(repo.byId(doc.id), isNull);
      expect(File(page.rawImagePath).existsSync(), isFalse);
      expect(File(page.processedImagePath!).existsSync(), isFalse);
    });

    test('garbage collection removes only old, unreferenced images', () async {
      final kept = pageWithImages('kept');
      await repo.saveDocument(ScannedDocument(title: 'Kept', pages: [kept]));
      final oldOrphan = File(writeJpeg(p.join(dir.path, 'scans', 'raw', 'orphan_old.jpg')));
      final newOrphan = File(writeJpeg(p.join(dir.path, 'scans', 'raw', 'orphan_new.jpg')));
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      oldOrphan.setLastModifiedSync(twoDaysAgo);
      File(kept.rawImagePath).setLastModifiedSync(twoDaysAgo);

      final removed = await repo.collectGarbage();
      expect(removed, 1);
      expect(oldOrphan.existsSync(), isFalse);
      expect(newOrphan.existsSync(), isTrue, reason: 'may belong to a scan in progress');
      expect(File(kept.rawImagePath).existsSync(), isTrue);
    });

    test('imported photos get unique paths', () async {
      final bytes = File(writeJpeg(p.join(dir.path, 'src.jpg'))).readAsBytesSync();
      final a = await repo.importImageBytes(bytes);
      final b = await repo.importImageBytes(bytes);
      expect(a, isNot(b));
      expect(File(a).existsSync(), isTrue);
    });
  });

  group('OcrService with a fake engine', () {
    const fixture = [
      OcrLineBox(text: 'SOCIETE ALPHA SARL', left: 80, top: 60, right: 520, bottom: 90, confidence: 0.95),
      OcrLineBox(text: 'FACTURE N° FA-77', left: 80, top: 120, right: 480, bottom: 150, confidence: 0.93),
      OcrLineBox(text: 'Total HT', left: 80, top: 600, right: 260, bottom: 630, confidence: 0.9),
      OcrLineBox(text: '100,000 DT', left: 700, top: 601, right: 900, bottom: 631, confidence: 0.9),
      OcrLineBox(text: 'TVA 19%', left: 80, top: 640, right: 240, bottom: 670, confidence: 0.9),
      OcrLineBox(text: '19,000 DT', left: 700, top: 641, right: 900, bottom: 671, confidence: 0.9),
      OcrLineBox(text: 'Net à payer', left: 80, top: 680, right: 300, bottom: 710, confidence: 0.9),
      OcrLineBox(text: '119,000 DT', left: 700, top: 681, right: 900, bottom: 711, confidence: 0.9),
      OcrLineBox(text: 'Merci pour votre confiance et à bientôt', left: 80, top: 760, right: 900, bottom: 790, confidence: 0.9),
    ];

    test('recognizes every page, stores normalized boxes and analyses the document', () async {
      final engine = FakeOcrEngine(fixture);
      OcrService.instance.engine = engine;
      final doc = ScannedDocument(title: 'Invoice', pages: [pageWithImages('p1', width: 1000, height: 1400)]);
      await repo.saveDocument(doc);

      await OcrService.instance.processDocument(doc.id);

      final result = repo.byId(doc.id)!;
      final page = result.pages.single;
      expect(page.ocrText, contains('Net à payer   119,000 DT'), reason: 'label and amount re-joined on one row');
      expect(page.ocrLines, isNotEmpty);
      for (final l in page.ocrLines) {
        expect(l.left, inInclusiveRange(0, 1));
        expect(l.bottom, inInclusiveRange(0, 1));
      }
      expect(result.analysis, isNotNull);
      expect(result.analysis!.documentType, DocumentType.invoice);
      expect(result.analysis!.extractedFields.firstWhere((f) => f.key == 'Total').value, '119,000 DT');
      expect(OcrService.instance.progress.value.containsKey(doc.id), isFalse);
    });

    test('turns a sideways page upright when its text is unreadable', () async {
      final engine = FakeOcrEngine(fixture);
      OcrService.instance.engine = engine;
      final doc = ScannedDocument(title: 'Sideways', pages: [pageWithImages('side', width: 1400, height: 1000)]);
      await repo.saveDocument(doc);
      final originalImage = doc.pages.single.processedImagePath!;

      await OcrService.instance.processDocument(doc.id);

      final page = repo.byId(doc.id)!.pages.single;
      expect(page.rotationDegrees, 90);
      expect(page.processedImagePath, isNot(originalImage));
      expect(File(originalImage).existsSync(), isFalse, reason: 'replaced image is cleaned up');
      expect(page.ocrText, contains('FACTURE N° FA-77'));
    });

    test('pages edited while OCR runs keep the edit', () async {
      final engine = FakeOcrEngine(fixture);
      OcrService.instance.engine = engine;
      final doc = ScannedDocument(title: 'Race', pages: [pageWithImages('race', width: 1000, height: 1400)]);
      await repo.saveDocument(doc);

      final job = OcrService.instance.processDocument(doc.id);
      final editedPath = writeJpeg(p.join(dir.path, 'scans', 'processed', 'edited.jpg'), width: 1000, height: 1400);
      await repo.updateDocument(doc.id, (d) => d.copyWith(pages: [d.pages.single.copyWith(processedImagePath: editedPath, clearOcr: true)]));
      await job;

      final page = repo.byId(doc.id)!.pages.single;
      expect(page.processedImagePath, editedPath);
      expect(page.hasOcr, isFalse, reason: 'stale OCR of the old image must not be applied');
    });
  });
}
