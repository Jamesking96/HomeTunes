// The app's look: colour themes, text size, corner roundness, the Material theme, and small
// time-formatting helpers.
//
// Since 0.1.24 the colours come from a theme the user picks in Settings › Appearance: Default
// (the original dark look with the warm orange accent), Midnight, Forest, "Your own" (a highlight
// and a background colour; the rest is worked out so it stays readable) and, since 0.1.25, any
// number of saved themes where every colour is chosen (light themes included) in
// Settings › Appearance › Advanced.
// [AppColors] always returns the colours of the current theme and [AppShape] the current corner
// roundness; HomeTunesApp (main.dart) sets them from the saved settings, rebuilds the Material
// theme with [buildTheme] and redraws every screen when they change. So widgets must read them
// at build time (never in a `const` or a `static final`). The duration formatters live here
// because nearly every screen that shows a time imports this file anyway.
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One colour theme.
@immutable
class AppPalette {
  /// 'default', 'midnight', 'forest', 'custom' ("Your own") or `saved:…` (Advanced).
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

  /// Main text and icons.
  final Color text;

  /// Grey for secondary text and icons.
  final Color textDim;

  /// The unfilled part of the seek and volume sliders.
  final Color track;

  /// The big round play button.
  final Color playButton;

  const AppPalette({
    required this.id,
    required this.name,
    required this.accent,
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    this.text = Colors.white,
    required this.textDim,
    required this.track,
    this.playButton = Colors.white,
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

  /// A light background (dark text) rather than a dark one.
  bool get isLight => bg.computeLuminance() > 0.35;

  /// Black or white, whichever reads better on [c].
  static Color onColour(Color c) => c.computeLuminance() > 0.4 ? Colors.black : Colors.white;

  /// Text on filled highlight buttons.
  Color get onAccent => onColour(accent);

  /// The play symbol on the play button.
  Color get onPlay => onColour(playButton);

  /// The line between the sidebar and the pages (black on dark themes, as before).
  Color get divider => isLight ? Color.lerp(bg, text, 0.15)! : Colors.black;

  /// Main text faded to [alpha] (0–1), e.g. lyrics that have been sung.
  Color faded(double alpha) => text.withValues(alpha: alpha);

  /// The same theme with another id and name (Duplicate, New theme).
  AppPalette copyWith({
    String? id,
    String? name,
    Color? accent,
    Color? bg,
    Color? surface,
    Color? surfaceHigh,
    Color? text,
    Color? textDim,
    Color? track,
    Color? playButton,
  }) =>
      AppPalette(
        id: id ?? this.id,
        name: name ?? this.name,
        accent: accent ?? this.accent,
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceHigh: surfaceHigh ?? this.surfaceHigh,
        text: text ?? this.text,
        textDim: textDim ?? this.textDim,
        track: track ?? this.track,
        playButton: playButton ?? this.playButton,
      );

  /// The colours as saved in settings.json ("#RRGGBB" each), for saved themes.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        for (final e in colourSlots.entries) e.key: colourToHex(e.value(this)),
      };

  /// A saved theme read back; null if it's missing its id, name or any colour.
  static AppPalette? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], name = json['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    final c = <String, Color>{};
    for (final k in colourSlots.keys) {
      final v = colourFromHex(json[k]);
      if (v == null) return null;
      c[k] = v;
    }
    return AppPalette(
      id: id,
      name: name.trim().isEmpty ? 'My theme' : name.trim(),
      accent: c['accent']!,
      bg: c['background']!,
      surface: c['panels']!,
      surfaceHigh: c['raisedPanels']!,
      text: c['text']!,
      textDim: c['greyText']!,
      track: c['sliderTrack']!,
      playButton: c['playButton']!,
    );
  }

  /// Each colour a saved theme stores, by its saved name.
  static final colourSlots = <String, Color Function(AppPalette)>{
    'background': (p) => p.bg,
    'panels': (p) => p.surface,
    'raisedPanels': (p) => p.surfaceHigh,
    'text': (p) => p.text,
    'greyText': (p) => p.textDim,
    'accent': (p) => p.accent,
    'sliderTrack': (p) => p.track,
    'playButton': (p) => p.playButton,
  };

  /// Plain-words warnings about colours that are hard to tell apart (empty when all is well).
  /// Uses the usual contrast rule: 4.5 for main text, 3 for grey text, highlights and buttons.
  List<String> readabilityProblems() => [
        if (contrast(text, bg) < 4.5) 'Text is hard to read on the background.',
        if (contrast(text, surface) < 4.5) 'Text is hard to read on panels.',
        if (contrast(text, surfaceHigh) < 3) 'Text is hard to read on raised panels.',
        if (contrast(textDim, bg) < 3) 'Grey text is hard to read on the background.',
        if (contrast(accent, bg) < 3) 'The highlight colour is hard to see on the background.',
        if (contrast(playButton, surface) < 3) 'The play button is hard to see on the player bar.',
      ];

  /// Backgrounds darker than this (HSL lightness) keep white text readable ("Your own").
  static const maxBackgroundLightness = 0.2;

  /// Highlights within this lightness range show up against a dark background ("Your own").
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
      other.name == name &&
      other.accent == accent &&
      other.bg == bg &&
      other.surface == surface &&
      other.surfaceHigh == surfaceHigh &&
      other.text == text &&
      other.textDim == textDim &&
      other.track == track &&
      other.playButton == playButton;

  @override
  int get hashCode => Object.hash(id, name, accent, bg, surface, surfaceHigh, text, textDim, track, playButton);
}

