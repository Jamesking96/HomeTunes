// What the TV's browsing screens share (0.2.0, step 2 of the TV interface: Home and the
// libraries; mockups "HomeTunes TV Interface", agreed 23 Oct):
//  * [TvPage]: a screen's frame: its title, the tabs beside it, buttons at the right, the body.
//  * [TvTabBar]: the tabs (Albums, Artists, Songs…). Moving onto a tab shows it after a moment
//    (OK shows it at once); coming up from the page lands on the tab that's showing.
//  * [TvAzGrid]: a grid of tiles (or a list of rows) with the A–Z strip down its right edge.
//    → at a row's end moves onto the strip; ↑ ↓ there jump letter by letter; ← or OK goes back
//    into the grid at that letter.
//  * [TvShelf]: a heading with a row of tiles that scrolls sideways (Home's rows).
//  * [TvButton]: a rounded button (Play, Shuffle, Sort).
//  * [TvHintBoard] / [TvPageHints]: lets the page that's showing set the hint bubble's words.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/library_index.dart' show sortKey;
import '../theme.dart';
import 'tv_focus.dart';
import 'tv_widgets.dart';

/// The letter [name] is listed under on the A–Z strip: its first letter, ignoring a leading
/// "The " and case, and "#" for anything that doesn't start with A–Z.
String tvLetterOf(String name) {
  final k = sortKey(name);
  if (k.isEmpty) return '#';
  final c = k[0].toUpperCase();
  return (c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90) ? c : '#';
}

/// The strip's letters, in order.
const tvLetters = ['#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'];

/// The hint bubble's words for the page that's showing in each tab. The TV frame shows them;
/// pages say theirs with [TvPageHints].
class TvHintBoard extends ChangeNotifier {
  // Per tab: the page that set the words, and the words.
  final _byTab = <int, (Object, List<TvHint>)>{};

  List<TvHint>? forTab(int tab) => _byTab[tab]?.$2;

  /// [owner] (a page) shows [hints] in [tab]; with null hints it takes its words away, unless
  /// another page has put up its own since (a page opened over it).
  void set(int tab, Object owner, List<TvHint>? hints) {
    final old = _byTab[tab];
    if (hints == null) {
      if (old == null || !identical(old.$1, owner)) return;
      _byTab.remove(tab);
    } else {
      if (old != null && identical(old.$1, owner) && listEquals(old.$2, hints)) return;
      _byTab[tab] = (owner, hints);
    }
    notifyListeners();
  }
}

/// Sets the hint bubble's words for [tab] while this page is the one showing (a page opened
/// over it puts its own up; closing that one brings these back).
class TvPageHints extends StatelessWidget {
  const TvPageHints({super.key, required this.tab, required this.hints, required this.child});
  final int tab;
  final List<TvHint> hints;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final showing = ModalRoute.of(context)?.isCurrent ?? true;
    final board = Provider.of<TvHintBoard?>(context, listen: false);
    if (board != null) {
      final owner = context; // this page's place in the tree
      WidgetsBinding.instance.addPostFrameCallback((_) => board.set(tab, owner, showing ? hints : null));
    }
    return child;
  }
}

/// A screen's frame: [title] with [tabs] beside it and [actions] at the right, then [body].
/// ↑ from the top of the body goes to the tabs (the one showing), even where a button is
/// nearer; the buttons are reached along the tabs' row.
class TvPage extends StatefulWidget {
  const TvPage({super.key, required this.title, this.tabs, this.actions = const [], required this.body});
  final String title;
  final Widget? tabs;
  final List<Widget> actions;
  final Widget body;

  @override
  State<TvPage> createState() => _TvPageState();
}

class _TvPageState extends State<TvPage> {
  final _tabs = FocusNode(debugLabel: 'tv page tabs', skipTraversal: true, canRequestFocus: false);
  final _body = FocusNode(debugLabel: 'tv page body', skipTraversal: true, canRequestFocus: false);

  @override
  void dispose() {
    _tabs.dispose();
    _body.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent || e.logicalKey != LogicalKeyboardKey.arrowUp || widget.tabs == null) return KeyEventResult.ignored;
    final current = FocusManager.instance.primaryFocus;
    if (current == null || current.context == null) return KeyEventResult.ignored;
    final inBody = [for (final n in _body.traversalDescendants) if (n != current && tvCanGo(n)) n];
    if (nearestInDirection(current.rect, TraversalDirection.up, inBody, levelOnly: false) != null) return KeyEventResult.ignored;
    return tvFocusFirstIn(_tabs) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(TvStyle.sideMargin, TvStyle.topMargin, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 44,
            child: Row(children: [
              Text(widget.title,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: Colors.white)),
              const SizedBox(width: 24),
              Expanded(
                child: widget.tabs == null
                    ? const SizedBox.shrink()
                    : Align(alignment: Alignment.centerLeft, child: Focus(focusNode: _tabs, child: widget.tabs!)),
              ),
              for (final a in widget.actions) Padding(padding: const EdgeInsets.only(left: 10), child: a),
            ]),
          ),
          const SizedBox(height: 10),
          Expanded(child: Focus(focusNode: _body, onKeyEvent: _key, child: widget.body)),
        ]),
      ),
    );
  }
}

