import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';
import '../../state/play_queue.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../screens/now_playing_screen.dart';
import '../screens/queue_screen.dart';
import '../theme.dart';
import 'artwork.dart';
import 'listening_controls.dart';

/// Seek bar with elapsed / total times. Rebuilds from the position stream only.
class SeekBar extends StatefulWidget {
  final bool compact;
  const SeekBar({super.key, this.compact = false});

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue; // while the user drags, ignore stream updates

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final total = player.duration;
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final maxMs = total.inMilliseconds.toDouble();
        final value = (_dragValue ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs <= 0 ? 1.0 : maxMs);
        final shown = Duration(milliseconds: value.round());
        final times = TextStyle(color: AppColors.textDim, fontSize: widget.compact ? 11 : 12);

        final slider = Slider(
          value: value,
          max: maxMs <= 0 ? 1.0 : maxMs,
          onChanged: maxMs <= 0 ? null : (v) => setState(() => _dragValue = v),
          onChangeEnd: (v) {
            player.seek(Duration(milliseconds: v.round()));
            setState(() => _dragValue = null);
          },
        );

        if (widget.compact) {
          return Row(children: [
            SizedBox(width: 44, child: Text(formatElapsed(shown), textAlign: TextAlign.right, style: times)),
            Expanded(child: slider),
            SizedBox(width: 44, child: Text(formatDuration(total), style: times)),
          ]);
        }
        return Column(children: [
          slider,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(formatElapsed(shown), style: times),
              Text(formatDuration(total), style: times),
            ]),
          ),
        ]);
      },
    );
  }
}

/// Music: Shuffle · Previous · Play/Pause · Next · Repeat · Sleep timer.
/// Books: Previous chapter · −15 · Play/Pause · +30 · Next chapter · Sleep timer.
class TransportControls extends StatelessWidget {
  final double playSize;
  const TransportControls({super.key, this.playSize = 64});

  Widget _playButton(PlayerModel p) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: playSize,
          height: playSize,
          child: IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            iconSize: playSize * 0.55,
            tooltip: p.playing ? 'Pause' : 'Play',
            icon: p.buffering && p.playing
                ? SizedBox(
                    width: playSize * 0.35,
                    height: playSize * 0.35,
                    child: const CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                  )
                : Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            onPressed: p.current == null ? null : p.togglePlay,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerModel>();
    final accent = Theme.of(context).colorScheme.primary;
    final repeatIcon = p.repeat == RepeatSetting.one ? Icons.repeat_one : Icons.repeat;
    final sleep = SleepTimerButton(iconSize: playSize < 50 ? 20 : 24);

    if (p.inBook) {
      final lib = context.watch<LibraryModel>();
      final skipSize = playSize * 0.5;
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          tooltip: 'Previous chapter',
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: p.previousChapter,
        ),
        IconButton(
          tooltip: 'Back ${lib.skipBackSeconds} seconds',
          icon: SkipIcon(seconds: lib.skipBackSeconds, forward: false, size: skipSize),
          onPressed: p.skipBack,
        ),
        _playButton(p),
        IconButton(
          tooltip: 'Forward ${lib.skipForwardSeconds} seconds',
          icon: SkipIcon(seconds: lib.skipForwardSeconds, forward: true, size: skipSize),
          onPressed: p.skipForward,
        ),
        IconButton(
          tooltip: 'Next chapter',
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: p.currentChapterIndex + 1 < p.chapters.length ? p.nextChapter : null,
        ),
        sleep,
      ]);
    }

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(
        tooltip: 'Shuffle',
        icon: Icon(Icons.shuffle, color: p.shuffle ? accent : null),
        onPressed: p.toggleShuffle,
      ),
      IconButton(
        tooltip: 'Previous',
        iconSize: playSize * 0.5,
        icon: const Icon(Icons.skip_previous_rounded),
        onPressed: p.current == null ? null : p.previous,
      ),
      _playButton(p),
      IconButton(
        tooltip: 'Next',
        iconSize: playSize * 0.5,
        icon: const Icon(Icons.skip_next_rounded),
        onPressed: p.current == null ? null : p.next,
      ),
      IconButton(
        tooltip: switch (p.repeat) {
          RepeatSetting.off => 'Repeat: off',
          RepeatSetting.all => 'Repeat: all',
          RepeatSetting.one => 'Repeat: one',
        },
        icon: Icon(repeatIcon, color: p.repeat == RepeatSetting.off ? null : accent),
        onPressed: p.cycleRepeat,
      ),
      sleep,
    ]);
  }
}

