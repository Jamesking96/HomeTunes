// The moon button for videos (0.1.63): starts and stops the video sleep timer
// (state/video_sleep_timer.dart), like the music's SleepTimerButton. Off, it's a moon icon; on,
// a pill with a filled moon and the time left, and a tap turns it off.
//
// It's in the video player's own controls (computer and phone, normal and full screen, in the
// chosen button colour) and in the bottom bar while a video plays. Settings › Sleep timer's
// "Show sleep timer button" hides it too, except while a timer is running.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';
import '../../state/video_sleep_timer.dart';
import '../theme.dart';
import 'listening_controls.dart' show SleepTimerButton;

class VideoSleepTimerButton extends StatelessWidget {
  /// The icon's size and colour (the video player's look; the theme's when null).
  final double iconSize;
  final Color? color;
  const VideoSleepTimerButton({super.key, this.iconSize = 24, this.color});

  /// The tooltip's length in words: "30 min" or "end of video".
  static String describe(int minutes) => minutes == LibraryModel.sleepAtEnd || minutes <= 0
      ? 'end of video'
      : SleepTimerButton.describe(minutes, book: false);

  @override
  Widget build(BuildContext context) {
    final timer = Provider.of<VideoSleepTimer?>(context);
    final lib = Provider.of<LibraryModel?>(context);
    if (timer == null || lib == null) return const SizedBox.shrink();
    if (!lib.sleepButtonShown && !timer.active) return const SizedBox.shrink();
    if (!timer.active) {
      return IconButton(
        key: const ValueKey('video-sleep-timer'),
        tooltip: 'Sleep timer (${describe(lib.sleepVideoMinutes)})',
        iconSize: iconSize,
        color: color,
        icon: const Icon(Icons.bedtime_outlined),
        onPressed: timer.start,
      );
    }
    final accent = Theme.of(context).colorScheme.primary;
    final left = timer.remaining ?? Duration.zero;
    return Tooltip(
      message: 'Sleep timer on - tap to turn off',
      child: TextButton.icon(
        key: const ValueKey('video-sleep-timer-on'),
        style: TextButton.styleFrom(
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 36),
          shape: StadiumBorder(side: BorderSide(color: accent.withValues(alpha: 0.6))),
        ),
        icon: Icon(Icons.bedtime, size: iconSize * 0.8),
        label: Text(formatElapsed(left), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
        onPressed: timer.cancel,
      ),
    );
  }
}
