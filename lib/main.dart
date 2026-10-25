import 'package:flutter/material.dart';
import 'core/storage/app_settings.dart';
import 'core/storage/document_repository.dart';
import 'ui/app_theme.dart';
import 'ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([DocumentRepository.instance.initialize(), AppSettings.load()]);
  runApp(const ClearScanApp());
}

class ClearScanApp extends StatelessWidget {
  const ClearScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (context, currentMode, _) => MaterialApp(
        title: 'ClearScan',
        debugShowCheckedModeBanner: false,
        themeMode: currentMode,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const HomeScreen(),
      ),
    );
  }
}