class LikeButton extends StatelessWidget {
  const LikeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final t = player.current;
    final pl = context.watch<PlaylistsModel>();
    // Audiobooks aren't liked like songs.
    if (t == null || player.inBook) return const SizedBox.shrink();
    final liked = pl.isLiked(t);
    return IconButton(
      tooltip: liked ? 'Remove from Liked Songs' : 'Like',
      icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
          color: liked ? Theme.of(context).colorScheme.primary : null),
      onPressed: () => pl.toggleLike(t),
    );
  }
}

void openNowPlaying(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    pageBuilder: (_, _, _) => const NowPlayingScreen(),
    transitionsBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ));
}

void openQueue(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const QueueScreen()));
}

/// Phone: compact bar above the bottom navigation. Tap to open Now Playing.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerModel>();
    final t = p.current;
    if (t == null) return const SizedBox.shrink();
    return Material(
      color: AppColors.surfaceHigh,
      child: InkWell(
        onTap: () => openNowPlaying(context),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
            child: Row(children: [
              Artwork(track: t, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
                ]),
              ),
              const LikeButton(),
              const SleepTimerButton(),
              IconButton(
                tooltip: p.playing ? 'Pause' : 'Play',
                icon: Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 32),
                onPressed: p.togglePlay,
              ),
            ]),
          ),
          _ThinProgress(),
        ]),
      ),
    );
  }
}

class _ThinProgress extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerModel>();
    return StreamBuilder<Duration>(
      stream: p.positionStream,
      initialData: p.position,
      builder: (context, snap) {
        final total = p.duration.inMilliseconds;
        final v = total <= 0 ? 0.0 : ((snap.data?.inMilliseconds ?? 0) / total).clamp(0.0, 1.0);
        return LinearProgressIndicator(value: v, minHeight: 2, color: Colors.white, backgroundColor: Colors.white12);
      },
    );
  }
}

/// Desktop / tablet: full-width bar along the bottom.
class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerModel>();
    final t = p.current;
    return Container(
      height: 88,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        // Left: now playing
        Expanded(
          flex: 3,
          child: t == null
              ? const SizedBox.shrink()
              : InkWell(
                  onTap: () => openNowPlaying(context),
                  child: Row(children: [
                    Artwork(track: t, size: 56),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
                        ],
                      ),
                    ),
                    const LikeButton(),
                  ]),
                ),
        ),
        // Middle: controls + seek
        Expanded(
          flex: 4,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const TransportControls(playSize: 40),
            if (t != null) const SeekBar(compact: true),
          ]),
        ),
        // Right: queue + volume
        Expanded(
          flex: 3,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (p.inBook) const SpeedButton(),
            if (p.inBook)
              IconButton(
                tooltip: 'Chapters',
                icon: const Icon(Icons.format_list_bulleted),
                onPressed: () => showChaptersSheet(context),
              ),
            IconButton(tooltip: 'Queue', icon: const Icon(Icons.queue_music), onPressed: () => openQueue(context)),
            const VolumeControl(),
          ]),
        ),
      ]),
    );
  }
}

/// Speaker icon + volume slider. Scrolling the mouse wheel over either turns
/// the volume up (wheel up) or down (wheel down); a two-finger swipe on a
/// touchpad works too.
class VolumeControl extends StatelessWidget {
  const VolumeControl({super.key});

  /// How much one notch of the wheel changes the volume (out of 100).
  static const wheelStep = 5.0;

  /// The volume after one wheel notch: scrolling down ([dy] > 0) turns it down.
  static double afterWheel(double volume, double dy) {
    if (dy == 0) return volume;
    return (volume + (dy > 0 ? -wheelStep : wheelStep)).clamp(0.0, 100.0);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerModel>();
    final volume = p.volume.clamp(0.0, 100.0);
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          // Claim the scroll so nothing behind the bar scrolls as well.
          GestureBinding.instance.pointerSignalResolver.register(event, (e) {
            final player = context.read<PlayerModel>();
            player.setVolume(afterWheel(player.volume, (e as PointerScrollEvent).scrollDelta.dy));
          });
        }
      },
      onPointerPanZoomUpdate: (event) {
        final player = context.read<PlayerModel>();
        player.setVolume((player.volume - event.panDelta.dy * 0.25).clamp(0.0, 100.0));
      },
      child: Tooltip(
        message: 'Volume ${volume.round()}% – scroll to change',
        waitDuration: const Duration(milliseconds: 800),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(volume == 0 ? Icons.volume_off : (volume < 50 ? Icons.volume_down : Icons.volume_up),
              size: 20, color: AppColors.textDim),
          SizedBox(
            width: 120,
            child: Slider(value: volume, max: 100, onChanged: p.setVolume),
          ),
        ]),
      ),
    );
  }
}
