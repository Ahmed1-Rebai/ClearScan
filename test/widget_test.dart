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
}
