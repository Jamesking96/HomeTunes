// The "Always on top" pin button (0.1.60): keeps the PC window above other windows, or not.
//
// The user wanted it always there and easy to click, shown the way each page needs, so it
// appears in several places (only on the PC, see services/window_pin.dart):
//   - at the right end of the player bar along the bottom (the desktop layout), or beside the
//     tab bar in a narrow window: on every tab, under any page;
//   - Now Playing and the Details pages, which cover the player bar: in their top bars;
//   - full-screen videos and music videos: a round button over the picture (round: true).
// A filled pin in the accent colour means it's on; an outline pin means it's off.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/window_pin.dart';
import '../../state/library_model.dart';

class AlwaysOnTopButton extends StatelessWidget {
  /// A round, see-through button for over a video (white pin) instead of a plain icon button.
  final bool round;
  const AlwaysOnTopButton({super.key, this.round = false});

  static String tooltipFor(bool on) =>
      on ? 'Always on top is on (click to turn it off)' : 'Keep HomeTunes on top of other windows';

  @override
  Widget build(BuildContext context) {
    if (!WindowPin.available) return const SizedBox.shrink();
    final lib = Provider.of<LibraryModel?>(context);
    if (lib == null) return const SizedBox.shrink();
    final on = lib.alwaysOnTop;
    final accent = Theme.of(context).colorScheme.primary;
    final button = IconButton(
      key: const ValueKey('always-on-top'),
      tooltip: tooltipFor(on),
      isSelected: on,
      color: round ? (on ? accent : Colors.white) : (on ? accent : null),
      icon: Icon(on ? Icons.push_pin : Icons.push_pin_outlined),
      onPressed: () => lib.setAlwaysOnTop(!on),
    );
    if (!round) return button;
    return Material(color: Colors.black54, shape: const CircleBorder(), child: button);
  }
}
