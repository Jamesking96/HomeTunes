// The volume slider with a percentage bubble (0.1.65, the user's request: "show what % it is on
// above the volume slider", only while adjusting, can be turned off in Settings › Playback).
//
// While the slider is dragged, or the volume changes some other way (the mouse wheel, a
// touchpad swipe, the mute button, the keyboard on a video), a small "65%" bubble sits above the
// slider's handle; it goes a second after the last change. It's drawn in the app's overlay, so a
// small pop-up (the phone's volume button) or the video controls can't cut it off.
// Used by every volume slider: the player bar, Now Playing and the phone pop-up (VolumeControl),
// the bottom bar while a video plays, and the video player's own bar.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';

class VolumeSlider extends StatefulWidget {
  const VolumeSlider({super.key, required this.value, required this.max, required this.onChanged, this.sliderKey});

  /// The volume on the sliders' scale: 0 to 100, or up to the volume boost's top.
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  /// The key for the slider itself (tests find the volume sliders by it).
  final Key? sliderKey;

  /// How long the bubble stays after the last change.
  static const showFor = Duration(seconds: 1);

  @override
  State<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<VolumeSlider> {
  final _bubble = OverlayPortalController();
  final _link = LayerLink();
  Timer? _hide;
  bool _dragging = false;
  double _width = 0;
  double _pad = 20;

  bool get _wanted => context.read<LibraryModel?>()?.showVolumePercent ?? true;

  /// Shows the bubble; it hides itself [VolumeSlider.showFor] after the last change, unless the
  /// slider is still held.
  void _flash() {
    if (!mounted) return;
    if (!_wanted) {
      if (_bubble.isShowing) _bubble.hide();
      return;
    }
    _bubble.show();
    _hide?.cancel();
    if (!_dragging) {
      _hide = Timer(VolumeSlider.showFor, () {
        if (mounted && _bubble.isShowing) _bubble.hide();
      });
    }
  }

  @override
  void didUpdateWidget(VolumeSlider old) {
    super.didUpdateWidget(old);
    // Changed from outside the slider (wheel, mute, keys): show it too. After this frame, so the
    // bubble isn't changed in the middle of building.
    if (old.value.round() != widget.value.round()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _flash());
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Turned off in Settings: take any bubble away.
    final wanted = context.select<LibraryModel?, bool>((l) => l?.showVolumePercent ?? true);
    if (!wanted && _bubble.isShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _bubble.isShowing) _bubble.hide();
      });
    }
    // Where the track starts and ends inside the slider: the larger of the handle and its
    // glow, as the slider itself works it out.
    final theme = SliderTheme.of(context);
    final thumb = (theme.thumbShape?.getPreferredSize(true, false).width ?? 20) / 2;
    final glow = (theme.overlayShape?.getPreferredSize(true, false).width ?? 40) / 2;
    _pad = math.max(thumb, glow);

    return OverlayPortal(
      controller: _bubble,
      overlayChildBuilder: _buildBubble,
      child: CompositedTransformTarget(
        link: _link,
        child: LayoutBuilder(builder: (context, box) {
          _width = box.maxWidth.isFinite ? box.maxWidth : 0;
          return Slider(
            key: widget.sliderKey,
            value: widget.value.clamp(0.0, widget.max),
            max: widget.max,
            onChangeStart: (_) {
              _dragging = true;
              _flash();
            },
            onChanged: (v) {
              widget.onChanged(v);
              _flash();
            },
            onChangeEnd: (_) {
              _dragging = false;
              _flash();
            },
          );
        }),
      ),
    );
  }

  Widget _buildBubble(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = widget.max <= 0 ? 0.0 : (widget.value / widget.max).clamp(0.0, 1.0);
    final track = math.max(0.0, _width - 2 * _pad);
    final x = _width <= 0 ? 0.0 : _pad + fraction * track;
    return Positioned(
      left: 0,
      top: 0,
      child: IgnorePointer(
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomCenter,
          // A little into the slider's box, so the bubble sits just over the handle.
          offset: Offset(x, 10),
          child: Material(
            key: const ValueKey('volume-percent'),
            color: scheme.primary,
            elevation: 2,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Text(
                '${widget.value.round()}%',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
