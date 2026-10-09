// The colour picker used by Appearance's theme editor and the video player look: suggestions, a
// colour wheel and a colour code box. Split out of appearance_settings.dart in refactor phase 6
// (9 Oct 2026), unchanged.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme.dart';

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

/// Any colour, dark to light (the Advanced editor).
const anySuggestions = <Color>[
  Color(0xFF000000), Color(0xFF101114), Color(0xFF24272E), Color(0xFF5B6270), Color(0xFFA3A8B3), Color(0xFFE9EBEF),
  Color(0xFFFFFFFF), Color(0xFF2F6FEB), Color(0xFF5AB4FF), Color(0xFF4CC38A), Color(0xFFF2C84B), Color(0xFFFF7A59),
  Color(0xFFFF5C8A), Color(0xFFA77BFF),
];

/// What the colour picker allows: a bright highlight ("Your own"), a dark background ("Your
/// own"), or anything (Advanced).
enum PickerMode { accent, darkBackground, any }

/// Lets the user pick a colour from suggestions or with shade / strength / brightness sliders.
/// Returns the colour, or null if cancelled.
Future<Color?> showColourPicker(BuildContext context,
        {required String title, required Color initial, PickerMode mode = PickerMode.accent}) =>
    showDialog<Color>(
      context: context,
      builder: (_) => _ColourPicker(title: title, initial: initial, mode: mode),
    );

class _ColourPicker extends StatefulWidget {
  final String title;
  final Color initial;
  final PickerMode mode;
  const _ColourPicker({required this.title, required this.initial, required this.mode});

  @override
  State<_ColourPicker> createState() => _ColourPickerState();
}

class _ColourPickerState extends State<_ColourPicker> {
  late HSLColor _hsl = HSLColor.fromColor(_fit(widget.initial));

  /// Brightness range the sliders allow.
  double get _minL => switch (widget.mode) {
        PickerMode.accent => AppPalette.minAccentLightness,
        _ => 0.0,
      };
  double get _maxL => switch (widget.mode) {
        PickerMode.accent => AppPalette.maxAccentLightness,
        PickerMode.darkBackground => AppPalette.maxBackgroundLightness,
        PickerMode.any => 1.0,
      };

  Color _fit(Color c) => switch (widget.mode) {
        PickerMode.accent => AppPalette.keepVisible(c),
        PickerMode.darkBackground => AppPalette.keepDark(c),
        PickerMode.any => c.withAlpha(255),
      };

  // The colour code box (0.1.29): shows the code of the colour picked with the sliders or
  // suggestions, and a code typed or pasted in picks that colour.
  late final _code = TextEditingController(text: colourToHex(_hsl.toColor()));

  /// Why the typed code wasn't used (not a code), or null.
  String? _codeError;

  /// The typed code, when it had to be changed to stay readable (Your own only).
  String? _adjustedFrom;

  /// The colour from a typed code, exactly (going through the sliders' shade / strength /
  /// brightness numbers can move it by one step). Cleared when a slider or suggestion is used.
  Color? _typedColour;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// A suggestion or slider: the code box follows.
  void _set(HSLColor h) => setState(() {
        _hsl = h;
        _typedColour = null;
        _code.text = colourToHex(h.toColor());
        _codeError = null;
        _adjustedFrom = null;
      });

  /// A code was typed or pasted.
  void _typed(String text) {
    final c = parseColourCode(text);
    setState(() {
      if (text.trim().isEmpty) {
        _codeError = null;
        _adjustedFrom = null;
        return;
      }
      if (c == null) {
        _codeError = 'Type a colour code like #FF7A59';
        _adjustedFrom = null;
        return;
      }
      final fitted = _fit(c);
      _hsl = HSLColor.fromColor(fitted);
      _typedColour = fitted;
      _codeError = null;
      _adjustedFrom = fitted == c ? null : colourToHex(c);
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    _code.text = text;
    _code.selection = TextSelection.collapsed(offset: text.length);
    _typed(text);
  }

  @override
  Widget build(BuildContext context) {
    final colour = _typedColour ?? _hsl.toColor();
    final suggestions = switch (widget.mode) {
      PickerMode.accent => accentSuggestions,
      PickerMode.darkBackground => backgroundSuggestions,
      PickerMode.any => anySuggestions,
    };
    final edge = AppColors.textDim.withValues(alpha: 0.5);
    Widget slider(String label, double value, double min, double max, ValueChanged<double> onChanged,
            {required Gradient track}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          Stack(alignment: Alignment.center, children: [
            Container(
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(gradient: track, borderRadius: AppShape.circular(5)),
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
            // What it will look like: a highlight on the current background, a background with
            // white text, or (Advanced) the colour itself with its code.
            Container(
              key: const ValueKey('colour-preview'),
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.mode == PickerMode.accent ? AppColors.bg : colour,
                borderRadius: AppShape.circular(10),
                border: Border.all(color: edge),
              ),
              child: switch (widget.mode) {
                PickerMode.darkBackground => Text('Song title',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontWeight: FontWeight.w600)),
                PickerMode.any => Text(colourToHex(colour),
                    style: TextStyle(color: AppPalette.onColour(colour), fontWeight: FontWeight.w600)),
                PickerMode.accent => Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.favorite, color: colour),
                    const SizedBox(width: 12),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
                      child: Icon(Icons.play_arrow_rounded, color: AppPalette.onColour(colour)),
                    ),
                  ]),
              },
            ),
            const SizedBox(height: 12),
            // Type or paste a colour code (0.1.29).
            TextField(
              key: const ValueKey('colour-code'),
              controller: _code,
              onChanged: _typed,
              onSubmitted: (_) {
                if (_codeError == null) Navigator.of(context).pop(_fit(colour));
              },
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [LengthLimitingTextInputFormatter(24)],
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
              decoration: InputDecoration(
                labelText: 'Colour code',
                hintText: '#FF7A59',
                isDense: true,
                errorText: _codeError,
                helperText: _adjustedFrom == null
                    ? 'Type or paste a code, or pick below'
                    : '$_adjustedFrom changed to ${colourToHex(colour)} so it stays easy to read',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  key: const ValueKey('paste-colour'),
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste),
                  onPressed: _paste,
                ),
              ),
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
                      border: Border.all(
                          color: _fit(s) == colour ? AppColors.text : edge, width: _fit(s) == colour ? 2.5 : 1),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            slider('Shade', _hsl.hue, 0, 359.9, (v) => _set(_hsl.withHue(v)),
                track: LinearGradient(colors: [
                  for (var h = 0; h <= 360; h += 60)
                    HSLColor.fromAHSL(1, h.toDouble() % 360, 0.8, widget.mode == PickerMode.darkBackground ? 0.2 : 0.6)
                        .toColor(),
                ])),
            slider('Strength', _hsl.saturation, 0, 1, (v) => _set(_hsl.withSaturation(v)),
                track: LinearGradient(colors: [_hsl.withSaturation(0).toColor(), _hsl.withSaturation(1).toColor()])),
            slider('Brightness', _hsl.lightness, _minL, _maxL, (v) => _set(_hsl.withLightness(v)),
                track: LinearGradient(colors: [
                  _hsl.withLightness(_minL).toColor(),
                  if (widget.mode == PickerMode.any) _hsl.withLightness(0.5).toColor(),
                  _hsl.withLightness(_maxL).toColor(),
                ])),
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
