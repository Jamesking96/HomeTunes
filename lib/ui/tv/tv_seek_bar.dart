// The TV players' progress bar (0.2.0, step 5 of the TV interface; mockups "Now Playing" and
// "Video player"). No slider: with the bar in focus, ← → move a marker along it (further the
// longer the button is held); OK jumps there, or it jumps by itself once the remote rests for a
// moment; Back cancels (the page asks [TvSeekBarController.cancel]). With no marker out, OK does
// what the page says (play / pause). [preview] draws something above the marker: the video's
// picture at that spot.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'tv_focus.dart' show tvActivateKeys;

/// Lets the page see and drop the marker (Back cancels it before closing anything).
class TvSeekBarController extends ChangeNotifier {
  Duration? _target;

  /// Where the marker is (null: not moving through).
  Duration? get target => _target;
  bool get scrubbing => _target != null;

  void _set(Duration? t) {
    if (t == _target) return;
    _target = t;
    notifyListeners();
  }

  /// Puts the marker away without jumping.
  void cancel() => _set(null);
}

/// "3:05", or "1:02:10" for an hour or more.
String tvTime(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

class TvSeekBar extends StatefulWidget {
  const TvSeekBar({
    super.key,
    required this.position,
    required this.length,
    required this.positions,
    required this.onSeek,
    this.onActivate,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.preview,
    this.onMoved,
    this.onHold,
    this.light = false,
  });

  /// Where it's playing now, and how long it is.
  final Duration Function() position;
  final Duration Function() length;

  /// Ticks as it plays, so the bar moves.
  final Stream<Object?> positions;
  final ValueChanged<Duration> onSeek;

  /// OK with no marker out.
  final VoidCallback? onActivate;
  final TvSeekBarController? controller;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Drawn above the marker while moving through (the video's picture there).
  final Widget Function(Duration target, Duration length)? preview;

  /// Told about every press (the video player keeps its controls up meanwhile).
  final VoidCallback? onMoved;

  /// OK held for half a second (with no marker out): the player's options. Without it OK acts
  /// as soon as it's pressed.
  final VoidCallback? onHold;

  /// Over a picture: the times in white with a shadow.
  final bool light;

  /// How long the remote rests before it jumps to the marker.
  static const jumpAfter = Duration(milliseconds: 1500);

  /// How far one press moves in something [length] long: 10 s (a long video's 1/150th, if more),
  /// more the longer a key is held, at most a tenth of it. As the video page's remote version.
  static Duration step(Duration length, int streak) {
    var base = length ~/ 150;
    if (base < const Duration(seconds: 10)) base = const Duration(seconds: 10);
    final step = base * (1 + streak ~/ 3);
    final most = length ~/ 10;
    return most > const Duration(seconds: 10) && step > most ? most : step;
  }

  @override
  State<TvSeekBar> createState() => _TvSeekBarState();
}

class _TvSeekBarState extends State<TvSeekBar> {
  late TvSeekBarController _controller = widget.controller ?? TvSeekBarController();
  bool _ownController = true;
  Timer? _jumpTimer;
  Timer? _holdTimer;
  bool _okDown = false, _held = false;
  int _streak = 0;
  DateTime _lastPress = DateTime.fromMillisecondsSinceEpoch(0);
  bool _focused = false;
  late StreamSubscription<Object?> _sub;

  @override
  void initState() {
    super.initState();
    _ownController = widget.controller == null;
    _controller.addListener(_changed);
    _sub = widget.positions.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(TvSeekBar old) {
    super.didUpdateWidget(old);
    if (old.positions != widget.positions) {
      _sub.cancel();
      _sub = widget.positions.listen((_) {
        if (mounted) setState(() {});
      });
    }
    if (old.controller != widget.controller && widget.controller != null) {
      _controller.removeListener(_changed);
      if (_ownController) _controller.dispose();
      _controller = widget.controller!..addListener(_changed);
      _ownController = false;
    }
  }

  @override
  void dispose() {
    _jumpTimer?.cancel();
    _holdTimer?.cancel();
    _sub.cancel();
    _controller.removeListener(_changed);
    if (_ownController) _controller.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_controller.scrubbing) {
      _jumpTimer?.cancel();
      _streak = 0;
    }
    if (mounted) setState(() {});
  }

  void _jump() {
    _jumpTimer?.cancel();
    final to = _controller.target;
    if (to == null) return;
    widget.onSeek(to);
    _controller.cancel();
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) {
      // OK let go before it counted as held: a press.
      if (tvActivateKeys.contains(e.logicalKey) && _okDown) {
        _okDown = false;
        _holdTimer?.cancel();
        if (!_held) widget.onActivate?.call();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final back = k == LogicalKeyboardKey.arrowLeft;
    final ahead = k == LogicalKeyboardKey.arrowRight;
    final length = widget.length();
    if ((back || ahead) && length > Duration.zero) {
      widget.onMoved?.call();
      final now = DateTime.now();
      _streak = e is KeyRepeatEvent || now.difference(_lastPress) < const Duration(milliseconds: 700) ? _streak + 1 : 0;
      _lastPress = now;
      final from = _controller.target ?? widget.position();
      final step = TvSeekBar.step(length, _streak);
      var to = back ? from - step : from + step;
      if (to < Duration.zero) to = Duration.zero;
      if (to > length) to = length;
      _controller._set(to);
      _jumpTimer?.cancel();
      _jumpTimer = Timer(TvSeekBar.jumpAfter, _jump);
      return KeyEventResult.handled;
    }
    if (tvActivateKeys.contains(k)) {
      if (e is KeyRepeatEvent) return KeyEventResult.handled;
      widget.onMoved?.call();
      if (_controller.scrubbing) {
        _jump();
      } else if (widget.onHold == null) {
        widget.onActivate?.call();
      } else {
        // Wait: a short press plays / pauses when let go, a long one opens the options.
        _okDown = true;
        _held = false;
        _holdTimer?.cancel();
        _holdTimer = Timer(const Duration(milliseconds: 500), () {
          _held = true;
          widget.onHold?.call();
        });
      }
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) && _controller.scrubbing) {
      _controller.cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final length = widget.length();
    final at = widget.position();
    final target = _controller.target;
    double frac(Duration d) => length.inMilliseconds <= 0 ? 0 : (d.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0);
    final textStyle = TextStyle(
      fontSize: 13,
      color: widget.light ? Colors.white : AppColors.textDim,
      shadows: widget.light ? const [Shadow(blurRadius: 4, color: Colors.black)] : null,
    );
    return Semantics(
      slider: true,
      label: 'Position',
      value: '${tvTime(target ?? at)} of ${tvTime(length)}',
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onKeyEvent: _key,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (!f && _controller.scrubbing) _controller.cancel();
        },
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The marker's picture and time, above the bar.
                if (target != null)
                  SizedBox(
                    height: widget.preview == null ? 30 : 140,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: _within(w * frac(target) - (widget.preview == null ? 32 : 96), w - (widget.preview == null ? 64 : 192)),
                          bottom: 6,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.preview != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(width: 192, height: 108, child: widget.preview!(target, length)),
                                ),
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
                                child: Text(
                                  tvTime(target),
                                  key: const ValueKey('tv-seek-target'),
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.current.onAccent),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    color: _focused ? Colors.black.withValues(alpha: 0.28) : Colors.transparent,
                    border: Border.all(color: _focused ? AppColors.accent : Colors.transparent, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final tw = c.maxWidth;
                      return SizedBox(
                        height: 10,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 5,
                              decoration: BoxDecoration(color: const Color(0x66FFFFFF), borderRadius: BorderRadius.circular(3)),
                            ),
                            Container(
                              width: tw * frac(at),
                              height: 5,
                              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(3)),
                            ),
                            if (target != null)
                              Positioned(
                                left: _within(tw * frac(target) - 2, tw - 4),
                                child: Container(width: 4, height: 16, color: Colors.white),
                              )
                            else if (_focused)
                              Positioned(
                                left: _within(tw * frac(at) - 7, tw - 14),
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      Text(tvTime(at), style: textStyle),
                      const Spacer(),
                      Text(tvTime(length), style: textStyle),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// [x] kept between 0 and [most] (0 when there's no room).
double _within(double x, double most) => most <= 0 ? 0 : x.clamp(0.0, most);
