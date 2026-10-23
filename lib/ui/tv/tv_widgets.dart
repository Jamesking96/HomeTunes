// The TV interface's building blocks (0.2.0, step 1 of the TV interface; mockups: "HomeTunes TV
// Interface", agreed 23 Oct). Every TV screen is made of these, so the remote behaves the same
// everywhere:
//  * [TvPressable]: anything the remote can press. OK presses it; holding OK (half a second)
//    is "hold" (the options panel, tv_options.dart). A mouse or a touch works too, for trying
//    TV mode on the PC: click, and right-click or a long press for hold.
//  * [TvFocusFrame]: whatever has focus grows a little and gets a thick ring in the accent
//    colour, with a gap between, so it shows over any picture.
//  * [TvTile] (a picture with a title under it: an album, a book, a video) and [TvRow] (one big
//    row: a song, an option, a setting), both pressable.
//  * [TvHints]: the small bubble saying what the remote's buttons do on this screen.
// The sizes are in the units the app lays out in; the TV is 960 x 540 of them.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'tv_focus.dart' show tvActivateKeys;

/// Sizes and timings shared by the TV screens.
abstract final class TvStyle {
  /// How long OK is held before it counts as "hold" rather than a press.
  static const holdDelay = Duration(milliseconds: 500);

  /// How much what has focus grows.
  static const focusScale = 1.06;

  /// The accent ring around what has focus, and the gap inside it.
  static const ringWidth = 3.0, ringGap = 3.0;

  static const animation = Duration(milliseconds: 140);

  /// Rounded corners of tiles and rows.
  static const radius = 12.0;

  /// The space kept clear at the screen's edges (TVs can crop them).
  static const sideMargin = 32.0, topMargin = 24.0;
}

/// Something the remote can press. [builder] draws it, told whether it has focus. With neither
/// [onPressed] nor [onHold] it can't take focus (the remote skips it).
class TvPressable extends StatefulWidget {
  const TvPressable({
    super.key,
    required this.builder,
    this.onPressed,
    this.onHold,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.semanticLabel,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onPressed;

  /// OK held, a right-click or a long press: the options for this thing.
  final VoidCallback? onHold;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final String? semanticLabel;

  @override
  State<TvPressable> createState() => _TvPressableState();
}

class _TvPressableState extends State<TvPressable> {
  FocusNode? _own;
  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode(debugLabel: 'TvPressable'));
  bool _focused = false;
  Timer? _holdTimer;
  bool _down = false, _held = false;

  bool get _enabled => widget.onPressed != null || widget.onHold != null;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _own?.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (!tvActivateKeys.contains(e.logicalKey) || !_enabled) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      _down = true;
      _held = false;
      _holdTimer?.cancel();
      if (widget.onHold != null) {
        _holdTimer = Timer(TvStyle.holdDelay, () {
          _held = true;
          widget.onHold?.call();
        });
      }
      return KeyEventResult.handled;
    }
    if (e is KeyRepeatEvent) return KeyEventResult.handled; // still held
    // Key up: a short press presses; after a hold, nothing more.
    _holdTimer?.cancel();
    if (_down && !_held) widget.onPressed?.call();
    _down = false;
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      enabled: _enabled,
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        canRequestFocus: _enabled,
        skipTraversal: !_enabled,
        onKeyEvent: _key,
        onFocusChange: (f) {
          if (!f) {
            _holdTimer?.cancel();
            _down = false;
          }
          setState(() => _focused = f);
          widget.onFocusChange?.call(f);
        },
        child: MouseRegion(
          cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            onLongPress: widget.onHold,
            onSecondaryTapUp: widget.onHold == null ? null : (TapUpDetails _) => widget.onHold!(),
            child: widget.builder(context, _focused),
          ),
        ),
      ),
    );
  }
}

/// The focus look: a little bigger, with an accent ring (and a gap in the background colour)
/// around [child]'s rounded box.
class TvFocusFrame extends StatelessWidget {
  const TvFocusFrame({super.key, required this.focused, required this.child, this.radius = TvStyle.radius, this.grow = true});

  final bool focused;
  final Widget child;
  final double radius;

