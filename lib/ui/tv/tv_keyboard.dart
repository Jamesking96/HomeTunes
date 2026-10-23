// The TV's on-screen keyboard (0.2.0, steps 6 and 7 of the TV interface; mockups "Search" and
// "Settings"). A remote has no letters, so typing is done by moving over a grid of keys and
// pressing OK. Search uses the short version (a–z, 1–0, Space, Delete, Clear); every other text
// box in TV mode opens [showTvTextInput]: the full version, with capitals, a page of symbols and
// accented letters, and Done. A real keyboard (or the remote's number keys) types too.
//
// The keys stay where they are when the capitals or symbols are switched on, so the remote stays
// on the same spot: each key is named after its place on the letters page ("tv-key-a").
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'tv_browse.dart' show TvButton;
import 'tv_focus.dart' show tvModeOf;
import 'tv_widgets.dart';

/// The letters page, a row at a time: a–z then 1–0.
const tvKeyboardRows = [
  ['a', 'b', 'c', 'd', 'e', 'f'],
  ['g', 'h', 'i', 'j', 'k', 'l'],
  ['m', 'n', 'o', 'p', 'q', 'r'],
  ['s', 't', 'u', 'v', 'w', 'x'],
  ['y', 'z', '1', '2', '3', '4'],
  ['5', '6', '7', '8', '9', '0'],
];

/// The symbols page, in the same places.
const tvSymbolRows = [
  ['.', ',', '-', '_', '/', ':'],
  ['@', "'", '&', '(', ')', '!'],
  ['?', '#', '+', '=', '*', '%'],
  [r'$', '"', ';', '~', '<', '>'],
  ['[', ']', '|', r'\', 'é', 'è'],
  ['à', 'ü', 'ö', 'ñ', 'ç', 'ø'],
];

/// A grid of keys. [full] adds Shift, the symbols page and (with [onDone]) Done.
class TvKeyboard extends StatefulWidget {
  const TvKeyboard({
    super.key,
    required this.onType,
    required this.onDelete,
    required this.onClear,
    this.onDone,
    this.full = false,
    this.canSpace = true,
    this.newLine = false,
    this.autofocus = false,
  });

  final ValueChanged<String> onType;
  final VoidCallback onDelete, onClear;
  final VoidCallback? onDone;
  final bool full;

  /// False dims Space (nothing typed yet, in Search).
  final bool canSpace;

  /// A New line key (text that can run over several lines).
  final bool newLine;

  /// The first key takes focus when it appears.
  final bool autofocus;

  static const keySize = 42.0, gap = 6.0;
  static const width = keySize * 6 + gap * 5;

  @override
  State<TvKeyboard> createState() => _TvKeyboardState();
}

class _TvKeyboardState extends State<TvKeyboard> {
  bool _caps = false, _symbols = false;

  String _show(int r, int c) {
    if (_symbols) return tvSymbolRows[r][c];
    final k = tvKeyboardRows[r][c];
    return _caps ? k.toUpperCase() : k;
  }

  @override
  Widget build(BuildContext context) {
    const k = TvKeyboard.keySize, g = TvKeyboard.gap;
    const wide = k * 2 + g;
    final w = widget;
    return SizedBox(
      width: TvKeyboard.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < tvKeyboardRows.length; r++) ...[
            Row(
              children: [
                for (var c = 0; c < 6; c++) ...[
                  if (c > 0) const SizedBox(width: g),
                  TvKey(
                    key: ValueKey('tv-key-${tvKeyboardRows[r][c]}'),
                    // The short keyboard shows capitals, as most remotes' keyboards do, but types small.
                    label: w.full ? _show(r, c) : _show(r, c).toUpperCase(),
                    width: k,
                    autofocus: w.autofocus && r == 0 && c == 0,
                    onPressed: () => w.onType(_show(r, c)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: g),
          ],
          if (w.full)
            Row(
              children: [
                TvKey(
                  key: const ValueKey('tv-key-Shift'),
                  label: 'Shift',
                  icon: Icons.arrow_upward,
                  on: _caps && !_symbols,
                  width: wide,
                  onPressed: () => setState(() {
                    _symbols = false;
                    _caps = !_caps;
                  }),
                ),
                const SizedBox(width: g),
                TvKey(
                  key: const ValueKey('tv-key-Symbols'),
                  label: _symbols ? 'abc' : '#+=',
                  width: wide,
                  onPressed: () => setState(() => _symbols = !_symbols),
                ),
                const SizedBox(width: g),
                w.newLine
                    ? TvKey(
                        key: const ValueKey('tv-key-New line'),
                        label: 'New line',
                        icon: Icons.keyboard_return,
                        width: wide,
                        onPressed: () => w.onType('\n'),
                      )
                    : TvKey(
                        key: const ValueKey('tv-key-Done'),
                        label: 'Done',
                        width: wide,
                        accent: true,
                        onPressed: w.onDone,
                      ),
              ],
            ),
          if (w.full) const SizedBox(height: g),
          Row(
            children: [
              TvKey(
                key: const ValueKey('tv-key-Space'),
                label: 'Space',
                width: wide,
                onPressed: w.canSpace ? () => w.onType(' ') : null,
              ),
              const SizedBox(width: g),
              TvKey(
                key: const ValueKey('tv-key-Delete'),
                label: 'Delete',
                icon: Icons.backspace_outlined,
                width: wide,
                onPressed: w.onDelete,
                onHold: w.onClear,
              ),
              const SizedBox(width: g),
              TvKey(key: const ValueKey('tv-key-Clear'), label: 'Clear', width: wide, onPressed: w.onClear),
            ],
          ),
        ],
      ),
    );
  }
}

/// One key. With [onPressed] null it still takes focus (so a row doesn't jump about), dimmed.
class TvKey extends StatelessWidget {
  const TvKey({
    super.key,
    required this.label,
    required this.width,
    required this.onPressed,
    this.icon,
    this.onHold,
    this.on = false,
    this.accent = false,
    this.autofocus = false,
  });
  final bool autofocus;
  final String label;
  final IconData? icon;
  final double width;
  final VoidCallback? onPressed, onHold;

  /// Lit (Shift while capitals are on).
  final bool on;

  /// In the accent colour (Done).
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final single = label.characters.length == 1;
    return TvPressable(
      semanticLabel: label,
      autofocus: autofocus,
      onPressed: onPressed ?? () {},
      onHold: onHold,
      builder: (context, focused) {
        final fg = focused || accent ? AppColors.current.onAccent : (enabled ? Colors.white : AppColors.textDim);
        return TvFocusFrame(
          focused: focused,
          radius: 8,
          grow: false,
          child: Container(
            width: width,
            height: 40,
            alignment: Alignment.center,
            color: focused
                ? AppColors.accent
                : accent
                ? AppColors.accent.withValues(alpha: 0.75)
                : on
                ? AppColors.accent.withValues(alpha: 0.35)
                : AppColors.surfaceHigh,
            child: icon != null && !single
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 16, color: fg),
                      if (width > 60 && label != 'Delete') ...[
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
                        ),
                      ],
                    ],
                  )
                : Text(
                    label,
                    style: TextStyle(fontSize: single ? 17 : 13, fontWeight: FontWeight.w600, color: fg),
                  ),
          ),
        );
      },
    );
  }
}

