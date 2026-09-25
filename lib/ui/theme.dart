// The app's look: colours, the Material theme, and small time-formatting helpers.
//
// HomeTunes has one dark theme only (Spotify-like). main.dart passes buildTheme() to MaterialApp,
// and widgets use AppColors directly for the few spots the theme doesn't cover. The duration
// formatters live here because nearly every screen that shows a time imports this file anyway.
import 'package:flutter/material.dart';

/// Dark theme with a warm accent.
class AppColors {
  /// The warm orange used for highlights, the play button and selected items.
  static const accent = Color(0xFFFF7A59);
  /// Page background (near black).
  static const bg = Color(0xFF101114);
  /// Slightly lighter panels: bottom bars, cards.
  static const surface = Color(0xFF1A1C21);
  /// Raised panels one step lighter again (dialogs, hovered items).
  static const surfaceHigh = Color(0xFF24272E);
  /// Grey for secondary text and icons.
  static const textDim = Color(0xFFA3A8B3);
}

/// Builds the Material 3 theme from [AppColors].
ThemeData buildTheme() {
  // Start from a generated scheme, then pin the colours we care about so they match exactly.
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
    // Phone tab bar: no pill behind the selected icon (the filled icon is enough).
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: Colors.transparent,
      height: 64,
    ),
    // Thin white sliders with small thumbs, used for the seek bar and volume.
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

/// "3:07", or "–:––" when the length isn't known yet.
String formatDuration(Duration d) {
  if (d <= Duration.zero) return '–:––';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  // Minutes only get a leading zero when there's an hour in front ("1:03:07" vs "3:07").
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Playback position: always a time, starting at "0:00".
String formatElapsed(Duration d) => d <= Duration.zero ? '0:00' : formatDuration(d);

/// "1 hr 12 min" style.
String formatLong(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '$h hr $m min';
  return '$m min';
}