  /// Grow when focused (tiles); rows only get the ring.
  final bool grow;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: focused && grow ? TvStyle.focusScale : 1.0,
      duration: TvStyle.animation,
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: TvStyle.animation,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: focused
              ? [
                  const BoxShadow(color: Color(0x8C000000), blurRadius: 24, offset: Offset(0, 10)),
                  BoxShadow(color: AppColors.accent, spreadRadius: TvStyle.ringGap + TvStyle.ringWidth),
                  BoxShadow(color: AppColors.bg, spreadRadius: TvStyle.ringGap),
                ]
              : const [],
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
      ),
    );
  }
}

/// A picture with a title (and a line under it): an album, a book, a video, a playlist.
class TvTile extends StatelessWidget {
  const TvTile({
    super.key,
    required this.picture,
    required this.title,
    this.subtitle,
    this.width = 124,
    this.aspectRatio = 1,
    this.onPressed,
    this.onHold,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.pictureRadius = TvStyle.radius,
  });

  final Widget picture;
  final String title;
  final String? subtitle;
  final double width;

  /// The picture's width / height (1: square covers; 16 / 9: videos; 2 / 3: posters).
  final double aspectRatio;
  final VoidCallback? onPressed, onHold;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;

  /// The picture's corners (half the width: a round artist picture).
  final double pictureRadius;

  @override
  Widget build(BuildContext context) {
    return TvPressable(
      onPressed: onPressed,
      onHold: onHold,
      focusNode: focusNode,
      autofocus: autofocus,
      onFocusChange: onFocusChange,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      builder: (context, focused) => SizedBox(
        width: width,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          TvFocusFrame(
            focused: focused,
            radius: pictureRadius,
            child: AspectRatio(aspectRatio: aspectRatio, child: picture),
          ),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: focused ? Colors.white : AppColors.text.withValues(alpha: 0.85))),
          if (subtitle != null)
            Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
        ]),
      ),
    );
  }
}

/// One big row: a song, an option, a setting. [trailing] sits at the right end (a value, a
/// length, a chevron).
class TvRow extends StatelessWidget {
  const TvRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onPressed,
    this.onHold,
    this.focusNode,
    this.autofocus = false,
    this.height = 52,
    this.background,
    this.onFocusChange,
  });

  final String title;
  final String? subtitle;
  final Widget? leading, trailing;
  final VoidCallback? onPressed, onHold;
  final FocusNode? focusNode;
  final bool autofocus;
  final double height;

  /// The row's colour when it hasn't focus (null: none, just the text).
  final Color? background;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    return TvPressable(
      onPressed: onPressed,
      onHold: onHold,
      focusNode: focusNode,
      autofocus: autofocus,
      onFocusChange: onFocusChange,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      builder: (context, focused) => TvFocusFrame(
        focused: focused,
        grow: false,
        child: AnimatedContainer(
          duration: TvStyle.animation,
          constraints: BoxConstraints(minHeight: height),
          color: focused ? AppColors.surfaceHigh : (background ?? Colors.transparent),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            if (leading != null) ...[
              IconTheme.merge(data: IconThemeData(size: 22, color: focused ? Colors.white : AppColors.textDim), child: leading!),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: focused ? FontWeight.w600 : FontWeight.w400, color: Colors.white)),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
              ]),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              DefaultTextStyle.merge(style: TextStyle(fontSize: 14, color: AppColors.textDim), child: trailing!),
            ],
          ]),
        ),
      ),
    );
  }
}

/// One hint in the bubble: the button ("OK", "Hold OK", "←") and what it does.
typedef TvHint = (String button, String does);

/// The small bubble saying what the remote's buttons do here.
class TvHints extends StatelessWidget {
  const TvHints(this.hints, {super.key});
  final List<TvHint> hints;

  /// The hints most screens show.
  static const browsing = <TvHint>[('OK', 'Open'), ('Hold OK', 'Options'), ('←', 'Menu')];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xDB0B0C0E),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.surfaceHigh),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < hints.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: Color(0xFFC9CDD4)), children: [
              TextSpan(text: hints[i].$1, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
              TextSpan(text: ' ${hints[i].$2}'),
            ])),
          ],
        ]),
      ),
    );
  }
}
