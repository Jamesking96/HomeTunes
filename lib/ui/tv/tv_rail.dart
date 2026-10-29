// The TV interface's menu (0.2.0, step 1): a slim rail of icons down the left edge (Home,
// Music, Audiobooks, Videos, Search, Settings, and what's playing at the bottom). When the
// remote moves onto it, it opens out with labels over the dimmed page; moving off closes it.
import 'package:flutter/material.dart';

import '../theme.dart';
import 'tv_focus.dart' show tvFocusOn;
import 'tv_widgets.dart';

/// One place on the rail.
class TvRailItem {
  const TvRailItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

class TvRail extends StatefulWidget {
  const TvRail({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    this.nowPlaying,
    this.nowPlayingLabel,
    this.onNowPlaying,
    this.onOpenChange,
  });

  final List<TvRailItem> items;

  /// Which item is the page on screen.
  final int selected;
  final ValueChanged<int> onSelect;

  /// The small picture of what's playing (null: nothing is), its label, and what pressing it does.
  final Widget? nowPlaying;
  final String? nowPlayingLabel;
  final VoidCallback? onNowPlaying;

  /// Told when the rail opens (the remote is on it) or closes.
  final ValueChanged<bool>? onOpenChange;

  static const width = 72.0, openWidth = 220.0;

  @override
  State<TvRail> createState() => TvRailState();
}

class TvRailState extends State<TvRail> {
  bool _open = false;
  late List<FocusNode> _nodes = _makeNodes();

  List<FocusNode> _makeNodes() => [for (final i in widget.items) FocusNode(debugLabel: 'rail ${i.label}')];

  /// Whether the remote is on the rail.
  bool get isOpen => _open;

  /// Moves the remote onto the item for the page on screen (Back from a page's top).
  void focusSelected() {
    final i = widget.selected.clamp(0, _nodes.length - 1);
    tvFocusOn(_nodes[i], TraversalDirection.left);
  }

  @override
  void didUpdateWidget(TvRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      for (final n in _nodes) {
        n.dispose();
      }
      _nodes = _makeNodes();
    }
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  Widget _item({required IconData? icon, Widget? picture, required String label, required bool here, required bool focused}) {
    return TvFocusFrame(
      focused: focused,
      grow: false,
      child: AnimatedContainer(
        duration: TvStyle.animation,
        height: 44,
        color: here ? AppColors.accent.withValues(alpha: 0.18) : (focused ? AppColors.surfaceHigh : Colors.transparent),
        child: Row(children: [
          SizedBox(
            width: 44,
            child: Center(
              child: picture ?? Icon(icon, size: 22, color: here ? AppColors.accent : (focused ? Colors.white : AppColors.textDim)),
            ),
          ),
          if (_open)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 6, right: 8),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: here ? AppColors.accent : (focused ? Colors.white : AppColors.text.withValues(alpha: 0.85)))),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (inside) {
        if (inside == _open) return;
        // Coming onto the rail from the page lands on the place showing, whichever item was
        // nearest (0.2.5: ← from Search's bottom row landed on Settings, ↑ from a collection's
        // Play on Music). What's playing, at the bottom, is reached with ↓ from there.
        if (inside) {
          final at = FocusManager.instance.primaryFocus;
          final here = _nodes[widget.selected.clamp(0, _nodes.length - 1)];
          if (at != here && _nodes.contains(at)) here.requestFocus();
        }
        setState(() => _open = inside);
        widget.onOpenChange?.call(inside);
      },
      child: AnimatedContainer(
        duration: TvStyle.animation,
        curve: Curves.easeOut,
        width: _open ? TvRail.openWidth : TvRail.width,
        decoration: BoxDecoration(
          color: const Color(0xFF0B0C0E),
          border: _open ? Border(right: BorderSide(color: AppColors.surfaceHigh)) : null,
        ),
        padding: const EdgeInsets.fromLTRB(14, 28, 14, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < widget.items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TvPressable(
                key: ValueKey('tv-rail-${widget.items[i].label}'),
                focusNode: _nodes[i],
                semanticLabel: widget.items[i].label,
                onPressed: () => widget.onSelect(i),
                builder: (context, focused) =>
                    _item(icon: widget.items[i].icon, label: widget.items[i].label, here: i == widget.selected, focused: focused),
              ),
            ),
          const Spacer(),
          if (widget.nowPlaying != null)
            TvPressable(
              key: const ValueKey('tv-rail-now-playing'),
              semanticLabel: widget.nowPlayingLabel ?? 'Now playing',
              onPressed: widget.onNowPlaying,
              builder: (context, focused) => _item(
                icon: null,
                picture: ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 36, height: 36, child: widget.nowPlaying)),
                label: widget.nowPlayingLabel ?? 'Now playing',
                here: false,
                focused: focused,
              ),
            ),
        ]),
      ),
    );
  }
}
