import 'dart:io';
import 'package:cam_scan/core/models/document.dart';
import 'package:cam_scan/core/ocr/ocr_engine.dart';
import 'package:cam_scan/core/ocr/ocr_service.dart';
import 'package:cam_scan/core/storage/document_repository.dart';
import 'package:cam_scan/ui/app_theme.dart';
import 'package:cam_scan/ui/screens/document_detail_screen.dart';
import 'package:cam_scan/ui/screens/scan_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../helpers/fakes.dart';
import '../helpers/synthetic_images.dart';

void main() {
  late Directory dir;
  final repo = DocumentRepository.instance;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clearscan_review_');
    repo.useBaseDirectoryForTesting(dir);
    await repo.initialize();
    OcrService.instance.engine = const UnavailableOcrEngine();
    Directory(p.join(dir.path, 'scans', 'raw')).createSync(recursive: true);
    Directory(p.join(dir.path, 'scans', 'processed')).createSync(recursive: true);
  });

  tearDown(() => dir.delete(recursive: true));

  /// Lets real time pass (isolates, file IO) and rebuilds, until [done] or a timeout.
  Future<void> settleReal(WidgetTester tester, bool Function() done) async {
    for (int i = 0; i < 120 && !done(); i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpReview(WidgetTester tester, ScanReviewScreen screen) async {
    tester.view.physicalSize = const Size(768, 1706);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
    await tester.pump();
  }

  testWidgets('a multi-page scan is processed and saved as one document', (tester) async {
    final raws = [
      for (final name in ['page1', 'page2'])
        (File(p.join(dir.path, 'scans', 'raw', '$name.jpg'))..writeAsBytesSync(img.encodeJpg(syntheticTextPage(width: 900, height: 1200)))).path,
    ];

    await pumpReview(tester, ScanReviewScreen(newRawPaths: raws));
    expect(find.text('Page 1 of 2'), findsOneWidget);

    // Page processing runs in background isolates: wait for real time to pass.
    await settleReal(tester, () => tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null);
    expect(find.text('Save (2)'), findsOneWidget);

    await tester.tap(find.text('Save (2)'));
    await settleReal(tester, () => find.byType(DocumentDetailScreen).evaluate().isNotEmpty);

    expect(repo.documents, hasLength(1));
    final doc = repo.documents.single;
    expect(doc.pageCount, 2);
    expect(doc.pages.map((p) => p.rawImagePath), raws);
    for (final page in doc.pages) {
      expect(File(page.processedImagePath!).existsSync(), isTrue);
      expect(page.corners, isNotNull);
    }
    expect(find.byType(DocumentDetailScreen), findsOneWidget);
  });

  testWidgets('deleting a page of an existing document removes it and its files', (tester) async {
    ScannedPage page(String name) => ScannedPage(
          rawImagePath: writeJpeg(p.join(dir.path, 'scans', 'raw', '$name.jpg')),
          processedImagePath: writeJpeg(p.join(dir.path, 'scans', 'processed', '$name.jpg')),
          corners: DocumentCorners.fullImage(600, 800),
          ocrText: 'Text of $name',
        );
    final doc = ScannedDocument(title: 'Three pages', pages: [page('a'), page('b'), page('c')]);
    await tester.runAsync(() => repo.saveDocument(doc));

    await pumpReview(tester, ScanReviewScreen(documentId: doc.id));
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(find.text('Page 1 of 2'), findsOneWidget);

    await tester.tap(find.text('Save (2)'));
    await settleReal(tester, () => !File(doc.pages.first.processedImagePath!).existsSync());

    final saved = repo.byId(doc.id)!;
    expect(saved.pages.map((p) => p.ocrText), ['Text of b', 'Text of c']);
    expect(File(doc.pages.first.rawImagePath).existsSync(), isFalse);
    expect(File(doc.pages.first.processedImagePath!).existsSync(), isFalse);
  });
}
