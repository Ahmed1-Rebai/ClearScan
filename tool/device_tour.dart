// Development tool: drives the real app on a device so screens can be captured
// without touch input. Build with:
//   flutter build apk --profile -t tool/device_tour.dart
// It prints "TOUR:<name>" before each screen; capture with `adb exec-out screencap`.
// Installing with `adb install -r` keeps the app's documents.
import 'dart:math';
import 'package:cam_scan/core/cv/cv_isolate_service.dart';
import 'package:cam_scan/core/models/document.dart';
import 'package:cam_scan/core/ocr/ocr_service.dart';
import 'package:cam_scan/core/storage/document_repository.dart';
import 'package:cam_scan/ui/app_theme.dart';
import 'package:cam_scan/ui/screens/camera_screen.dart';
import 'package:cam_scan/ui/screens/document_detail_screen.dart';
import 'package:cam_scan/ui/screens/home_screen.dart';
import 'package:cam_scan/ui/screens/insights_screen.dart';
import 'package:cam_scan/ui/screens/scan_review_screen.dart';
import 'package:flutter/material.dart';

final _navigator = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = DocumentRepository.instance;
  await repo.initialize();
  runApp(MaterialApp(
    navigatorKey: _navigator,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ThemeMode.dark,
    home: const HomeScreen(),
  ));
  await _pause(4);
  await _mark('home_before');

  for (final doc in repo.documents) {
    final sw = Stopwatch()..start();
    await OcrService.instance.processDocument(doc.id, force: true);
    final done = repo.byId(doc.id)!;
    final text = done.combinedText;
    _log('OCR "${done.title}" pages=${done.pageCount} ${sw.elapsedMilliseconds}ms '
        'rotations=${done.pages.map((p) => p.rotationDegrees).toList()} chars=${text.length} '
        'conf=${done.pages.map((p) => p.ocrConfidence?.toStringAsFixed(2)).toList()}');
    _log('TEXT ${text.substring(0, min(400, text.length)).replaceAll('\n', ' ⏎ ')}');
    final a = done.analysis;
    if (a != null) {
      _log('ANALYSIS type=${a.documentType.name} lang=${a.language} '
          'fields=${a.extractedFields.map((f) => '${f.key}=${f.value}').join(' | ')}');
    }
  }
  await _pause(2);
  await _mark('home_after_ocr');

  final docs = repo.documents;
  if (docs.isNotEmpty) {
    final doc = docs.first;
    _push(DocumentDetailScreen(documentId: doc.id));
    await _pause(3);
    await _mark('detail');
    _push(InsightsScreen(documentId: doc.id));
    await _pause(3);
    await _mark('insights_overview');
    _selectTab(2);
    await _pause(2);
    await _mark('insights_text');
    _navigator.currentState!.popUntil((r) => r.isFirst);
    _push(ScanReviewScreen(documentId: doc.id));
    await _pause(3);
    await _mark('review_existing');
    _navigator.currentState!.popUntil((r) => r.isFirst);
    _push(const CameraScreen());
    await _pause(4);
    await _mark('camera');
    _navigator.currentState!.popUntil((r) => r.isFirst);
  }

  // Timing of the full pipeline on stored raw photos (nothing is saved).
  final raws = <String>{for (final d in docs) for (final p in d.pages) p.rawImagePath}.take(3).toList();
  for (final raw in raws) {
    final out = await repo.newProcessedPath('tour');
    final sw = Stopwatch()..start();
    final result = await CvIsolateService.processPageAsync(
      rawPath: raw,
      outputPath: out,
      filter: ScanFilterType.magicColor,
      autoOrient: true,
    );
    final processing = sw.elapsedMilliseconds;
    final page = ScannedPage(rawImagePath: raw, processedImagePath: out, corners: result.corners, rotationDegrees: result.rotation);
    final recognized = await OcrService.instance.recognizePage(page);
    _log('TIMING ${result.width}x${result.height} process=${processing}ms ocr=${sw.elapsedMilliseconds - processing}ms '
        'lines=${recognized.ocrLines.length}');
    await repo.deleteFiles([out, recognized.processedImagePath]);
  }
  _log('TOUR:done');
}

void _push(Widget screen) => _navigator.currentState!.push(MaterialPageRoute(builder: (_) => screen));

Future<void> _pause(int seconds) => Future.delayed(Duration(seconds: seconds));

Future<void> _mark(String name) async {
  _log('TOUR:$name');
  await _pause(3);
}

// ignore: avoid_print
void _log(String message) => print('CLEARSCAN $message');

void _selectTab(int index) {
  void visit(Element element) {
    final widget = element.widget;
    if (widget is TabBar && widget.controller != null) {
      widget.controller!.animateTo(index);
      return;
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
}
