import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/play_queue.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../screens/now_playing_screen.dart';
import '../screens/queue_screen.dart';
import '../theme.dart';
import 'artwork.dart';

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
            SizedBox(width: 44, child: Text(formatDuration(shown), textAlign: TextAlign.right, style: times)),
            Expanded(child: slider),
            SizedBox(width: 44, child: Text(formatDuration(total), style: times)),
          ]);
        }
        return Column(children: [
          slider,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(formatDuration(shown), style: times),
              Text(formatDuration(total), style: times),
            ]),
          ),
        ]);
      },
    );
  }
}

/// Shuffle · Previous · Play/Pause · Next · Repeat.
class TransportControls extends StatelessWidget {
  final double playSize;
  const TransportControls({super.key, this.playSize = 64});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerModel>();
    final accent = Theme.of(context).colorScheme.primary;
    final repeatIcon = p.repeat == RepeatSetting.one ? Icons.repeat_one : Icons.repeat;
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
      Padding(
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
      ),
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
    ]);
  }
}

class LikeButton extends StatelessWidget {
  const LikeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<PlayerModel>().current;
    final pl = context.watch<PlaylistsModel>();
    if (t == null) return const SizedBox.shrink();
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
            IconButton(tooltip: 'Queue', icon: const Icon(Icons.queue_music), onPressed: () => openQueue(context)),
            Icon(p.volume == 0 ? Icons.volume_off : Icons.volume_up, size: 20, color: AppColors.textDim),
            SizedBox(
              width: 120,
              child: Slider(value: p.volume.clamp(0.0, 100.0), max: 100, onChanged: p.setVolume),
            ),
          ]),
        ),
      ]),
    );
  }
}
