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
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../services/seek_preview.dart';

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
  /// this widget's coordinates, while the bar is showing.
  ({Rect bar, Rect track})? _where() {
    final me = context.findRenderObject();
    final bar = _findBar();
    if (me is! RenderBox || !me.hasSize || bar == null || !_showing(bar)) return null;
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
    return LayoutBuilder(builder: (context, box) {
      final at = _at;
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
            if (at != null) _preview(at, box),
          ]),
        ),
      );
    });
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
