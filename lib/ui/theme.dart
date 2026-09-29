// The app's look: colour themes, the Material theme, and small time-formatting helpers.
//
// Since 0.1.24 the colours come from a theme the user picks in Settings › Appearance: Default
// (the original dark look with the warm orange accent), Midnight, Forest, or their own
// (a highlight and a background colour; the rest is worked out so it stays readable).
// [AppColors] always returns the colours of the current theme; HomeTunesApp (main.dart) sets
// [AppColors.current] from the saved setting, rebuilds the Material theme with [buildTheme] and
// redraws every screen when it changes. So widgets must read AppColors at build time (never in
// a `const` or a `static final`). The duration formatters live here because nearly every screen
// that shows a time imports this file anyway.
import 'package:flutter/material.dart';

/// One colour theme.
@immutable
class AppPalette {
  /// Saved in settings.json: 'default', 'midnight', 'forest' or 'custom'.
  final String id;

  /// Shown in Settings › Appearance.
  final String name;

  /// Highlights, the selected tab, switches.
  final Color accent;

  /// Page background.
  final Color bg;

  /// Slightly lighter panels: bottom bars, cards.
  final Color surface;

  /// Raised panels one step lighter again (dialogs, hovered items).
  final Color surfaceHigh;

  /// Grey for secondary text and icons.
  final Color textDim;

  /// The unfilled part of the seek and volume sliders.
  final Color track;

  const AppPalette({
    required this.id,
    required this.name,
    required this.accent,
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.textDim,
    required this.track,
  });

  /// A theme made from just a highlight and a background ("Your own"). The background is kept
  /// dark and the highlight bright enough to see, because text and icons are white; panels and
  /// the grey text are mixed from the background towards white.
  factory AppPalette.fromColours({
    String id = 'custom',
    String name = 'Your own',
    required Color accent,
    required Color background,
  }) {
    final bg = keepDark(background);
    Color mix(double t) => Color.lerp(bg, Colors.white, t)!;
    return AppPalette(
      id: id,
      name: name,
      accent: keepVisible(accent),
      bg: bg,
      surface: mix(0.04),
      surfaceHigh: mix(0.09),
      textDim: mix(0.62),
      track: mix(0.24),
    );
  }

  /// Black or white, whichever reads better on the accent (text on filled buttons).
  Color get onAccent => accent.computeLuminance() > 0.4 ? Colors.black : Colors.white;

  /// Backgrounds darker than this (HSL lightness) keep white text readable.
  static const maxBackgroundLightness = 0.2;

  /// Highlights within this lightness range show up against a dark background.
  static const minAccentLightness = 0.45, maxAccentLightness = 0.8;

  static Color keepDark(Color c) {
    final h = HSLColor.fromColor(c);
    return h.lightness <= maxBackgroundLightness ? c.withAlpha(255) : h.withLightness(maxBackgroundLightness).toColor();
  }

  static Color keepVisible(Color c) {
    final h = HSLColor.fromColor(c);
    final l = h.lightness.clamp(minAccentLightness, maxAccentLightness);
    return l == h.lightness ? c.withAlpha(255) : h.withLightness(l).toColor();
  }

  @override
  bool operator ==(Object other) =>
      other is AppPalette &&
      other.id == id &&
      other.accent == accent &&
      other.bg == bg &&
      other.surface == surface &&
      other.surfaceHigh == surfaceHigh &&
      other.textDim == textDim &&
      other.track == track;

  @override
  int get hashCode => Object.hash(id, accent, bg, surface, surfaceHigh, textDim, track);
}

/// The original HomeTunes look.
const defaultPalette = AppPalette(
  id: 'default',
  name: 'Default',
  accent: Color(0xFFFF7A59),
  bg: Color(0xFF101114),
  surface: Color(0xFF1A1C21),
  surfaceHigh: Color(0xFF24272E),
  textDim: Color(0xFFA3A8B3),
  track: Color(0xFF4A4E57),
);

/// The ready-made themes, in the order they're offered. "Your own" comes after these.
const builtInPalettes = <AppPalette>[
  defaultPalette,
  AppPalette(
    id: 'midnight',
    name: 'Midnight',
    accent: Color(0xFF5AB4FF),
    bg: Color(0xFF0D1321),
    surface: Color(0xFF161E2E),
    surfaceHigh: Color(0xFF1F2940),
    textDim: Color(0xFF9FAECB),
    track: Color(0xFF3A4661),
  ),
  AppPalette(
    id: 'forest',
    name: 'Forest',
    accent: Color(0xFF4CC38A),
    bg: Color(0xFF0F1512),
    surface: Color(0xFF18201B),
    surfaceHigh: Color(0xFF222C26),
    textDim: Color(0xFF9FB3A7),
    track: Color(0xFF3F4D45),
  ),
];

/// The theme for a saved choice ([id] from settings.json); unknown ids fall back to Default.
AppPalette paletteFor(String id, {required Color customAccent, required Color customBackground}) {
  if (id == 'custom') return AppPalette.fromColours(accent: customAccent, background: customBackground);
  for (final p in builtInPalettes) {
    if (p.id == id) return p;
  }
  return defaultPalette;
}

/// "#RRGGBB", as saved in settings.json.
String colourToHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Reads "#RRGGBB" (or "RRGGBB"); null if it isn't one.
Color? colourFromHex(Object? s) {
  if (s is! String) return null;
  final t = s.trim().replaceFirst('#', '');
  if (t.length != 6) return null;
  final v = int.tryParse(t, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// The current theme's colours, for the spots the Material theme doesn't cover.
class AppColors {
  /// Set by HomeTunesApp from the saved choice.
  static AppPalette current = defaultPalette;

  static Color get accent => current.accent;
  static Color get bg => current.bg;
  static Color get surface => current.surface;
  static Color get surfaceHigh => current.surfaceHigh;
  static Color get textDim => current.textDim;
  static Color get track => current.track;
}

/// Builds the Material 3 theme from [p] (the current theme by default).
ThemeData buildTheme([AppPalette? p]) {
  final c = p ?? AppColors.current;
  // Start from a generated scheme, then pin the colours we care about so they match exactly.
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: c.accent,
    onPrimary: c.onAccent,
    surface: c.bg,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surfaceHigh,
    onSurfaceVariant: c.textDim,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    appBarTheme: AppBarTheme(backgroundColor: c.bg, surfaceTintColor: Colors.transparent),
    // Phone tab bar: no pill behind the selected icon (the filled icon is enough).
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      indicatorColor: Colors.transparent,
      height: 64,
    ),
    // Thin white sliders with small thumbs, used for the seek bar and volume.
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      activeTrackColor: Colors.white,
      inactiveTrackColor: c.track,
      thumbColor: Colors.white,
    ),
    listTileTheme: ListTileThemeData(iconColor: c.textDim),
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
