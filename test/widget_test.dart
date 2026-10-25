import 'dart:io';
import 'package:cam_scan/core/models/document.dart';
import 'package:cam_scan/core/storage/app_settings.dart';
import 'package:cam_scan/core/storage/document_repository.dart';
import 'package:cam_scan/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fakes.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clearscan_app_');
    DocumentRepository.instance.useBaseDirectoryForTesting(dir);
  });

  tearDown(() => dir.delete(recursive: true));

  testWidgets('App smoke test: home screen with scan and import actions', (tester) async {
    await tester.pumpWidget(const ClearScanApp());
    await tester.pump();

    expect(find.text('ClearScan'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.byTooltip('Import images'), findsOneWidget);
    expect(find.text('Scan pages'), findsOneWidget, reason: 'empty library shows the onboarding actions');
  });

  testWidgets('Theme menu switches between system, light and dark', (tester) async {
    AppSettings.themeMode.value = ThemeMode.system;
    await tester.pumpWidget(const ClearScanApp());
    await tester.pump();

    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(AppSettings.themeMode.value, ThemeMode.light);
    expect(Theme.of(tester.element(find.text('ClearScan'))).brightness, Brightness.light);

    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(AppSettings.themeMode.value, ThemeMode.dark);
    expect(Theme.of(tester.element(find.text('ClearScan'))).brightness, Brightness.dark);
  });

  testWidgets('Long-press selects documents and the trash button deletes them', (tester) async {
    final docs = [
      for (final name in ['First scan', 'Second scan', 'Kept scan'])
        ScannedDocument(title: name, pages: [
          ScannedPage(
            rawImagePath: writeJpeg(p.join(dir.path, '$name-raw.jpg')),
            processedImagePath: writeJpeg(p.join(dir.path, '$name-proc.jpg')),
            ocrText: 'text',
          ),
        ]),
    ];
    await tester.runAsync(() async {
      await DocumentRepository.instance.initialize();
      for (final d in docs) {
        await DocumentRepository.instance.saveDocument(d);
      }
    });

    await tester.pumpWidget(const ClearScanApp());
    await tester.pump();

    await tester.longPress(find.text('First scan'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Scan'), findsNothing, reason: 'the scan button hides while selecting');

    await tester.tap(find.text('Second scan'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete selected'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 documents?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    // Deleting files is real IO: let real time pass until selection mode ends.
    for (int i = 0; i < 40 && find.text('2 selected').evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(DocumentRepository.instance.documents.map((d) => d.title), ['Kept scan']);
    expect(File(docs[0].pages.single.rawImagePath).existsSync(), isFalse);
    expect(find.text('Scan'), findsOneWidget, reason: 'selection mode ends after deleting');
  });
}