/// A rounded button: [label], with an [icon] before it.
class TvButton extends StatelessWidget {
  const TvButton({super.key, required this.label, this.icon, required this.onPressed, this.primary = false, this.focusNode});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// The main button (Play): filled in the accent colour.
  final bool primary;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvPressable(
      onPressed: onPressed,
      focusNode: focusNode,
      semanticLabel: label,
      builder: (context, focused) {
        final bg = primary ? AppColors.accent : (focused ? Colors.white : AppColors.surfaceHigh);
        final fg = primary ? AppColors.current.onAccent : (focused ? const Color(0xFF101114) : AppColors.text);
        return TvFocusFrame(
          focused: focused,
          grow: false,
          radius: 999,
          child: Container(
            height: 36,
            color: bg,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
            ]),
          ),
        );
      },
    );
  }
}

/// The tabs along the top of a library screen. Moving onto a tab shows it after a short pause
/// (so passing over a tab doesn't), OK shows it at once; coming up from the page always lands on
/// the tab that's showing.
class TvTabBar extends StatefulWidget {
  const TvTabBar({super.key, required this.labels, required this.selected, required this.onSelect});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  /// How long a tab keeps focus before it's shown.
  static const settle = Duration(milliseconds: 300);

  @override
  State<TvTabBar> createState() => _TvTabBarState();
}

class _TvTabBarState extends State<TvTabBar> {
  late List<FocusNode> _nodes = _make();
  Timer? _timer;

  List<FocusNode> _make() => [for (final l in widget.labels) FocusNode(debugLabel: 'tab $l')];

