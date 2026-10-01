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
