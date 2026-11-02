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
import 'package:provider/provider.dart';

import '../../services/word_predictor.dart';
import '../../state/library_model.dart';
import '../theme.dart';
import 'tv_browse.dart' show TvButton;
import 'tv_focus.dart' show tvModeOf;
import 'tv_widgets.dart';
import 'tv_words.dart';

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

/// The number pad (0.2.8), for boxes that take a number (Year, Season, Episode).
const tvNumberRows = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['.', '0', '-'],
];

/// A grid of keys. [full] adds Shift, the symbols page and (with [onDone]) Done.
///
/// 0.2.8: [predictions] show in a row over the keys (↑ from the top row goes to them; OK puts the
/// word in, [onPredict]); [capitalNext] makes the next letter a capital by itself (a name's next
/// word, a new sentence; Shift makes it small instead); [numbers] opens on the number pad.
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
    this.predictions,
    this.onPredict,
    this.capitalNext = false,
    this.numbers = false,
    this.firstKey,
  });

  /// The top-left key's focus node, when the page needs it (to put focus back on the keys).
  final FocusNode? firstKey;

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

  /// The words offered over the keys (null: no row for them).
  final List<Prediction>? predictions;
  final ValueChanged<Prediction>? onPredict;

  /// The next letter is a capital unless Shift is pressed.
  final bool capitalNext;

  /// Start on the number pad.
  final bool numbers;

  static const keySize = 42.0, gap = 6.0;
  static const width = keySize * 6 + gap * 5;

  /// Most predictions shown at once.
  static const most = 4;

  @override
  State<TvKeyboard> createState() => _TvKeyboardState();
}

class _TvKeyboardState extends State<TvKeyboard> {
  bool _caps = false, _symbols = false;
  late bool _numbers = widget.numbers;

  /// Shift was pressed while a capital was coming by itself: this letter is small.
  bool _small = false;

  FocusNode? _own;
  FocusNode get _first => widget.firstKey ?? (_own ??= FocusNode(debugLabel: 'tv key a'));

  bool get _upper => _caps || (widget.capitalNext && !_small);

