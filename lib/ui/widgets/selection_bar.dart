// The bar shown while things are ticked (refactor phase 6, 9 Oct 2026): ✕ to clear, how many are
// selected, then the buttons for what's ticked. One bar for songs and for albums or audiobooks
// (shell.dart) and for videos (VideoSelectionBar, a collection's page and All videos); each passes
// the same buttons it showed before. Esc to cancel stays with the callers (EscapeCancels).
import 'package:flutter/material.dart';

class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.label,
    required this.onClear,
    required this.actions,
    this.verticalPadding = 2,
    this.safeArea = true,
    this.oneLine = true,
  });

  /// "3 selected", "2 albums selected".
  final String label;
  final VoidCallback onClear;

  /// The buttons after the label, in order.
  final List<Widget> actions;

  /// The songs bar and the videos bar use 2, the albums / audiobooks bar 4.
  final double verticalPadding;

  /// Keep clear of a phone's rounded corners and notch at the sides (the bars in the app frame).
  final bool safeArea;

  /// The label stays on one line, with "…" if it doesn't fit.
  final bool oneLine;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: verticalPadding),
      child: Row(children: [
        IconButton(tooltip: 'Clear selection', icon: const Icon(Icons.close), onPressed: onClear),
        Expanded(
          child: oneLine
              ? Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))
              : Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        ...actions,
      ]),
    );
    return Material(
      color: accent.withValues(alpha: 0.18),
      child: safeArea ? SafeArea(top: false, bottom: false, child: row) : row,
    );
  }
}
