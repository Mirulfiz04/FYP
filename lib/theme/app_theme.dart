import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MEDS brand accent — the same green used across the app.
const Color medsGreen = Color(0xFF00DC64);

/// Dark theme — preserves the app's original look.
ThemeData buildDarkTheme() {
  const surface = Color(0xFF12121F);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0A0A19),
    dividerColor: Colors.white10,
    colorScheme: const ColorScheme.dark(
      primary: medsGreen,
      surface: surface,
      onSurface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: medsGreen,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFF1A1A2E),
      border: OutlineInputBorder(borderSide: BorderSide.none),
    ),
  );
}

/// Light theme — mirrors the dark layout with light surfaces.
ThemeData buildLightTheme() {
  const primary = Color(0xFF00A84B); // slightly darker green for contrast on white
  const surface = Colors.white;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF2F3F7),
    dividerColor: Colors.black12,
    colorScheme: const ColorScheme.light(
      primary: primary,
      surface: surface,
      onSurface: Color(0xFF1A1A2E),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: Color(0xFF1A1A2E),
      elevation: 0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: primary,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFEDEFF3),
      border: const OutlineInputBorder(borderSide: BorderSide.none),
      hintStyle: TextStyle(color: Colors.grey.shade600),
    ),
  );
}

/// Holds the selected [ThemeMode] and persists it across launches.
class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';
  ThemeMode _mode = ThemeMode.dark;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = switch (prefs.getString(_key)) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark, // default keeps the original dark look
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  Future<void> toggle() =>
      setMode(isDark ? ThemeMode.light : ThemeMode.dark);
}

/// Global instance used by the app shell and settings screen.
final themeController = ThemeController();
