// Extra player controls, mostly for audiobooks: the sleep timer (moon) button, the "−15 / +30"
// skip icons, the speed button and speed chooser, and the chapter list.
//
// Used by the player bar, mini player and Now Playing (player_controls.dart and the Now
// Playing screen). The work itself happens in PlayerModel and SleepTimer; these widgets only
// show the state and pass on taps.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';
import '../../state/player_model.dart';
import '../../state/sleep_timer.dart';
import '../theme.dart';

/// The moon button beside play/pause: one tap starts the sleep timer with the
/// length from Settings, another tap stops it. Shows the time left while on.
/// Hidden when turned off in Settings > Sleep timer.
class SleepTimerButton extends StatelessWidget {
  final double iconSize;
  const SleepTimerButton({super.key, this.iconSize = 24});

  /// Timer length in words for the tooltip, e.g. "30 min" or "end of chapter".
  static String describe(int minutes, {required bool book}) {
    if (minutes == LibraryModel.sleepAtEnd) return book ? 'end of chapter' : 'end of song';
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    // select: rebuild only when these particular values change, not on every position tick.
    final shown = context.select<LibraryModel, bool>((l) => l.sleepButtonShown);
    final hasTrack = context.select<PlayerModel, bool>((p) => p.current != null);
    final inBook = context.select<PlayerModel, bool>((p) => p.inBook);
    final timer = context.watch<SleepTimer>();
    // Even with the button hidden in Settings, a running timer stays visible so it can be stopped.
    if (!shown && !timer.active) return const SizedBox.shrink();
    final accent = Theme.of(context).colorScheme.primary;
    final lib = context.read<LibraryModel>();
    final length = describe(inBook ? lib.sleepBookMinutes : lib.sleepMusicMinutes, book: inBook);

    // Off: a plain moon icon (disabled when nothing is loaded).
    if (!timer.active) {
      return IconButton(
        tooltip: 'Sleep timer ($length)',
        iconSize: iconSize,
        icon: const Icon(Icons.bedtime_outlined),
        onPressed: hasTrack ? timer.start : null,
      );
    }
    // On: an outlined pill with a filled moon and the time left; tapping it cancels.
    // (For "end of song/chapter" this is the time left in the song or chapter.)
    final left = timer.remaining ?? Duration.zero;
    return Tooltip(
      message: 'Sleep timer on – tap to turn off',
      child: TextButton.icon(
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

/// A circular arrow with the number of seconds in it (−15 / +30 …).
class SkipIcon extends StatelessWidget {
  final int seconds;
  final bool forward;
  final double size;

  /// The arrow's and number's colour (0.1.59: white over a music video); the icon colour if null.
  final Color? color;
  const SkipIcon({super.key, required this.seconds, required this.forward, this.size = 32, this.color});

  @override
  Widget build(BuildContext context) {
    // The "replay" arrow points backwards; mirrored it makes a forward arrow.
    final arrow = Icon(Icons.replay, size: size, color: color);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        forward ? Transform.flip(flipX: true, child: arrow) : arrow,
        Padding(
          padding: EdgeInsets.only(top: size * 0.12),
          child: Text('$seconds', style: TextStyle(fontSize: size * 0.28, fontWeight: FontWeight.w700, color: color)),
        ),
      ]),
    );
  }
}

/// "1.25×" button that opens the speed chooser.
class SpeedButton extends StatelessWidget {
  const SpeedButton({super.key});

  /// 1.25 -> "1.25×", 1.5 -> "1.5×", 1.0 -> "1.0×". Also used by Settings › Audiobooks.
  static String label(double s) {
    // Two decimals, then drop trailing zeros, but keep one zero after a bare point.
    final t = s.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '.0');
    return '$t×';
  }

  @override
  Widget build(BuildContext context) {
    final speed = context.select<PlayerModel, double>((p) => p.speed);
    return TextButton(
      style: TextButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 10)),
      onPressed: () => showSpeedSheet(context),
      child: Text(label(speed), style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

/// The speed chooser: a sheet of chips, one per speed in [PlayerModel.speeds].
Future<void> showSpeedSheet(BuildContext context) {
  final player = context.read<PlayerModel>();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Playback speed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            player.inBook ? 'Remembered for this book.' : 'Goes back to normal when a book starts or ends.',
            style: TextStyle(color: AppColors.textDim),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in PlayerModel.speeds)
              ChoiceChip(
                label: Text(SpeedButton.label(s)),
                // Compare with a small tolerance, as decimals aren't stored exactly.
                selected: (player.speed - s).abs() < 0.001,
                onSelected: (_) {
                  player.setSpeed(s);
                  Navigator.pop(ctx);
                },
              ),
          ]),
        ]),
      ),
    ),
  );
}

/// Chapter list in a sheet (Now Playing, while a book plays).
Future<void> showChaptersSheet(BuildContext context) {
  final player = context.read<PlayerModel>();
  // A snapshot taken when the sheet opens; it doesn't follow along while it's open.
  final chapters = player.chapters;
  final current = player.currentChapterIndex;
  final accent = Theme.of(context).colorScheme.primary;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, scroll) => ListView.builder(
        controller: scroll,
        itemCount: chapters.length,
        itemBuilder: (_, i) {
          final c = chapters[i];
          return ListTile(
            leading: SizedBox(
              width: 32,
              child: i == current
                  ? Icon(Icons.graphic_eq, color: accent, size: 20)
                  : Text('${i + 1}', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
            ),
            title: Text(c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: i == current ? accent : null)),
            // The chapter's length.
            trailing: Text(formatDuration(player.chapterEnd(i) - c.offset),
                style: TextStyle(color: AppColors.textDim)),
            onTap: () {
              Navigator.pop(ctx);
              player.goToChapter(i);
            },
          );
        },
      ),
    ),
  );
}
