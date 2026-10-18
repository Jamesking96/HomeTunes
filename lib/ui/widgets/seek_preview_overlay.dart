// Seek preview (0.1.84): shows the picture and the time above a video's progress bar where the
// video would land. On a computer while the mouse is over the bar and while it's dragged; on a
// phone (and with a touchscreen) while a finger is on the bar. In full screen too: it wraps the
// player's controls, which full screen builds again.
//
// The progress bar is media_kit's own (MaterialDesktopSeekBar on a computer, MaterialSeekBar on a
// phone), so this doesn't change it: it finds the bar on screen, works out the spot under the
// pointer from the bar's own width, and only shows while the bar itself is showing (the controls
// fade away when the mouse or finger rests). The pictures come from services/seek_preview.dart.
// Settings › Videos › Preview when moving through a video turns it off.
//
// On a TV (0.2.0, TV mode) there's no pointer, so the bar gets a stand-in the remote can move to,
// laid over it: it has focus when the video opens. Left / Right (and ◀◀ / ▶▶) move a spot along
// the bar with its preview, faster while held; OK jumps there, or it jumps by itself once the
// remote rests; Back drops it. With no spot chosen, OK plays or pauses. Up / Down move to the
// player's buttons as usual. The stand-in draws its own bar while it has focus, as media_kit's
// fades away with the controls.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../services/seek_preview.dart';
import '../theme.dart' show AppColors;
import '../tv/tv_focus.dart' show tvActivateKeys, tvModeOf;

/// Whether [w] is one of media_kit's progress bars.
bool isMediaKitSeekBar(Widget w) => w is MaterialDesktopSeekBar || w is MaterialSeekBar;

