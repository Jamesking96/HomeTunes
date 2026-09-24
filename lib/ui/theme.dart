import 'package:flutter/material.dart';

/// Dark theme with a warm accent.
class AppColors {
  static const accent = Color(0xFFFF7A59);
  static const bg = Color(0xFF101114);
  static const surface = Color(0xFF1A1C21);
  static const surfaceHigh = Color(0xFF24272E);
  static const textDim = Color(0xFFA3A8B3);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: Colors.black,
    surface: AppColors.bg,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surfaceHigh,
    onSurfaceVariant: AppColors.textDim,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg, surfaceTintColor: Colors.transparent),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: Colors.transparent,
      height: 64,
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      activeTrackColor: Colors.white,
      inactiveTrackColor: Color(0xFF4A4E57),
      thumbColor: Colors.white,
    ),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.textDim),
  );
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// "1 hr 12 min" style.
String formatLong(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '$h hr $m min';
  return '$m min';
}
