import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';
import '../../state/player_model.dart';
import '../../state/sleep_timer.dart';
import '../theme.dart';

/// The moon button beside play/pause: one tap starts the sleep timer with the
/// length from Settings, another tap stops it. Shows the time left while on.
/// Hidden when turned off in Settings > Audiobooks.
class SleepTimerButton extends StatelessWidget {
  final double iconSize;
  const SleepTimerButton({super.key, this.iconSize = 24});

  static String describe(int minutes, {required bool book}) {
    if (minutes == LibraryModel.sleepAtEnd) return book ? 'end of chapter' : 'end of song';
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final shown = context.select<LibraryModel, bool>((l) => l.sleepButtonShown);
    final hasTrack = context.select<PlayerModel, bool>((p) => p.current != null);
    final inBook = context.select<PlayerModel, bool>((p) => p.inBook);
    final timer = context.watch<SleepTimer>();
    if (!shown && !timer.active) return const SizedBox.shrink();
    final accent = Theme.of(context).colorScheme.primary;
    final lib = context.read<LibraryModel>();
    final length = describe(inBook ? lib.sleepBookMinutes : lib.sleepMusicMinutes, book: inBook);

    if (!timer.active) {
      return IconButton(
        tooltip: 'Sleep timer ($length)',
        iconSize: iconSize,
        icon: const Icon(Icons.bedtime_outlined),
        onPressed: hasTrack ? timer.start : null,
      );
    }
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
  const SkipIcon({super.key, required this.seconds, required this.forward, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final arrow = Icon(Icons.replay, size: size);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        forward ? Transform.flip(flipX: true, child: arrow) : arrow,
        Padding(
          padding: EdgeInsets.only(top: size * 0.12),
          child: Text('$seconds', style: TextStyle(fontSize: size * 0.28, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// "1.25×" button that opens the speed chooser.
class SpeedButton extends StatelessWidget {
  const SpeedButton({super.key});

  static String label(double s) {
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
            style: const TextStyle(color: AppColors.textDim),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in PlayerModel.speeds)
              ChoiceChip(
                label: Text(SpeedButton.label(s)),
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
                  : Text('${i + 1}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textDim)),
            ),
            title: Text(c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: i == current ? accent : null)),
            trailing: Text(formatDuration(player.chapterEnd(i) - c.offset),
                style: const TextStyle(color: AppColors.textDim)),
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
