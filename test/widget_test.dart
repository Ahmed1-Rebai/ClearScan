import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cam_scan/main.dart';

void main() {
  testWidgets('App smoke test: loads ClearScan HomeScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const ClearScanApp());
    await tester.pump();

    // Verify ClearScan app title is displayed in the AppBar
    expect(find.text('ClearScan'), findsOneWidget);
    // Verify "Scan Document" FloatingActionButton is present
    expect(find.text('Scan Document'), findsOneWidget);
  });

  testWidgets('Theme toggle switches between Dark and Light mode', (WidgetTester tester) async {
    themeNotifier.value = ThemeMode.dark;
    await tester.pumpWidget(const ClearScanApp());
    await tester.pump();

    // Verify initial dark mode tooltip
    expect(find.byTooltip('Switch to Light Mode'), findsOneWidget);

    // Tap theme toggle button
    await tester.tap(find.byTooltip('Switch to Light Mode'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify switched to light mode
    expect(themeNotifier.value, equals(ThemeMode.light));
    expect(find.byTooltip('Switch to Dark Mode'), findsOneWidget);
  });
}