  @override
  void didUpdateWidget(TvTabBar old) {
    super.didUpdateWidget(old);
    if (old.labels.length != widget.labels.length) {
      for (final n in _nodes) {
        n.dispose();
      }
      _nodes = _make();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _focused(int i, bool f) {
    if (!f) return;
    _timer?.cancel();
    _timer = Timer(TvTabBar.settle, () {
      if (mounted && _nodes[i].hasFocus && i != widget.selected) widget.onSelect(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // Coming in from outside: onto the tab that's showing, wherever the press came from.
      onFocusChange: (inside) {
        final sel = widget.selected.clamp(0, _nodes.length - 1);
        if (inside && !_nodes[sel].hasFocus) _nodes[sel].requestFocus();
      },
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < widget.labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TvPressable(
                key: ValueKey('tv-tab-${widget.labels[i]}'),
                focusNode: _nodes[i],
                semanticLabel: widget.labels[i],
                onPressed: () => widget.onSelect(i),
                onFocusChange: (f) => _focused(i, f),
                builder: (context, focused) {
                  final here = i == widget.selected;
                  return TvFocusFrame(
                    focused: focused,
                    grow: false,
                    radius: 999,
                    child: Container(
                      height: 32,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      color: here || focused ? const Color(0xFFF2F3F5) : AppColors.surface,
                      child: Text(widget.labels[i],
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: here ? FontWeight.w600 : FontWeight.w500,
                              color: here || focused ? const Color(0xFF101114) : AppColors.text.withValues(alpha: 0.85))),
                    ),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}

/// The A–Z strip. ↑ ↓ move to the letter before / after that has something under it (and the
/// grid jumps there); ← or OK go back into the grid at that letter.
class TvLetterStrip extends StatefulWidget {
  const TvLetterStrip({super.key, required this.available, required this.current, required this.onLetter, required this.onEnter});

  /// The letters with something under them; the others are dimmed and skipped.
  final Set<String> available;

  /// The letter of what has focus (in the grid or here).
  final String? current;
  final ValueChanged<String> onLetter;
  final VoidCallback onEnter;

  static const width = 24.0;

  @override
  State<TvLetterStrip> createState() => _TvLetterStripState();
}

class _TvLetterStripState extends State<TvLetterStrip> {
  bool _focused = false;

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft || tvActivateKeys.contains(k)) {
      if (e is KeyDownEvent) widget.onEnter();
      return KeyEventResult.handled;
    }
    final step = k == LogicalKeyboardKey.arrowDown ? 1 : (k == LogicalKeyboardKey.arrowUp ? -1 : 0);
    if (step == 0) return k == LogicalKeyboardKey.arrowRight ? KeyEventResult.handled : KeyEventResult.ignored;
    var i = tvLetters.indexOf(widget.current ?? '#');
    for (i += step; i >= 0 && i < tvLetters.length; i += step) {
      if (widget.available.contains(tvLetters[i])) {
        widget.onLetter(tvLetters[i]);
        return KeyEventResult.handled;
      }
    }
    // Past the first or last letter: the press goes on (↑ to the tabs).
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Jump to a letter',
      child: Focus(
        canRequestFocus: widget.available.isNotEmpty,
        onKeyEvent: _key,
        onFocusChange: (f) => setState(() => _focused = f),
        child: Container(
          width: TvLetterStrip.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: _focused ? AppColors.surface : Colors.transparent,
            border: _focused ? Border.all(color: AppColors.accent, width: 2) : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final l in tvLetters)
              Expanded(
                child: Center(
                  child: Container(
                    width: 20,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: l == widget.current && _focused ? AppColors.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: FittedBox(
                      child: Text(l,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: l == widget.current ? FontWeight.w700 : FontWeight.w400,
                              color: l == widget.current
                                  ? (_focused ? const Color(0xFF101114) : AppColors.accent)
                                  : widget.available.contains(l)
                                      ? AppColors.textDim
                                      : AppColors.textDim.withValues(alpha: 0.3))),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// A grid of tiles, or a list of rows ([columns] 1), with the A–Z strip at its right when
/// [letterOf] is given. Only the tiles near the screen are built, so big libraries stay quick.
class TvAzGrid<T> extends StatefulWidget {
  const TvAzGrid({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.letterOf,
    this.tileWidth = 132,
    this.itemHeight,
    this.aspectRatio = 1,
    this.subtitles = true,
    this.rowGap = 18,
    this.header,
  });

  final List<T> items;

  /// Draws one item at [width], with the focus node it must use.
  final Widget Function(BuildContext context, T item, int index, FocusNode node, double width) itemBuilder;

  /// The strip's letter for an item (null: no strip, for date and number orders).
  final String Function(T item)? letterOf;

  /// Tiles: about how wide each is (as many columns as fit). Ignored for a list.
  final double tileWidth;

  /// A list: each row's height (one column).
  final double? itemHeight;

  /// Tiles: the picture's width / height, and whether there's a line under the title.
  final double aspectRatio;
  final bool subtitles;
  final double rowGap;

  /// Something above the items that scrolls with them (Play and Shuffle on a page).
  final Widget? header;

  @override
  State<TvAzGrid<T>> createState() => _TvAzGridState<T>();
}

class _TvAzGridState<T> extends State<TvAzGrid<T>> {
  final _scroll = ScrollController();
  final _nodes = <int, FocusNode>{};
  int? _focusedIndex;
  String? _stripLetter;
  final _stripNode = FocusNode(debugLabel: 'A–Z strip');

  // Worked out in build, for jumps.
  int _columns = 1;
  double _rowExtent = 0, _headerExtent = 0;

  FocusNode _node(int i) => _nodes[i] ??= FocusNode(debugLabel: 'tv item $i');

  @override
  void didUpdateWidget(TvAzGrid<T> old) {
    super.didUpdateWidget(old);
    if (old.items.length != widget.items.length) {
      // Nodes beyond the end belong to nothing now.
      final gone = [for (final i in _nodes.keys) if (i >= widget.items.length) i];
      for (final i in gone) {
        _nodes.remove(i)!.dispose();
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _stripNode.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  String? _letterAt(int? i) =>
      (i == null || widget.letterOf == null || i >= widget.items.length) ? null : widget.letterOf!(widget.items[i]);

  int? _firstWith(String letter) {
    for (var i = 0; i < widget.items.length; i++) {
      if (widget.letterOf!(widget.items[i]) == letter) return i;
    }
    return null;
  }

  void _jumpTo(String letter) {
    final i = _firstWith(letter);
    if (i == null) return;
    setState(() {
      _stripLetter = letter;
      _focusedIndex = i;
    });
    if (_scroll.hasClients) {
      final row = i ~/ _columns;
      final at = (_headerExtent + row * _rowExtent - 8).clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.jumpTo(at);
    }
  }

  /// Back into the grid at the strip's letter. The tile is normally drawn already (the grid
  /// jumped there with the letter); if not, once the next frame has drawn it.
  void _enter() {
    final i = _focusedIndex ?? 0;
    bool go() {
      final n = _nodes[i];
      if (n == null || n.context == null || n.parent == null || !n.context!.mounted) return false;
      tvFocusOn(n, TraversalDirection.left);
      return true;
    }

    if (go()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) go();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    final strip = widget.letterOf != null && widget.items.length > 12;
    final scale = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, c) {
      const pad = 10.0;
      final width = c.maxWidth - (strip ? TvLetterStrip.width + 12 : 0) - 2 * pad;
      final list = widget.itemHeight != null;
      final gap = list ? 6.0 : widget.rowGap;
      _columns = list ? 1 : ((width + gap) / (widget.tileWidth + gap)).floor().clamp(1, 12);
      final tileW = (width - (_columns - 1) * gap) / _columns;
      final tileH = list
          ? widget.itemHeight!
          : tileW / widget.aspectRatio + 10 + scale.scale(19) + (widget.subtitles ? scale.scale(16) : 0) + 4;
      _rowExtent = tileH + gap;
      final available = widget.letterOf == null ? const <String>{} : {for (final x in widget.items) widget.letterOf!(x)};

      final grid = CustomScrollView(
        controller: _scroll,
        scrollCacheExtent: const ScrollCacheExtent.pixels(900),
        slivers: [
          if (widget.header != null) SliverToBoxAdapter(child: _HeaderMeasure(onHeight: (h) => _headerExtent = h, child: widget.header!)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(pad, pad, pad, 64),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _columns,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                mainAxisExtent: tileH,
              ),
              itemCount: widget.items.length,
              itemBuilder: (context, i) => Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (f) {
                  if (f && _focusedIndex != i) {
                    setState(() {
                      _focusedIndex = i;
                      _stripLetter = null;
                    });
                  }
                },
                child: Align(alignment: Alignment.topLeft, child: widget.itemBuilder(context, widget.items[i], i, _node(i), tileW)),
              ),
            ),
          ),
        ],
      );
      if (!strip) return grid;
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: grid),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 56),
          child: Focus(
            focusNode: _stripNode,
            canRequestFocus: false,
            skipTraversal: true,
            child: TvLetterStrip(
              available: available,
              current: _stripLetter ?? _letterAt(_focusedIndex) ?? (available.isEmpty ? null : tvLetters.firstWhere(available.contains)),
              onLetter: _jumpTo,
              onEnter: _enter,
            ),
          ),
        ),
      ]);
    });
  }
}

/// Reports its child's height after layout (the grid's header, for working out where a letter is).
class _HeaderMeasure extends SingleChildRenderObjectWidget {
  const _HeaderMeasure({required this.onHeight, required super.child});
  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeaderMeasure(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderHeaderMeasure r) => r.onHeight = onHeight;
}

class _RenderHeaderMeasure extends RenderProxyBox {
  _RenderHeaderMeasure(this.onHeight);
  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}

/// A heading with a row of tiles under it that scrolls sideways (Home's rows). The tiles are
/// all built (a row holds a few dozen at most), so → always has somewhere to go.
class TvShelf extends StatelessWidget {
  const TvShelf({super.key, required this.title, required this.children, this.gap = 18});
  final String title;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textDim)),
      const SizedBox(height: 4),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(6, 10, 40, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Each in a slot of its own, so the same thing twice in a row can't clash.
          for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(width: gap), KeyedSubtree(key: ValueKey(i), child: children[i])],
        ]),
      ),
    ]);
  }
}