  @override
  void didUpdateWidget(TvKeyboard old) {
    super.didUpdateWidget(old);
    if (old.capitalNext != widget.capitalNext) _small = false;
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  String _show(int r, int c) {
    if (_symbols) return tvSymbolRows[r][c];
    final k = tvKeyboardRows[r][c];
    return _upper ? k.toUpperCase() : k;
  }

  void _type(String s) {
    widget.onType(s);
    if (_small) setState(() => _small = false);
  }

  void _shift() => setState(() {
        _symbols = false;
        if (widget.capitalNext && !_caps && !_small) {
          _small = true; // this one capital, not wanted
        } else if (_small) {
          _small = false;
          _caps = true;
        } else {
          _caps = !_caps;
        }
      });

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
          if (w.predictions != null) ...[
            TvPredictionRow(predictions: w.predictions!, onPredict: (p) => w.onPredict?.call(p), fallback: _first),
            const SizedBox(height: g + 2),
          ],
          if (_numbers)
            for (var r = 0; r < tvNumberRows.length; r++) ...[
              Row(
                children: [
                  for (var c = 0; c < 3; c++) ...[
                    if (c > 0) const SizedBox(width: g),
                    TvKey(
                      key: ValueKey('tv-num-${tvNumberRows[r][c]}'),
                      focusNode: r == 0 && c == 0 ? _first : null,
                      label: tvNumberRows[r][c],
                      width: wide,
                      autofocus: w.autofocus && r == 0 && c == 0,
                      onPressed: () => _type(tvNumberRows[r][c]),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: g),
            ]
          else
            for (var r = 0; r < tvKeyboardRows.length; r++) ...[
              Row(
                children: [
                  for (var c = 0; c < 6; c++) ...[
                    if (c > 0) const SizedBox(width: g),
                    TvKey(
                      key: ValueKey('tv-key-${tvKeyboardRows[r][c]}'),
                      focusNode: r == 0 && c == 0 ? _first : null,
                      // The short keyboard shows capitals, as most remotes' keyboards do, but types small.
                      label: w.full ? _show(r, c) : _show(r, c).toUpperCase(),
                      width: k,
                      autofocus: w.autofocus && r == 0 && c == 0,
                      onPressed: () => _type(_show(r, c)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: g),
            ],
          if (w.full)
            Row(
              children: [
                _numbers
                    ? TvKey(
                        key: const ValueKey('tv-key-Letters'),
                        label: 'abc',
                        width: wide,
                        onPressed: () => setState(() => _numbers = false),
                      )
                    : TvKey(
                        key: const ValueKey('tv-key-Shift'),
                        label: 'Shift',
                        icon: Icons.arrow_upward,
                        on: _upper && !_symbols,
                        width: wide,
                        onPressed: _shift,
                      ),
                const SizedBox(width: g),
                TvKey(
                  key: const ValueKey('tv-key-Symbols'),
                  label: _numbers ? '#+=' : (_symbols ? 'abc' : (w.numbers ? '123' : '#+=')),
                  width: wide,
                  onPressed: () => setState(() {
                    if (_numbers) {
                      _numbers = false;
                      _symbols = true;
                    } else if (w.numbers && !_symbols) {
                      _numbers = true;
                    } else {
                      _symbols = !_symbols;
                    }
                  }),
                ),
                const SizedBox(width: g),
                w.newLine
                    ? TvKey(
                        key: const ValueKey('tv-key-New line'),
                        label: 'New line',
                        icon: Icons.keyboard_return,
                        width: wide,
                        onPressed: () => _type('\n'),
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
                onPressed: w.canSpace ? () => _type(' ') : null,
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

/// The predicted words (0.2.8): up to [TvKeyboard.most], OK on one is [onPredict]. Over the keys
/// (narrow: each takes a share of the width by its length) or across a page ([natural]: each as
/// wide as its word). When the one with focus goes (a word was put in and fewer are offered), focus
/// moves to the last one left, or to [fallback] (the keys).
class TvPredictionRow extends StatefulWidget {
  const TvPredictionRow({super.key, required this.predictions, required this.onPredict, this.fallback, this.natural = false});
  final List<Prediction> predictions;
  final ValueChanged<Prediction> onPredict;
  final FocusNode? fallback;
  final bool natural;

  @override
  State<TvPredictionRow> createState() => _TvPredictionRowState();
}

class _TvPredictionRowState extends State<TvPredictionRow> {
  final _slots = [for (var i = 0; i < TvKeyboard.most; i++) FocusNode(debugLabel: 'tv prediction $i')];

  @override
  void didUpdateWidget(TvPredictionRow old) {
    super.didUpdateWidget(old);
    final n = widget.predictions.length.clamp(0, TvKeyboard.most);
    final had = _slots.indexWhere((f) => f.hasFocus);
    if (had >= n && had >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (n > 0 ? _slots[n - 1] : widget.fallback)?.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final f in _slots) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const g = TvKeyboard.gap;
    final list = widget.predictions;
    Widget key(int i) => TvKey(
          key: ValueKey('tv-predict-$i'),
          focusNode: _slots[i],
          label: list[i].word,
          width: widget.natural ? null : double.infinity,
          height: 36,
          word: true,
          onPressed: () => widget.onPredict(list[i]),
        );
    return SizedBox(
      key: const ValueKey('tv-predictions'),
      height: 36,
      child: Row(children: [
        for (var i = 0; i < list.length && i < TvKeyboard.most; i++) ...[
          if (i > 0) SizedBox(width: widget.natural ? 10 : g),
          widget.natural
              // As wide as the word (up to a share of the row when they're all long).
              ? Flexible(child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 72), child: key(i)))
              // Over the keys: a share of the width by the word's length, so long ones aren't
              // cut short next to short ones.
              : Expanded(flex: list[i].word.characters.length.clamp(4, 16), child: key(i)),
        ],
        if (list.isEmpty)
          Expanded(
            child: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.surfaceHigh),
              ),
              child: Text('Suggested words show here',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textDim)),
            ),
          ),
      ]),
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
    this.focusNode,
    this.word = false,
    this.height = 40,
  });
  final bool autofocus;
  final double height;
  final FocusNode? focusNode;

  /// A predicted word: its text left-aligned, cut short if it doesn't fit.
  final bool word;
  final String label;
  final IconData? icon;
  /// Null: as wide as its label.
  final double? width;
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
      focusNode: focusNode,
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
            height: height,
            alignment: width == null ? null : Alignment.center,
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
                      if ((width ?? 0) > 60 && label != 'Delete') ...[
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
                        ),
                      ],
                    ],
                  )
                : word
                ? Align(
                    // As wide as the word when there's no width (centred up and down either way).
                    widthFactor: width == null ? 1 : null,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: width == null ? 14 : 4),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg),
                      ),
                    ),
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
  TvTyping? typing,
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
      typing: typing ?? tvTypingFor(label: title, obscure: obscure, multiline: multiline),
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
    this.typing = TvTyping.title,
  });
  final String title, initial;
  final String? hint;
  final bool obscure, multiline;
  final int? maxLength;

  /// What it's for (0.2.8): the keys, capitals and predicted words.
  final TvTyping typing;

  @override
  State<TvTextInput> createState() => _TvTextInputState();
}

