// Shrink to fit small windows (0.1.41, user's request: "when scaling the window of the application
// down, the widgets/buttons should scale down a little bit", with a switch in Settings ›
// Appearance).
//
// On a computer, when the window is narrower than [WindowScale.fullWidth] (or shorter than
// [WindowScale.fullHeight]), the whole app is drawn a little smaller, down to [WindowScale.smallest]
// (80 %) at [WindowScale.smallWidth] / [WindowScale.smallHeight] and below. It's done once for the
// whole app (in MaterialApp.builder): the app is laid out as if the window were bigger by that
// much, then drawn scaled down, so every button, text and picture shrinks together and the mouse
// still lands where you click. Phones (and the switch off) are left as they are.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class WindowScale extends StatelessWidget {
  const WindowScale({super.key, required this.enabled, required this.child, this.desktop});

  /// Settings › Appearance › Shrink to fit small windows.
  final bool enabled;
  final Widget child;

  /// Whether this is a computer; null asks the platform (tests set it).
  final bool? desktop;

  /// At this size and above, everything is its usual size.
  static const fullWidth = 1200.0, fullHeight = 760.0;

  /// At this size and below, everything is at [smallest].
  static const smallWidth = 760.0, smallHeight = 520.0;
  static const smallest = 0.8;

  /// How big everything is drawn for a window of [size] (1.0 = usual size).
  static double factorFor(Size size) {
    double along(double v, double small, double full) =>
        v >= full ? 1.0 : (v <= small ? smallest : smallest + (1 - smallest) * (v - small) / (full - small));
    return math.min(along(size.width, smallWidth, fullWidth), along(size.height, smallHeight, fullHeight));
  }

  /// How squeezed a window is: 0 at [fullWidth] × [fullHeight] and above, 1 at [smallWidth] ×
  /// [smallHeight] and below.
  static double squeeze(Size window) => (1 - factorFor(window)) / (1 - smallest);

  // ---- a video in a small window (0.1.68, the user's request: "when the UI is scaled down and a
  // video is present, prioritise its size over text and controls; those scale down to a value
  // just small enough they are still usable") ----

  /// The smallest the text and buttons under a video are drawn on screen, all shrinking
  /// together: three quarters of their usual size (text about 10–11 px, buttons still easy to
  /// click with a mouse).
  static const smallestVideoInfo = 0.75;

  /// How much of the video page's height the video may take: 70 % in a big window, up to 85 %
  /// in the smallest.
  static double videoShare(Size window) => 0.7 + 0.15 * squeeze(window);

  /// How much smaller to draw the text and buttons under a video, on top of the whole app's own
  /// shrink ([appFactor], 1 when it isn't shrunk): together they reach [smallestVideoInfo] in
  /// the smallest windows.
  static double videoInfoScale(Size window, {double appFactor = 1}) {
    final target = 1 - (1 - smallestVideoInfo) * squeeze(window);
    return (target / appFactor).clamp(smallestVideoInfo, 1.0);
  }

  static bool get isDesktop => _isDesktop;
  static bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    if (!enabled || !(desktop ?? _isDesktop)) return child;
    final mq = MediaQuery.of(context);
    final factor = factorFor(mq.size);
    if (factor >= 0.999) return child;
    final laidOut = mq.size / factor;
    return MediaQuery(
      data: mq.copyWith(
        size: laidOut,
        padding: mq.padding / factor,
        viewPadding: mq.viewPadding / factor,
        viewInsets: mq.viewInsets / factor,
      ),
      // The bigger box goes outside the scaling (not inside it): a click is first checked against
      // the window, then turned into the bigger layout's position, so clicks near the right and
      // bottom edges still land (inside-out, they were thrown away as outside the window).
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: laidOut.width,
          maxWidth: laidOut.width,
          minHeight: laidOut.height,
          maxHeight: laidOut.height,
          child: Transform.scale(
            key: const ValueKey('window-scale'),
            scale: factor,
            alignment: Alignment.topLeft,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Draws [child] [scale] times its size, laid out as if it were that much wider, and takes up
/// only the space it's drawn in (so a shrunk section in a list leaves no gap). Clicks land where
/// they should. Used for the text and buttons under a video in a small window (0.1.68).
class ShrinkToWidth extends StatelessWidget {
  const ShrinkToWidth({super.key, required this.scale, required this.child});
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (scale >= 0.999) return child;
    return LayoutBuilder(
      builder: (context, box) => FittedBox(
        key: const ValueKey('shrink-to-width'),
        fit: BoxFit.fitWidth,
        alignment: Alignment.topLeft,
        child: SizedBox(width: box.maxWidth / scale, child: child),
      ),
    );
  }
}