/// A message in the middle of an empty tab, with an optional button.
class TvEmpty extends StatelessWidget {
  const TvEmpty({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: AppColors.textDim),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
          if (message != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: 460,
              child: Text(message!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textDim)),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ]),
      ),
    );
  }
}

/// A plain coloured square with an icon or a word on it (Liked Songs, a genre, a folder).
class TvColourPicture extends StatelessWidget {
  const TvColourPicture({super.key, required this.colour, this.icon, this.label});
  final Color colour;
  final IconData? icon;
  final String? label;

  /// A steady colour for [name] (a genre always gets the same one).
  static Color forName(String name) {
    const colours = [
      Color(0xFF3B5B7A), Color(0xFF7A4B3B), Color(0xFF4B6B4F), Color(0xFF6B4B7A), Color(0xFF7A6A3B),
      Color(0xFF3B6B6B), Color(0xFF5B4A3B), Color(0xFF4A3B5B), Color(0xFF3B4A5B), Color(0xFF5B3B4A),
    ];
    var h = 0;
    for (final c in name.toLowerCase().codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return colours[h % colours.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [colour, Color.lerp(colour, Colors.black, 0.45)!]),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10),
      child: label != null
          ? Text(label!, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white))
          : Icon(icon, size: 40, color: Colors.white.withValues(alpha: 0.9)),
    );
  }
}
