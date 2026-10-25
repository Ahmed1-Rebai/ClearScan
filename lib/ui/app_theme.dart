import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ClearScan's light and dark themes (deep navy and neon cyan branding).
class AppTheme {
  static ThemeData get light => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme.light(
          primary: Color(0xFF0066FF),
          secondary: Color(0xFF0284C7),
          tertiary: Color(0xFF7C3AED),
          surface: Color(0xFFFFFFFF),
          surfaceContainerHighest: Color(0xFFF1F5F9),
          onPrimary: Color(0xFFFFFFFF),
          onSurface: Color(0xFF0F172A),
          outlineVariant: Color(0xFFE2E8F0),
        ),
        scaffold: const Color(0xFFF8FAFC),
        card: Colors.white,
        border: const Color(0xFFE2E8F0),
        fabForeground: Colors.white,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF60A5FA),
          tertiary: Color(0xFFC084FC),
          surface: Color(0xFF131B2E),
          surfaceContainerHighest: Color(0xFF1E293B),
          onPrimary: Color(0xFF050C1A),
          onSurface: Color(0xFFF8FAFC),
          outlineVariant: Color(0xFF1E293B),
        ),
        scaffold: const Color(0xFF0B0F19),
        card: const Color(0xFF131B2E),
        border: const Color(0xFF1E293B),
        fabForeground: const Color(0xFF050C1A),
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color scaffold,
    required Color card,
    required Color border,
    required Color fabForeground,
  }) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: fabForeground,
        elevation: dark ? 4 : 3,
      ),
    );
  }
}
