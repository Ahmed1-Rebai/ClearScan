import 'dart:io';
import 'package:cam_scan/core/analysis/document_analyzer.dart';
import 'package:cam_scan/core/models/document.dart';
import 'package:cam_scan/core/ocr/ocr_engine.dart';
import 'package:cam_scan/core/ocr/ocr_service.dart';
import 'package:cam_scan/core/storage/document_repository.dart';
import 'package:cam_scan/ui/app_theme.dart';
import 'package:cam_scan/ui/screens/camera_screen.dart';
import 'package:cam_scan/ui/screens/crop_screen.dart';
import 'package:cam_scan/ui/screens/document_detail_screen.dart';
import 'package:cam_scan/ui/screens/filter_screen.dart';
import 'package:cam_scan/ui/screens/home_screen.dart';
import 'package:cam_scan/ui/screens/insights_screen.dart';
import 'package:cam_scan/ui/screens/scan_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/fakes.dart';

/// Renders every screen at small phones, landscape and tablet sizes with large
/// text. Any "RenderFlex overflowed by N pixels" error fails the test.
void main() {
  const sizes = {
    'small phone 320x568': Size(320, 568),
    'phone 360x640': Size(360, 640),
    'Redmi Note 14 Pro 384x853': Size(384, 853),
    'landscape 853x384': Size(853, 384),
    'tablet 1280x800': Size(1280, 800),
  };
  const textScales = [1.0, 1.5, 2.0];

  late Directory dir;
  late ScannedDocument invoice;
  late ScannedDocument pending;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('clearscan_ui_');
    DocumentRepository.instance.useBaseDirectoryForTesting(dir);
    await DocumentRepository.instance.initialize();
    OcrService.instance.engine = const UnavailableOcrEngine();
    Directory(p.join(dir.path, 'img')).createSync();

    const text = '''SOCIETE DE DISTRIBUTION ET DE SERVICES INFORMATIQUES DU SAHEL SARL
FACTURE N° FA-2026-000123456
Date : 12/10/2026
Date d'échéance : 11/11/2026
Client : Etablissement Benali pour le commerce international et la logistique
Maintenance des serveurs de production et sauvegardes externalisées   2   400,000   800,000
Total HT   1 000,000 DT
TVA 19%   190,000 DT
Timbre fiscal   1,000 DT
Net à payer   1 191,000 DT
IBAN : TN59 1000 6035 1835 9847 8831
Email : comptabilite.fournisseurs@distribution-services-sahel.com.tn''';
    final pages = [
      for (int i = 0; i < 3; i++)
        ScannedPage(
          rawImagePath: writeJpeg(p.join(dir.path, 'img', 'raw$i.jpg')),
          processedImagePath: writeJpeg(p.join(dir.path, 'img', 'proc$i.jpg')),
          corners: DocumentCorners.fullImage(600, 800),
          ocrText: i == 0 ? text : 'Conditions générales de vente, page ${i + 1}.',
          ocrConfidence: 0.87,
        ),
    ];
    invoice = ScannedDocument(
      title: 'Facture fournisseur octobre 2026 — distribution et services informatiques',
      pages: pages,
    );
    invoice = invoice.copyWith(analysis: DocumentAnalyzer.analyze(invoice.combinedText));
    pending = ScannedDocument(title: 'Scan pending', pages: [
      ScannedPage(rawImagePath: writeJpeg(p.join(dir.path, 'img', 'raw_pending.jpg'))),
    ]);
    await DocumentRepository.instance.saveDocument(pending);
    await DocumentRepository.instance.saveDocument(invoice);
  });

  tearDownAll(() async {
    await dir.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen, Size size, double textScale, {bool dark = false}) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: screen,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  final screens = <String, Widget Function()>{
    'Home': () => const HomeScreen(),
    'Document detail': () => DocumentDetailScreen(documentId: invoice.id),
    'Document detail (OCR unavailable)': () => DocumentDetailScreen(documentId: pending.id),
    'Insights': () => InsightsScreen(documentId: invoice.id),
    'Scan review': () => ScanReviewScreen(documentId: invoice.id),
    'Camera (no camera available)': () => const CameraScreen(),
    'Crop': () => CropScreen(rawImagePath: invoice.pages.first.rawImagePath),
    'Filter': () => FilterScreen(page: invoice.pages.first),
  };

  for (final screen in screens.entries) {
    for (final size in sizes.entries) {
      for (final scale in textScales) {
        testWidgets('${screen.key} — ${size.key} — text ×$scale', (tester) async {
          await pumpScreen(tester, screen.value(), size.value, scale, dark: scale == 1.5);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final size in sizes.entries) {
    testWidgets('Home selection mode — ${size.key} — text ×1.5', (tester) async {
      await pumpScreen(tester, const HomeScreen(), size.value, 1.5);
      await tester.longPress(find.textContaining('Facture fournisseur'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byTooltip('Delete selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Camera controls fill the screen — ${size.key}', (tester) async {
      await pumpScreen(tester, const CameraScreen(), size.value, 1.0);
      final height = size.value.height;
      expect(tester.getCenter(find.byTooltip('Import from gallery')).dy, greaterThan(height * 0.75));
      expect(tester.getCenter(find.byTooltip('Close')).dy, lessThan(height * 0.2));
    });

    testWidgets('Insights tabs (Ask, Text) — ${size.key} — text ×1.5', (tester) async {
      await pumpScreen(tester, InsightsScreen(documentId: invoice.id), size.value, 1.5);
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Quel est le montant total ?');
      await tester.tap(find.byTooltip('Ask'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 191,000 DT'), findsWidgets);
      await tester.tap(find.text('Text'));
      await tester.pumpAndSettle();
      expect(find.text('Recognized text'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
