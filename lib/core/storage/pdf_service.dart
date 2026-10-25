import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/document.dart';
import 'document_repository.dart';

/// Builds searchable PDFs: each page image with its OCR text laid over it as
/// invisible text, so viewers can search and select it.
class PdfService {
  static const double _pageWidthPt = 595.28; // A4 width

  static Future<File> generatePdf(ScannedDocument document) async {
    final pdf = pw.Document(title: document.title, author: 'ClearScan', creator: 'ClearScan');
    final font = pw.Font.helvetica();

    for (final page in document.pages) {
      final file = File(page.displayImagePath);
      if (!await file.exists()) continue;
      final image = pw.MemoryImage(await file.readAsBytes());
      final aspect = (image.height ?? 1) / max(1, image.width ?? 1);
      final pageW = _pageWidthPt;
      final pageH = pageW * aspect;

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat(pageW, pageH, marginAll: 0),
        build: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Stack(
            fit: pw.StackFit.expand,
            children: [
              pw.Image(image, fit: pw.BoxFit.fill),
              for (final line in page.ocrLines) ?_invisibleLine(line, pageW, pageH, font),
            ],
          ),
        ),
      ));
    }

    final dir = await DocumentRepository.instance.exportsDirectory();
    final safeTitle = document.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    final output = File(p.join(dir.path, '${safeTitle.isEmpty ? 'scan' : safeTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf'));
    await output.writeAsBytes(await pdf.save());
    return output;
  }

  static Future<void> shareOrPrintPdf(ScannedDocument document) async {
    final file = await generatePdf(document);
    await Printing.sharePdf(bytes: await file.readAsBytes(), filename: p.basename(file.path));
  }

  static pw.Widget? _invisibleLine(OcrLine line, double pageW, double pageH, pw.Font font) {
    final text = pdfSafeText(line.text);
    final boxW = line.width * pageW;
    final boxH = line.height * pageH;
    if (text.trim().isEmpty || boxW < 1 || boxH < 1) return null;
    return pw.Positioned(
      left: line.left * pageW,
      top: line.top * pageH,
      child: pw.SizedBox(
        width: boxW,
        height: boxH,
        child: pw.FittedBox(
          fit: pw.BoxFit.fill,
          child: pw.Text(
            text,
            style: pw.TextStyle(font: font, fontSize: max(1.0, boxH * 0.8), renderingMode: PdfTextRenderingMode.invisible),
          ),
        ),
      ),
    );
  }

  /// The built-in PDF font covers Latin-1 only; map common punctuation and drop the rest.
  static String pdfSafeText(String input) {
    const replacements = {
      '’': "'", '‘': "'", '“': '"', '”': '"', '–': '-', '—': '-', '…': '...', '•': '*', '€': 'EUR',
      'œ': 'oe', 'Œ': 'OE', ' ': ' ', ' ': ' ',
    };
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final c = String.fromCharCode(rune);
      final mapped = replacements[c];
      if (mapped != null) {
        buffer.write(mapped);
      } else if (rune >= 0x20 && rune <= 0xFF) {
        buffer.write(c);
      }
    }
    return buffer.toString();
  }
}