/// Typing on a real keyboard while the on-screen one is in use: [onType] for a letter, digit or
/// symbol, [onDelete] for Backspace. Returns null for any other key.
KeyEventResult tvHardKey(KeyEvent e, {required ValueChanged<String> onType, required VoidCallback onDelete}) {
  if (e is KeyUpEvent) return KeyEventResult.ignored;
  if (e.logicalKey == LogicalKeyboardKey.backspace) {
    onDelete();
    return KeyEventResult.handled;
  }
  final c = e.character;
  if (c != null && c.isNotEmpty && c.codeUnitAt(0) >= 32 && c.codeUnitAt(0) != 127) {
    onType(c);
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

/// Asks for some text with the full keyboard: [title] over it, [initial] already typed. Returns
/// what was typed, or null if Back or Cancel was pressed. [obscure]: shown as dots (a password),
/// with Show to see it. [multiline]: a New line key, and the text wraps.
Future<String?> showTvTextInput(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  bool obscure = false,
  bool multiline = false,
  int? maxLength,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close the keyboard',
    barrierColor: const Color(0xE6050608),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, _, _) => TvTextInput(
      title: title,
      initial: initial,
      hint: hint,
      obscure: obscure,
      multiline: multiline,
      maxLength: maxLength,
    ),
    transitionBuilder: (context, anim, _, child) => FadeTransition(opacity: anim, child: child),
  );
}

/// The page [showTvTextInput] shows: the keyboard on the left, the text and Done / Cancel on the right.
class TvTextInput extends StatefulWidget {
  const TvTextInput({
    super.key,
    required this.title,
    this.initial = '',
    this.hint,
    this.obscure = false,
    this.multiline = false,
    this.maxLength,
  });
  final String title, initial;
  final String? hint;
  final bool obscure, multiline;
  final int? maxLength;

  @override
  State<TvTextInput> createState() => _TvTextInputState();
}

class _TvTextInputState extends State<TvTextInput> {
  late String _text = widget.initial;
  bool _show = false;

  void _type(String s) {
    if (widget.maxLength != null && _text.characters.length >= widget.maxLength!) return;
    if (s == '\n' && !widget.multiline) return;
    setState(() => _text += s);
  }

  void _delete() {
    if (_text.isEmpty) return;
    setState(() => _text = _text.characters.skipLast(1).toString());
  }

  void _done() => Navigator.of(context).pop(_text);

