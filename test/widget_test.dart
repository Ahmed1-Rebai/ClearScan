import 'package:flutter_test/flutter_test.dart';
import 'package:cam_scan/main.dart';

void main() {
  testWidgets('App smoke test: loads HomeScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const CamScanApp());
    await tester.pump();

    // Verify app title is displayed in the AppBar
    expect(find.text('CamScanner Local AI'), findsOneWidget);
    // Verify "New Scan" FloatingActionButton is present
    expect(find.text('New Scan'), findsOneWidget);
  });
}
