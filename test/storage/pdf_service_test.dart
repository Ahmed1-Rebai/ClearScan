import 'dart:io';
import 'dart:convert';
import 'package:cam_scan/core/models/document.dart';
import 'package:cam_scan/core/storage/document_repository.dart';
import 'package:cam_scan/core/storage/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/fakes.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clearscan_pdf_');
    DocumentRepository.instance.useBaseDirectoryForTesting(dir);
  });

  tearDown(() => dir.delete(recursive: true));

  test('exports one PDF page per scanned page, with the OCR text layer', () async {
    final pages = [
      for (int i = 0; i < 2; i++)
        ScannedPage(
          rawImagePath: writeJpeg(p.join(dir.path, 'raw$i.jpg')),
          processedImagePath: writeJpeg(p.join(dir.path, 'proc$i.jpg'), width: 600, height: 850),
          ocrText: 'Facture N° $i',
          ocrLines: [OcrLine(text: 'Facture N° $i — total 12,50 €', left: 0.1, top: 0.1, right: 0.7, bottom: 0.14)],
        ),
    ];
    final file = await PdfService.generatePdf(ScannedDocument(title: 'Facture / Octobre', pages: pages));

    expect(p.basename(file.path), startsWith('Facture_Octobre_'));
    final bytes = file.readAsBytesSync();
    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    final pageObjects = RegExp(r'/Type\s*/Page[^s]').allMatches(latin1.decode(bytes)).length;
    expect(pageObjects, 2);
  });

  test('text layer is limited to characters the built-in font can encode', () {
    expect(PdfService.pdfSafeText('Total — 12,50 € “TTC” • œuvre'), 'Total - 12,50 EUR "TTC" * oeuvre');
    expect(PdfService.pdfSafeText('Prix: ١٢٣ 漢字 ok'), 'Prix:   ok');
  });
}