  @override
  Widget build(BuildContext context) {
    final hidden = widget.obscure && !_show;
    final shown = hidden ? '•' * _text.characters.length : _text;
    return Material(
      color: AppColors.bg, // over everything: what is behind only distracts
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, e) => tvHardKey(e, onType: _type, onDelete: _delete),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            TvStyle.sideMargin + 24,
            TvStyle.topMargin + 8,
            TvStyle.sideMargin + 24,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TvKeyboard(
                      full: true,
                      autofocus: true,
                      newLine: widget.multiline,
                      onType: _type,
                      onDelete: _delete,
                      onClear: () => setState(() => _text = ''),
                      onDone: _done,
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            key: const ValueKey('tv-text-box'),
                            width: double.infinity,
                            constraints: BoxConstraints(minHeight: 52, maxHeight: widget.multiline ? 220 : 120),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHigh,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.accent, width: 2),
                            ),
                            child: SingleChildScrollView(
                              reverse: true,
                              child: _text.isEmpty
                                  ? Text(widget.hint ?? '', style: TextStyle(fontSize: 18, color: AppColors.textDim))
                                  : Text(
                                      '$shown|',
                                      key: const ValueKey('tv-text'),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                          if (widget.maxLength != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${_text.characters.length} / ${widget.maxLength}',
                              style: TextStyle(fontSize: 13, color: AppColors.textDim),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              TvButton(
                                key: const ValueKey('tv-text-done'),
                                label: 'Done',
                                icon: Icons.check,
                                primary: true,
                                onPressed: _done,
                              ),
                              TvButton(
                                key: const ValueKey('tv-text-cancel'),
                                label: 'Cancel',
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              if (widget.obscure)
                                TvButton(
                                  key: const ValueKey('tv-text-show'),
                                  label: _show ? 'Hide' : 'Show',
                                  icon: _show ? Icons.visibility_off : Icons.visibility,
                                  onPressed: () => setState(() => _show = !_show),
                                ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            'A keyboard plugged into the TV types here too.',
                            style: TextStyle(fontSize: 13, color: AppColors.textDim),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A text box that, in TV mode, opens [showTvTextInput] instead of the phone's keyboard: wrap any
/// [TextField] in it. Off TV mode it is just [field]. On the TV it looks like the box (its label
/// and what's typed); OK opens the keyboard, and Done puts the text in the box's controller and
/// tells [TextField.onChanged] and [TextField.onSubmitted], as typing and Enter would.
class TvTextField extends StatefulWidget {
  const TvTextField({super.key, required this.field});
  final TextField field;

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  /// Holds the text when the field has no controller of its own.
  TextEditingController? _own;
  TextEditingController get _controller => widget.field.controller ?? (_own ??= TextEditingController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  String get _label {
    final d = widget.field.decoration;
    return d?.labelText ?? d?.hintText ?? d?.helperText ?? 'Type';
  }

  Future<void> _edit() async {
    final f = widget.field;
    var typed = await showTvTextInput(
      context,
      title: _label,
      initial: _controller.text,
      hint: f.decoration?.hintText,
      obscure: f.obscureText,
      multiline: f.maxLines != 1 || f.keyboardType == TextInputType.multiline,
      maxLength: f.maxLength,
    );
    if (typed == null || !mounted) return;
    // The box's own rules (digits only, a length) apply as if it had been typed there.
    var value = TextEditingValue(text: typed, selection: TextSelection.collapsed(offset: typed.length));
    for (final rule in f.inputFormatters ?? const <TextInputFormatter>[]) {
      value = rule.formatEditUpdate(_controller.value, value);
    }
    typed = value.text;
    _controller.text = typed;
    f.onChanged?.call(typed);
    f.onSubmitted?.call(typed);
    f.onEditingComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    if (!tvModeOf(context) || f.readOnly) return f;
    final d = f.decoration;
    final enabled = f.enabled ?? d?.enabled ?? true;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final text = _controller.text;
        final shown = f.obscureText ? '•' * text.characters.length : text;
        return TvPressable(
          semanticLabel: _label,
          autofocus: f.autofocus,
          focusNode: f.focusNode,
          onPressed: enabled ? _edit : null,
          builder: (context, focused) => TvFocusFrame(
            focused: focused,
            radius: 8,
            grow: false,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: focused ? AppColors.surfaceHigh : AppColors.surface,
              child: Row(
                children: [
                  if (d?.prefixIcon != null) ...[
                    IconTheme(
                      data: IconThemeData(color: AppColors.textDim, size: 20),
                      child: d!.prefixIcon!,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (d?.labelText != null)
                          Text(
                            d!.labelText!,
                            style: TextStyle(fontSize: 12, color: focused ? AppColors.accent : AppColors.textDim),
                          ),
                        Text(
                          text.isEmpty ? (d?.hintText ?? '') : shown,
                          maxLines: f.maxLines == 1 ? 1 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            color: text.isEmpty ? AppColors.textDim : (enabled ? Colors.white : AppColors.textDim),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.keyboard_outlined, size: 18, color: focused ? AppColors.accent : AppColors.textDim),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
