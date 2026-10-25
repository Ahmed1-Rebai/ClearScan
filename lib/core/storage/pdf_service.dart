import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/document.dart';

/// Service for generating and exporting searchable multi-page PDF files.
class PdfService {
  /// Compiles a [ScannedDocument] into a high-quality multi-page PDF and returns the saved file.
  static Future<File> generatePdf(ScannedDocument document) async {
    final pdf = pw.Document(
      title: document.title,
      author: 'CamScanner Local AI (Gemma)',
    );

    for (int i = 0; i < document.pages.length; i++) {
      final page = document.pages[i];
      final imagePath = page.processedImagePath ?? page.rawImagePath;
      final file = File(imagePath);

      if (await file.exists()) {
        final Uint8List imageBytes = await file.readAsBytes();
        final image = pw.MemoryImage(imageBytes);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (pw.Context context) {
              return pw.FullPage(
                ignoreMargins: true,
                child: pw.Center(
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              );
            },
          ),
        );
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory(p.join(appDir.path, 'exports'));
    if (!await pdfDir.exists()) await pdfDir.create(recursive: true);

    final sanitizedTitle = document.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final fileName = '${sanitizedTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final outputFile = File(p.join(pdfDir.path, fileName));

    await outputFile.writeAsBytes(await pdf.save());
    return outputFile;
  }

  /// Opens the system print/share dialog for the generated PDF.
  static Future<void> shareOrPrintPdf(ScannedDocument document) async {
    final file = await generatePdf(document);
    final bytes = await file.readAsBytes();
    await Printing.sharePdf(bytes: bytes, filename: p.basename(file.path));
  }
}

