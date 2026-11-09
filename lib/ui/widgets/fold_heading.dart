// A heading that folds up what's under it (9 Nov 2026, the user: "Make all headers, like
// Continue watching and Titles of Collections colapsable on all tabs"). Tap it (or its arrow) to
// fold or open. What's folded is remembered by a key while HomeTunes is open, so switching tabs
// or coming back to the page keeps it.
import 'package:flutter/material.dart';

import '../theme.dart';

/// Which headings are folded, by key ("videos.every:Continue watching").
abstract final class FoldedHeadings {
  static final Set<String> _folded = {};

  static bool isFolded(String key) => _folded.contains(key);

  static void toggle(String key) => _folded.contains(key) ? _folded.remove(key) : _folded.add(key);

  /// For tests: everything open again.
  @visibleForTesting
  static void openAll() => _folded.clear();
}

/// A section heading with an arrow; [onToggle] runs after the folded state changed (the page
/// redraws then). [count]: shown faintly after the text while folded ("Continue watching · 4").
class FoldHeading extends StatelessWidget {
  const FoldHeading({
    super.key,
    required this.foldKey,
    required this.text,
    required this.onToggle,
    this.count,
    this.padding = const EdgeInsets.fromLTRB(8, 12, 16, 0),
    this.onSecondaryTapUp,
    this.onLongPressStart,
  });

  final String foldKey;
  final String text;
  final VoidCallback onToggle;
  final int? count;
  final EdgeInsets padding;

  /// The heading's own menu (right-click / press and hold), kept as before.
  final GestureTapUpCallback? onSecondaryTapUp;
  final GestureLongPressStartCallback? onLongPressStart;

  @override
  Widget build(BuildContext context) {
    final folded = FoldedHeadings.isFolded(foldKey);
    return Padding(
      padding: padding,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: onSecondaryTapUp,
        onLongPressStart: onLongPressStart,
        child: InkWell(
          key: ValueKey('fold:$foldKey'),
          borderRadius: AppShape.circular(8),
          onTap: () {
            FoldedHeadings.toggle(foldKey);
            onToggle();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Tooltip(
                message: folded ? 'Open' : 'Fold up',
                child: AnimatedRotation(
                  turns: folded ? -0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Icons.expand_more, color: AppColors.textDim),
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              if (folded && count != null)
                Text('  ·  $count', style: TextStyle(fontSize: 14, color: AppColors.textDim)),
            ]),
          ),
        ),
      ),
    );
  }
}
