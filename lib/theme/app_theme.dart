import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MEDS brand accent — the hero green used across the app.
const Color medsGreen = Color(0xFF00DC64);

/// The friendly, vibrant MEDS palette. Use these for cards, icons, accents and
/// emotion colours so the whole app stays consistent and colourful.
abstract final class MedsColors {
  static const green = medsGreen;
  static const greenDark = Color(0xFF00A84B); // readable green on white
  static const blue = Color(0xFF2E9BF0);
  static const purple = Color(0xFF8B5CF6);
  static const amber = Color(0xFFFFA62B);
  static const coral = Color(0xFFFF6B6B);
  static const pink = Color(0xFFEC4899);
  static const teal = Color(0xFF14B8A6);
  static const red = Color(0xFFFF4D5E);

  // Light surfaces
  static const lightBg = Color(0xFFF4F6FB);
  static const lightText = Color(0xFF1B2333);

  // Dark surfaces
  static const darkBg = Color(0xFF0A0A19);
  static const darkSurface = Color(0xFF15162A);

  // Secondary / muted text that reads well on both themes.
  static const muted = Color(0xFF7A8699);

  /// A cheerful gradient for hero headers and the primary action.
  static const heroGradient = LinearGradient(
    colors: [Color(0xFF00DC64), Color(0xFF00B488)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// A pleasing per-emotion colour, consistent across every screen.
  static Color emotion(String e) => switch (e) {
        'Happy' => green,
        'Sad' => blue,
        'Angry' => red,
        'Fear' => purple,
        'Surprise' => teal,
        'Disgust' => amber,
        'Neutral' => const Color(0xFF9AA6B8),
        _ => const Color(0xFF9AA6B8),
      };

  /// A friendly emoji for each emotion.
  static String emoji(String e) => switch (e) {
        'Happy' => '😊',
        'Sad' => '😢',
        'Angry' => '😠',
        'Fear' => '😨',
        'Surprise' => '😲',
        'Disgust' => '🤢',
        'Neutral' => '😐',
        _ => '🙂',
      };

  /// Colour for an AI stress level badge.
  static Color stress(String level) => switch (level) {
        'Low' => green,
        'Moderate' => blue,
        'Elevated' => amber,
        'High' => red,
        _ => muted,
      };
}

/// Accent colour for the authentication screens (login & register).
/// Matches the purple mockup. 👉 Change to `MedsColors.greenDark` to use the
/// app's brand green across both auth screens.
const Color authAccent = MedsColors.purple;

/// Soft, theme-aware card shadow. Subtle on light, near-invisible on dark.
List<BoxShadow> softShadow(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return [
    BoxShadow(
      color: dark
          ? Colors.black.withValues(alpha: 0.30)
          : const Color(0xFF1B2333).withValues(alpha: 0.07),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

// Shared component shapes so light and dark stay consistent.
final _btnShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

OutlineInputBorder _inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );

InputDecorationTheme _inputTheme(Color fill, Color focus) => InputDecorationTheme(
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: _inputBorder(Colors.transparent),
      enabledBorder: _inputBorder(Colors.transparent),
      focusedBorder: _inputBorder(focus, 1.6),
      errorBorder: _inputBorder(MedsColors.red),
      focusedErrorBorder: _inputBorder(MedsColors.red, 1.6),
    );

/// Light theme — the bright, friendly default.
ThemeData buildLightTheme() {
  const primary = MedsColors.greenDark;
  const surface = Colors.white;
  final scheme = const ColorScheme.light(
    primary: primary,
    onPrimary: Colors.white,
    secondary: MedsColors.blue,
    onSecondary: Colors.white,
    surface: surface,
    onSurface: MedsColors.lightText,
    error: MedsColors.red,
  );
  return _base(scheme, MedsColors.lightBg,
      inputFill: const Color(0xFFEDF1F7), focus: primary, dividerColor: const Color(0x141B2333));
}

/// Dark theme — the original dark look, refreshed with the same vibrant accents.
ThemeData buildDarkTheme() {
  const surface = MedsColors.darkSurface;
  final scheme = const ColorScheme.dark(
    primary: medsGreen,
    onPrimary: Colors.black,
    secondary: MedsColors.blue,
    onSecondary: Colors.white,
    surface: surface,
    onSurface: Colors.white,
    error: MedsColors.red,
  );
  return _base(scheme, MedsColors.darkBg,
      inputFill: const Color(0xFF1E2036), focus: medsGreen, dividerColor: Colors.white12);
}

/// Builds a complete, polished theme from a colour scheme so light and dark
/// share the same rounded, colourful component styling.
ThemeData _base(
  ColorScheme scheme,
  Color background, {
  required Color inputFill,
  required Color focus,
  required Color dividerColor,
}) {
  return ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    dividerColor: dividerColor,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: _btnShape,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: _btnShape,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: _btnShape,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: _inputTheme(inputFill, focus),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide.none,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: 0.16),
      elevation: 0,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : MedsColors.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : MedsColors.muted,
        ),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: scheme.surface,
      selectedItemColor: scheme.primary,
      unselectedItemColor: MedsColors.muted,
      type: BottomNavigationBarType.fixed,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}

/// Holds the selected [ThemeMode] and persists it across launches.
class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';
  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = switch (prefs.getString(_key)) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light, // bright & friendly by default
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

  Future<void> toggle() => setMode(isDark ? ThemeMode.light : ThemeMode.dark);
}

/// Global instance used by the app shell and settings screen.
final themeController = ThemeController();