/// "1:02:03" / "4:05".
String seekPreviewTime(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

class SeekPreviewOverlay extends StatefulWidget {
  const SeekPreviewOverlay({
    super.key,
    required this.previewer,
    required this.length,
    required this.child,
    this.enabled,
    this.aspect,
    this.isSeekBar = isMediaKitSeekBar,
    this.position,
    this.onSeek,
    this.onActivate,
    this.tv,
  });

  /// Where the pictures come from (null: times only, as in tests without one).
  final SeekPreviewer? previewer;

  /// The video's length now.
  final Duration Function() length;

  /// Whether previews are on (Settings › Videos), read each time. Null: always.
  final bool Function()? enabled;

  /// The picture's width ÷ height (null or unknown: 16:9).
  final double Function()? aspect;

  /// Which widget below is the progress bar (media_kit's, or a stand-in in tests). Its first
  /// LayoutBuilder is the track the spot is measured along.
  final bool Function(Widget) isSeekBar;

  /// TV mode: where the video is now, jumping to the chosen spot, and OK with no spot chosen
  /// (play / pause).
  final Duration Function()? position;
  final void Function(Duration to)? onSeek;
  final VoidCallback? onActivate;

  /// TV mode on or off (null: as the app is, Settings › Appearance › TV mode).
  final bool? tv;

  final Widget child;

  @override
  State<SeekPreviewOverlay> createState() => SeekPreviewOverlayState();
}

class SeekPreviewOverlayState extends State<SeekPreviewOverlay> {
  Element? _bar;

  /// The spot shown, where it is along the bar, and the top of the bar (this widget's own
  /// coordinates). Null spot: no preview.
  Duration? _at;
  double _x = 0, _barTop = 0;
  bool _dragging = false;

  /// The spot shown now (for tests).
  Duration? get shownAt => _at;

  // TV mode: the stand-in over the bar, where the bar is, the spot chosen with the remote, and
  // how many presses in a row (held keys go faster).
  final FocusNode _remote = FocusNode(debugLabel: 'seek bar');
  ({Rect bar, Rect track})? _tvBar;
  Duration? _target;
  Timer? _jumpTimer;
  int _streak = 0;
  DateTime _lastPress = DateTime.fromMillisecondsSinceEpoch(0);

  /// How long the remote rests before the video jumps to the chosen spot.
  static const jumpAfter = Duration(milliseconds: 1500);

  bool _tvOn(BuildContext context) => widget.tv ?? tvModeOf(context);

  @override
  void dispose() {
    _jumpTimer?.cancel();
    _remote.dispose();
    super.dispose();
  }

  /// How far one press moves in a video [length] long: 10 s (a long video's 1/150th, if more),
  /// more the longer a key is held, at most a tenth of the video.
  static Duration remoteStep(Duration length, int streak) {
    var base = length ~/ 150;
    if (base < const Duration(seconds: 10)) base = const Duration(seconds: 10);
    final step = base * (1 + streak ~/ 3);
    final most = length ~/ 10;
    return most > const Duration(seconds: 10) && step > most ? most : step;
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final back = k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind;
    final ahead = k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward;
    final length = widget.length();
    if ((back || ahead) && length > Duration.zero) {
      final now = DateTime.now();
      _streak = e is KeyRepeatEvent || now.difference(_lastPress) < const Duration(milliseconds: 700) ? _streak + 1 : 0;
      _lastPress = now;
      final from = _target ?? widget.position?.call() ?? Duration.zero;
      final step = remoteStep(length, _streak);
      var to = back ? from - step : from + step;
      if (to < Duration.zero) to = Duration.zero;
      if (to > length) to = length;
      _aimAt(to, length);
      _jumpTimer?.cancel();
      _jumpTimer = Timer(jumpAfter, _jump);
      return KeyEventResult.handled;
    }
    if (tvActivateKeys.contains(k)) {
      if (_target != null) {
        _jump();
      } else {
        widget.onActivate?.call();
      }
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) && _target != null) {
      _drop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _aimAt(Duration to, Duration length) {
    final w = _tvBar;
    if (w == null) return;
    final fraction = length.inMilliseconds <= 0 ? 0.0 : to.inMilliseconds / length.inMilliseconds;
    if (widget.enabled?.call() ?? true) widget.previewer?.request(to, length);
    setState(() {
      _target = to;
      _at = (widget.enabled?.call() ?? true) ? to : null;
      _x = w.track.left + w.track.width * fraction;
      _barTop = w.bar.top;
    });
  }

  void _jump() {
    _jumpTimer?.cancel();
    final to = _target;
    if (to == null) return;
    widget.onSeek?.call(to);
    _drop();
  }

  void _drop() {
    _jumpTimer?.cancel();
    _streak = 0;
    if (!mounted) return;
    setState(() {
      _target = null;
      _at = null;
    });
  }

  /// TV mode: keeps the stand-in where the bar is (whether or not the controls are showing). The
  /// first time it's placed (the video opening, or full screen) it takes focus, so the remote's
  /// ← → move through the video straight away.
  void _placeRemote() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tvOn(context)) return;
      final w = _where(evenHidden: true);
      if (w == null || (w.bar == _tvBar?.bar && w.track == _tvBar?.track)) return;
      final first = _tvBar == null;
      setState(() => _tvBar = w);
      if (first) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _remote.context != null) _remote.requestFocus();
        });
      }
    });
  }

  bool get _on => (widget.enabled?.call() ?? true) && widget.length() > Duration.zero;

  /// The progress bar's element, found again when it goes (a new video, full screen).
  Element? _findBar() {
    final cached = _bar;
    if (cached != null && cached.mounted) return cached;
    Element? found;
    void visit(Element e) {
      if (found != null) return;
      if (widget.isSeekBar(e.widget)) {
        found = e;
        return;
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return _bar = found;
  }

  /// Whether the bar is showing: not faded out with the rest of the controls, nor switched off.
  bool _showing(Element bar) {
    // (TV mode's stand-in lies over the bar but isn't part of it.)
    var shown = true;
    bar.visitAncestorElements((a) {
      if (identical(a, context)) return false;
      final w = a.widget;
      if ((w is AnimatedOpacity && w.opacity == 0) ||
          (w is Opacity && w.opacity == 0) ||
          (w is IgnorePointer && w.ignoring) ||
          (w is Offstage && w.offstage) ||
          (w is Visibility && !w.visible)) {
        shown = false;
      }
      return shown;
    });
    return shown;
  }

  /// The whole bar (what can be pointed at) and its track (what the spot is measured along), in
  /// this widget's coordinates, while the bar is showing ([evenHidden]: always, for TV mode).
  ({Rect bar, Rect track})? _where({bool evenHidden = false}) {
    final me = context.findRenderObject();
    final bar = _findBar();
    if (me is! RenderBox || !me.hasSize || bar == null || (!evenHidden && !_showing(bar))) return null;
    RenderBox? track;
    void visit(Element e) {
      if (track != null) return;
      if (e.widget is LayoutBuilder && e.renderObject is RenderBox) {
        track = e.renderObject as RenderBox;
        return;
      }
      e.visitChildren(visit);
    }

    bar.visitChildren(visit);
    final outer = bar.renderObject;
    if (outer is! RenderBox || !outer.hasSize || !outer.attached) return null;
    final along = track ?? outer;
    if (!along.hasSize || along.size.width <= 0) return null;
    Rect rect(RenderBox b) => me.globalToLocal(b.localToGlobal(Offset.zero)) & b.size;
    return (bar: rect(outer), track: rect(along));
  }

  void _show(Offset local, ({Rect bar, Rect track}) w) {
    final length = widget.length();
    final fraction = ((local.dx - w.track.left) / w.track.width).clamp(0.0, 1.0);
    final at = length * fraction;
    widget.previewer?.request(at, length);
    setState(() {
      _at = at;
      _x = w.track.left + w.track.width * fraction;
      _barTop = w.bar.top;
    });
  }

  void _hide() {
    if (_at != null) setState(() => _at = null);
  }

  void _hover(PointerHoverEvent e) {
    if (_dragging || e.kind != PointerDeviceKind.mouse) return;
    final w = _on ? _where() : null;
    if (w != null && w.bar.contains(e.localPosition)) {
      _show(e.localPosition, w);
    } else {
      _hide();
    }
  }

  void _down(PointerDownEvent e) {
    final w = _on ? _where() : null;
    if (w == null || !w.bar.contains(e.localPosition)) return;
    _dragging = true;
    _show(e.localPosition, w);
  }

  void _move(PointerMoveEvent e) {
    if (!_dragging) return;
    final w = _where();
    if (w == null) return _hide();
    _show(e.localPosition, w);
  }

  void _up(PointerEvent e) {
    if (!_dragging) return;
    _dragging = false;
    // A mouse still over the bar keeps its preview; a finger lifted ends it.
    final w = e.kind == PointerDeviceKind.mouse ? _where() : null;
    if (w == null || !w.bar.contains(e.localPosition)) _hide();
  }

  @override
  Widget build(BuildContext context) {
    final tv = _tvOn(context);
    if (tv) _placeRemote();
    return LayoutBuilder(builder: (context, box) {
      final at = _at;
      final remoteAt = _tvBar;
      return MouseRegion(
        opaque: false,
        hitTestBehavior: HitTestBehavior.translucent,
        onExit: (_) {
          if (!_dragging) _hide();
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerHover: _hover,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: widget.child),
            if (tv && remoteAt != null) _remoteBar(remoteAt),
            if (at != null) _preview(at, box),
          ]),
        ),
      );
    });
  }

  /// TV mode: the stand-in over the bar. With focus it shows its own bar: how far the video has
  /// got, or the spot chosen, in the accent colour.
  Widget _remoteBar(({Rect bar, Rect track}) w) {
    return Positioned.fromRect(
      rect: w.bar,
      child: Focus(
        key: const ValueKey('tv-seek-bar'),
        focusNode: _remote,
        onKeyEvent: _key,
        onFocusChange: (focused) {
          if (!focused) _drop();
          setState(() {});
        },
        child: !_remote.hasFocus
            ? const SizedBox.expand()
            : StreamBuilder<int>(
                // Redrawn while it has focus, so the bar follows the video.
                stream: Stream.periodic(const Duration(milliseconds: 500), (i) => i),
                builder: (context, _) {
                  final length = widget.length();
                  final at = _target ?? widget.position?.call() ?? Duration.zero;
                  final fraction =
                      length.inMilliseconds <= 0 ? 0.0 : (at.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0);
                  final left = w.track.left - w.bar.left, width = w.track.width;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.accent, width: 2),
                    ),
                    child: Stack(children: [
                      Positioned(
                        left: left,
                        width: width,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Container(height: 4, color: Colors.white38),
                        ),
                      ),
                      Positioned(
                        left: left,
                        width: width * fraction,
                        top: 0,
                        bottom: 0,
                        child: Center(child: Container(height: 4, color: AppColors.accent)),
                      ),
                      Positioned(
                        left: left + width * fraction - 8,
                        width: 16,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                          ),
                        ),
                      ),
                    ]),
                  );
                },
              ),
      ),
    );
  }

  Widget _preview(Duration at, BoxConstraints box) {
    // Bigger on a big screen, never more than a third of the picture's width.
    final wide = box.maxWidth.isFinite ? box.maxWidth : 800.0;
    final width = (wide >= 900 ? 200.0 : 160.0).clamp(96.0, wide / 3 < 96 ? 96.0 : wide / 3);
    final ratio = (widget.aspect?.call() ?? 16 / 9).clamp(0.5, 2.5);
    final left = (_x - width / 2).clamp(8.0, (wide - width - 8).clamp(8.0, double.infinity));
    final height = box.maxHeight.isFinite ? box.maxHeight : 0.0;
    final previewer = widget.previewer;
    return Positioned(
      key: const ValueKey('seek-preview'),
      left: left,
      width: width,
      bottom: height - _barTop + 2,
      child: IgnorePointer(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (previewer != null)
            Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white70, width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: ratio,
                child: ValueListenableBuilder<SeekFrame?>(
                  valueListenable: previewer.frame,
                  builder: (context, frame, _) {
                    // The picture for this spot if it's kept, else the newest one until it comes.
                    final picture = previewer.keptFor(at, widget.length()) ?? frame?.picture;
                    if (picture == null) return const SizedBox.expand();
                    return Image.memory(picture,
                        key: const ValueKey('seek-preview-picture'),
                        gaplessPlayback: true,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium);
                  },
                ),
              ),
            ),
          const SizedBox(height: 4),
          DecoratedBox(
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(seekPreviewTime(at),
                  key: const ValueKey('seek-preview-time'),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ),
        ]),
      ),
    );
  }
}
