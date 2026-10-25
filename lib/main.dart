import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/ai/gemma_local_service.dart';
import 'core/storage/document_repository.dart';
import 'ui/screens/home_screen.dart';

/// Global notifier for switching between Light and Dark theme modes.
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B0F19),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize local offline services
  await DocumentRepository.instance.initialize();
  await GemmaLocalService.instance.initialize();

  runApp(const ClearScanApp());
}

class ClearScanApp extends StatelessWidget {
  const ClearScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'ClearScan — Local AI Scanner',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          // Light Mode Theme
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0066FF),
              secondary: Color(0xFF0284C7),
              tertiary: Color(0xFF0EA5E9),
              surface: Color(0xFFFFFFFF),
              surfaceContainerHighest: Color(0xFFF1F5F9),
              onPrimary: Color(0xFFFFFFFF),
              onSurface: Color(0xFF0F172A),
              outlineVariant: Color(0xFFE2E8F0),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF8FAFC),
              foregroundColor: Color(0xFF0F172A),
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: false,
              titleTextStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
                color: Color(0xFF0F172A),
              ),
            ),
            cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF0066FF), width: 1.5),
              ),
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: Color(0xFF0066FF),
              foregroundColor: Colors.white,
              elevation: 3,
            ),
          ),
          // Dark Mode Theme
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0B0F19),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00E5FF),
              secondary: Color(0xFF0066FF),
              tertiary: Color(0xFF38BDF8),
              surface: Color(0xFF131B2E),
              surfaceContainerHighest: Color(0xFF1E293B),
              onPrimary: Color(0xFF050C1A),
              onSurface: Color(0xFFF8FAFC),
              outlineVariant: Color(0xFF1E293B),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0B0F19),
              foregroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: false,
              titleTextStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
                color: Colors.white,
              ),
            ),
            cardTheme: CardThemeData(
              color: const Color(0xFF131B2E),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF1E293B), width: 1),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF131B2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF1E293B)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF1E293B)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
              ),
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: Color(0xFF00E5FF),
              foregroundColor: Color(0xFF050C1A),
              elevation: 4,
            ),
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}
