// Scroll to skip (30 Sep): with the mouse over a progress bar (songs, audiobooks, videos), a
// wheel notch up skips forward 5 seconds and a notch down goes back 5. Only while the pointer is
// over the bar, so scrolling the page elsewhere still scrolls. A two-finger touchpad swipe works
// too (one step for every [WheelSeek.panPerStep] pixels).
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// How far one wheel notch skips.
const wheelSeekStep = Duration(seconds: 5);

/// Where one notch goes from [from]: up ([dy] < 0) is forward, down is back; kept inside the
/// file ([length] 0 = not known yet, so only the start is a limit). Null for no movement.
Duration? wheelSeekTarget(Duration from, Duration length, double dy) {
  if (dy == 0) return null;
  var to = dy < 0 ? from + wheelSeekStep : from - wheelSeekStep;
  if (to < Duration.zero) to = Duration.zero;
  if (length > Duration.zero && to > length) to = length;
  return to;
}

/// Wraps a progress bar so the mouse wheel over it skips back / forward 5 s.
class WheelSeek extends StatefulWidget {
  const WheelSeek({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.child,
    this.enabled = true,
  });

  /// The place and length now (read when the wheel turns).
  final Duration Function() position;
  final Duration Function() duration;
  final void Function(Duration to) onSeek;
  final Widget child;
  final bool enabled;

  /// Touchpad: pixels of two-finger movement per 5 s step.
  static const panPerStep = 40.0;

  @override
  State<WheelSeek> createState() => _WheelSeekState();
}

class _WheelSeekState extends State<WheelSeek> {
  // Several quick notches add up from where the last one went, not from a position the player
  // hasn't caught up with yet.
  Duration? _lastTarget;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _pan = 0;

  void _step(double dy) {
    final now = DateTime.now();
    final from = _lastTarget != null && now.difference(_lastAt) < const Duration(milliseconds: 700)
        ? _lastTarget!
        : widget.position();
    final to = wheelSeekTarget(from, widget.duration(), dy);
    if (to == null) return;
    _lastTarget = to;
    _lastAt = now;
    widget.onSeek(to);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          // Claim the scroll so the page behind doesn't scroll as well.
          GestureBinding.instance.pointerSignalResolver.register(
            event,
            (e) => _step((e as PointerScrollEvent).scrollDelta.dy),
          );
        }
      },
      onPointerPanZoomStart: (_) => _pan = 0,
      onPointerPanZoomUpdate: (event) {
        _pan += event.panDelta.dy;
        while (_pan.abs() >= WheelSeek.panPerStep) {
          // Fingers moving up (negative) go forward, like the wheel.
          _step(_pan < 0 ? -1 : 1);
          _pan += _pan < 0 ? WheelSeek.panPerStep : -WheelSeek.panPerStep;
        }
      },
      child: widget.child,
    );
  }
}