/// How far apart two colours are to the eye: 1 (same) to 21 (black on white).
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
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
/// [saved] are the user's saved themes (Advanced).
AppPalette paletteFor(String id,
    {required Color customAccent, required Color customBackground, List<AppPalette> saved = const []}) {
  if (id == 'custom') return AppPalette.fromColours(accent: customAccent, background: customBackground);
  for (final p in [...builtInPalettes, ...saved]) {
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

/// A colour code typed or pasted by the user (0.1.29): "#FF7A59", "ff7a59", the short "#F75",
/// or "0xFF7A59", with spaces or quotes around it ignored. Null if it isn't one.
Color? parseColourCode(String input) {
  var t = input.trim().replaceAll(RegExp('^["\']+|["\';,]+\$'), '').trim();
  if (t.startsWith('#')) {
    t = t.substring(1);
  } else if (t.toLowerCase().startsWith('0x')) {
    t = t.substring(2);
  }
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(t)) return null;
  if (t.length == 3) t = [for (final ch in t.split('')) '$ch$ch'].join();
  if (t.length != 6) return null;
  return Color(0xFF000000 | int.parse(t, radix: 16));
}

/// The current theme's colours, for the spots the Material theme doesn't cover.
class AppColors {
  /// Set by HomeTunesApp from the saved choice.
  static AppPalette current = defaultPalette;

  static Color get accent => current.accent;
  static Color get bg => current.bg;
  static Color get surface => current.surface;
  static Color get surfaceHigh => current.surfaceHigh;
  static Color get text => current.text;
  static Color get textDim => current.textDim;
  static Color get track => current.track;
  static Color get playButton => current.playButton;
  static Color get onPlay => current.onPlay;
  static Color get divider => current.divider;
  static Color faded(double alpha) => current.faded(alpha);
}

/// Text size choices (Settings › Appearance › Advanced), as a multiple of the system size.
const textSizes = <(String, double)>[('Smaller', 0.9), ('Default', 1.0), ('Larger', 1.15), ('Largest', 1.3)];

/// Corner roundness choices: how rounded covers, cards, buttons and dialogs are.
const roundnessChoices = <(String, double)>[('Square', 0.0), ('Slight', 0.5), ('Default', 1.0), ('Extra round', 1.6)];

/// The current corner roundness. Rounded corners in the app go through [circular] / [radius].
class AppShape {
  /// Set by HomeTunesApp: 0 = square corners, 1 = as designed.
  static double scale = 1.0;

  static double r(double designed) => designed * scale;
  static BorderRadius circular(double designed) => BorderRadius.circular(designed * scale);
  static Radius radius(double designed) => Radius.circular(designed * scale);
}

/// Builds the Material 3 theme from [p] (the current theme by default) and the corner
/// roundness [corners] (the current one by default).
ThemeData buildTheme([AppPalette? p, double? corners]) {
  final c = p ?? AppColors.current;
  final s = corners ?? AppShape.scale;
  RoundedRectangleBorder round(double r) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(r * s));
  final brightness = c.isLight ? Brightness.light : Brightness.dark;
  // Themes where every colour was chosen (Advanced), and light ones, pin all of Material's
  // colours to theirs. The ready-made dark themes and "Your own" keep Material's generated
  // in-between shades, so they look exactly as they did before 0.1.25.
  final pinAll = c.id.startsWith('saved:') || c.isLight;
  // Start from a generated scheme, then pin the colours we care about so they match exactly.
  var scheme = ColorScheme.fromSeed(seedColor: c.accent, brightness: brightness).copyWith(
    primary: c.accent,
    onPrimary: c.onAccent,
    surface: c.bg,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surfaceHigh,
    onSurfaceVariant: c.textDim,
  );
  if (pinAll) {
    scheme = scheme.copyWith(
      onSurface: c.text,
      surfaceContainerLowest: c.bg,
      surfaceContainerLow: c.surface,
      surfaceContainerHighest: c.surfaceHigh,
      outline: c.textDim,
      outlineVariant: c.track,
    );
  }
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    textTheme: pinAll ? base.textTheme.apply(bodyColor: c.text, displayColor: c.text) : null,
    iconTheme: pinAll ? IconThemeData(color: c.text) : null,
    dividerColor: pinAll ? c.divider : null,
    appBarTheme: AppBarTheme(
        backgroundColor: c.bg, foregroundColor: pinAll ? c.text : null, surfaceTintColor: Colors.transparent),
    // Phone tab bar: no pill behind the selected icon (the filled icon is enough).
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      indicatorColor: Colors.transparent,
      height: 64,
    ),
    // Thin sliders in the text colour with small thumbs, used for the seek bar and volume.
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      activeTrackColor: c.text,
      inactiveTrackColor: c.track,
      thumbColor: c.text,
    ),
    listTileTheme: ListTileThemeData(iconColor: c.textDim, textColor: pinAll ? c.text : null),
    // Corner roundness (Settings › Appearance › Advanced). The numbers are Material's own
    // defaults, so "Default" roundness looks as it always has.
    cardTheme: CardThemeData(shape: round(12)),
    dialogTheme: DialogThemeData(shape: round(28)),
    popupMenuTheme: PopupMenuThemeData(shape: round(4)),
    bottomSheetTheme: BottomSheetThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28 * s))),
    ),
    chipTheme: ChipThemeData(shape: round(8)),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: round(20))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: round(20))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: round(20))),
    menuTheme: MenuThemeData(style: MenuStyle(shape: WidgetStatePropertyAll(round(4)))),
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