class _TvTextInputState extends State<TvTextInput> {
  late String _text = widget.initial;
  bool _show = false;
  WordPredictor? _predictor;
  LibraryModel? _lib;
  final _firstKey = FocusNode(debugLabel: 'tv key a');

  @override
  void dispose() {
    _firstKey.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final typing = widget.typing;
    if (!typing.predicts) return;
    _lib = context.read<LibraryModel?>();
    // The library's words at once; the words typed before as soon as they're read.
    _predictor = tvPredictorFor(context, typing, label: widget.title);
    final lib = _lib;
    if (lib != null && typing != TvTyping.address) {
      TypedWords.load(lib).then((learned) {
        if (!mounted || learned.isEmpty) return;
        setState(() => _predictor = tvPredictorFor(context, typing, label: widget.title, learned: learned));
      });
    }
  }

  /// Whether the next letter starts a word (names) or a sentence (descriptions).
  bool get _capitalNext {
    final t = _text;
    switch (widget.typing) {
      case TvTyping.title || TvTyping.pick:
        return t.isEmpty || t.endsWith(' ') || t.endsWith('\n');
      case TvTyping.sentence:
        final before = t.trimRight();
        return before.isEmpty ||
            t.endsWith('\n') ||
            (t.endsWith(' ') && (before.endsWith('.') || before.endsWith('!') || before.endsWith('?')));
      default:
        return false;
    }
  }

  void _predict(Prediction p) {
    var next = WordPredictor.apply(_text, p);
    if (widget.typing == TvTyping.address && p.whole) next = p.word; // no space after an address
    if (widget.maxLength != null && next.characters.length > widget.maxLength!) return;
    setState(() => _text = next);
  }

  void _type(String s) {
    if (widget.maxLength != null && _text.characters.length >= widget.maxLength!) return;
    if (s == '\n' && !widget.multiline) return;
    setState(() => _text += s);
  }

  void _delete() {
    if (_text.isEmpty) return;
    setState(() => _text = _text.characters.skipLast(1).toString());
  }

  void _done() {
    final lib = _lib;
    if (lib != null && widget.typing.remembers && !widget.obscure) TypedWords.learn(lib, _text);
    Navigator.of(context).pop(_text);
  }

  @override
  Widget build(BuildContext context) {
    final hidden = widget.obscure && !_show;
    final shown = hidden ? '•' * _text.characters.length : _text;
    final predictions = _predictor == null || hidden ? null : _predictor!.predict(_text, max: TvKeyboard.most);
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
              const SizedBox(height: 12),
              // Predicted words across the page (0.2.8), so long names show whole; ↑ from the
              // keys' top row comes here.
              if (predictions != null) ...[
                TvPredictionRow(predictions: predictions, onPredict: _predict, fallback: _firstKey, natural: true),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TvKeyboard(
                      full: true,
                      autofocus: true,
                      firstKey: _firstKey,
                      numbers: widget.typing == TvTyping.number,
                      capitalNext: _capitalNext,
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
      typing: tvTypingFor(
        label: _label,
        keyboardType: f.keyboardType,
        obscure: f.obscureText,
        multiline: f.maxLines != 1 || f.keyboardType == TextInputType.multiline,
      ),
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
