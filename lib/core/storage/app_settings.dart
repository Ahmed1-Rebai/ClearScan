import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Small persisted user preferences (stored next to the documents index).
class AppSettings {
  /// Light until the user picks another option (System default or Dark) in the theme menu.
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);

  static Future<File> _file() async => File(p.join((await getApplicationDocumentsDirectory()).path, 'settings.json'));

  static Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      themeMode.value = ThemeMode.values.firstWhere((m) => m.name == json['themeMode'], orElse: () => ThemeMode.light);
    } catch (e) {
      debugPrint('AppSettings: could not load settings: $e');
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    try {
      await (await _file()).writeAsString(jsonEncode({'themeMode': mode.name}));
    } catch (e) {
      debugPrint('AppSettings: could not save settings: $e');
    }
  }
}
