// Settings › Appearance (0.1.24): pick the colour theme — Default, Midnight, Forest or "Your own"
// (a highlight and a background colour chosen with a simple picker).
//
// The choice is saved in settings.json by LibraryModel.setTheme (so it's in backups).
// HomeTunesApp (main.dart) turns it into a palette with [paletteOfSettings], and
// [RedrawOnThemeChange] redraws every screen when it changes, because many widgets read
// AppColors directly rather than through the Material theme.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/library_model.dart';
import '../../theme.dart';
import 'settings_widgets.dart';

/// The theme the saved settings ask for.
AppPalette paletteOfSettings(LibraryModel lib) => paletteFor(
      lib.themeId,
      customAccent: colourFromHex(lib.customAccent) ?? defaultPalette.accent,
      customBackground: colourFromHex(lib.customBackground) ?? defaultPalette.bg,
    );

/// Redraws the whole app after the theme changes. Widgets that read AppColors (rather than
/// Theme.of) wouldn't otherwise notice, so every element is marked to build again once.
class RedrawOnThemeChange extends StatefulWidget {
  final AppPalette palette;
  final Widget child;
  const RedrawOnThemeChange({super.key, required this.palette, required this.child});

  @override
  State<RedrawOnThemeChange> createState() => _RedrawOnThemeChangeState();
}

class _RedrawOnThemeChangeState extends State<RedrawOnThemeChange> {
  @override
  void didUpdateWidget(RedrawOnThemeChange old) {
    super.didUpdateWidget(old);
    if (old.palette == widget.palette) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void mark(Element e) {
        e.markNeedsBuild();
        e.visitChildren(mark);
      }

      (context as Element).visitChildren(mark);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Settings › Appearance.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final accent = colourFromHex(lib.customAccent) ?? defaultPalette.accent;
    final background = colourFromHex(lib.customBackground) ?? defaultPalette.bg;
    final custom = AppPalette.fromColours(accent: accent, background: background);
    final chosen = lib.themeId == 'custom' ? 'custom' : paletteOfSettings(lib).id;

    return SettingsPageList(children: [
      const SettingsGroupTitle('Colour theme'),
      SettingTarget(
        'theme',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            for (final p in [...builtInPalettes, custom])
              ThemeCard(
                palette: p,
                selected: p.id == chosen,
                onTap: () => lib.setTheme(id: p.id),
              ),
          ]),
        ),
      ),
      SettingTarget(
        'theme-custom',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SettingsGroupTitle('Your own colours'),
          ListTile(
            leading: _Swatch(colour: custom.accent),
            title: const Text('Highlight colour'),
            subtitle: const Text('Buttons, the selected tab, switches and progress'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final c = await showColourPicker(context, title: 'Highlight colour', initial: custom.accent);
              if (c != null) await lib.setTheme(id: 'custom', accent: colourToHex(c));
            },
          ),
          ListTile(
            leading: _Swatch(colour: custom.bg),
            title: const Text('Background colour'),
            subtitle: const Text('Pages and panels (panels are made a little lighter automatically)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final c = await showColourPicker(context,
                  title: 'Background colour', initial: custom.bg, background: true);
              if (c != null) await lib.setTheme(id: 'custom', background: colourToHex(c));
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Choosing a colour here switches to "Your own". Backgrounds stay dark and highlights stay '
              'bright, so text is always easy to read.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// A small preview of a theme: a page with a panel along the bottom, two lines of text and a
/// play button in its highlight colour. Tap to use it.
class ThemeCard extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;
  const ThemeCard({super.key, required this.palette, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final ring = selected ? AppColors.accent : Colors.white24;
    return Semantics(
      button: true,
      selected: selected,
      label: '${p.name} theme',
      child: InkWell(
        key: ValueKey('theme:${p.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 150,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: p.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ring, width: selected ? 2.5 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: 70, height: 8, decoration: _bar(Colors.white)),
                      const SizedBox(height: 6),
                      Container(width: 48, height: 6, decoration: _bar(p.textDim)),
                    ]),
                  ),
                ),
                Container(
                  height: 34,
                  color: p.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(children: [
                    Container(width: 18, height: 18, decoration: BoxDecoration(color: p.surfaceHigh, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 8),
                    Expanded(child: Container(height: 3, decoration: _bar(p.track))),
                    const SizedBox(width: 8),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                      child: Icon(Icons.play_arrow_rounded, size: 14, color: p.onAccent),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (selected) Icon(Icons.check_circle, size: 18, color: AppColors.accent),
            ]),
          ]),
        ),
      ),
    );
  }

  static BoxDecoration _bar(Color c) => BoxDecoration(color: c, borderRadius: BorderRadius.circular(4));
}

class _Swatch extends StatelessWidget {
  final Color colour;
  const _Swatch({required this.colour});

  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: colour, shape: BoxShape.circle, border: Border.all(color: Colors.white38)),
      );
}

/// Suggested highlight colours.
const accentSuggestions = <Color>[
  Color(0xFFFF7A59), Color(0xFFFF5C8A), Color(0xFFE35BD8), Color(0xFFA77BFF), Color(0xFF6F8BFF), Color(0xFF5AB4FF),
  Color(0xFF3CCFCF), Color(0xFF4CC38A), Color(0xFF9BD14B), Color(0xFFF2C84B), Color(0xFFFFA23A), Color(0xFFE5E5E5),
];

/// Suggested backgrounds (all dark).
const backgroundSuggestions = <Color>[
  Color(0xFF101114), Color(0xFF000000), Color(0xFF0D1321), Color(0xFF0F1512), Color(0xFF1A1020),
  Color(0xFF1E1412), Color(0xFF121A1F), Color(0xFF191919),
];

/// Lets the user pick a colour from suggestions or with shade / strength / brightness sliders.
/// [background] keeps it dark; otherwise it's kept bright enough to be a highlight. Returns the
/// colour, or null if cancelled.
Future<Color?> showColourPicker(BuildContext context,
        {required String title, required Color initial, bool background = false}) =>
    showDialog<Color>(
      context: context,
      builder: (_) => _ColourPicker(title: title, initial: initial, background: background),
    );

class _ColourPicker extends StatefulWidget {
  final String title;
  final Color initial;
  final bool background;
  const _ColourPicker({required this.title, required this.initial, required this.background});

  @override
  State<_ColourPicker> createState() => _ColourPickerState();
}

class _ColourPickerState extends State<_ColourPicker> {
  late HSLColor _hsl = HSLColor.fromColor(_fit(widget.initial));

  /// Brightness range the sliders allow.
  double get _minL => widget.background ? 0.0 : AppPalette.minAccentLightness;
  double get _maxL => widget.background ? AppPalette.maxBackgroundLightness : AppPalette.maxAccentLightness;

  Color _fit(Color c) => widget.background ? AppPalette.keepDark(c) : AppPalette.keepVisible(c);

  void _set(HSLColor h) => setState(() => _hsl = h);

  @override
  Widget build(BuildContext context) {
    final colour = _hsl.toColor();
    final suggestions = widget.background ? backgroundSuggestions : accentSuggestions;
    Widget slider(String label, double value, double min, double max, ValueChanged<double> onChanged,
            {required Gradient track}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          Stack(alignment: Alignment.center, children: [
            Container(
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(gradient: track, borderRadius: BorderRadius.circular(5)),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
              ),
              child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
            ),
          ]),
        ]);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // What it will look like: white text on a background, or the highlight on the
            // current background.
            Container(
              key: const ValueKey('colour-preview'),
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.background ? colour : AppColors.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: widget.background
                  ? Text('Song title', style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontWeight: FontWeight.w600))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.favorite, color: colour),
                      const SizedBox(width: 12),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
                        child: Icon(Icons.play_arrow_rounded,
                            color: colour.computeLuminance() > 0.4 ? Colors.black : Colors.white),
                      ),
                    ]),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in suggestions)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _set(HSLColor.fromColor(_fit(s))),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: s,
                      shape: BoxShape.circle,
                      border: Border.all(color: _fit(s) == colour ? Colors.white : Colors.white24, width: _fit(s) == colour ? 2.5 : 1),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            slider('Shade', _hsl.hue, 0, 359.9, (v) => _set(_hsl.withHue(v)),
                track: LinearGradient(colors: [
                  for (var h = 0; h <= 360; h += 60)
                    HSLColor.fromAHSL(1, h.toDouble() % 360, 0.8, widget.background ? 0.2 : 0.6).toColor(),
                ])),
            slider('Strength', _hsl.saturation, 0, 1, (v) => _set(_hsl.withSaturation(v)),
                track: LinearGradient(colors: [_hsl.withSaturation(0).toColor(), _hsl.withSaturation(1).toColor()])),
            slider('Brightness', _hsl.lightness, _minL, _maxL, (v) => _set(_hsl.withLightness(v)),
                track: LinearGradient(colors: [_hsl.withLightness(_minL).toColor(), _hsl.withLightness(_maxL).toColor()])),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_fit(colour)), child: const Text('Use this colour')),
      ],
    );
  }
}
