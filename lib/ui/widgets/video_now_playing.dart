// The bottom player bar and phone mini player while a video is the thing playing (30 Sep):
// the video's picture, title and collection (tap to go back to its page), skip back / play-pause
// / skip forward, its progress bar (drag, or the mouse wheel for 5 s steps) and its volume.
// Shown by DesktopPlayerBar / MiniPlayer when NowWatching.inFront; music takes the bar back as
// soon as it plays.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/now_watching.dart';
import '../theme.dart';
import 'wheel_seek.dart';

String _time(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

IconData _skipIcon(bool forward, int seconds) => switch ((forward, seconds)) {
  (false, 5) => Icons.replay_5,
  (false, 10) => Icons.replay_10,
  (false, 30) => Icons.replay_30,
  (true, 5) => Icons.forward_5,
  (true, 10) => Icons.forward_10,
  (true, 30) => Icons.forward_30,
  (false, _) => Icons.fast_rewind_rounded,
  (true, _) => Icons.fast_forward_rounded,
};

/// The video's picture, 16:9, or a film icon when there's none yet.
class _VideoThumb extends StatelessWidget {
  const _VideoThumb({required this.file, required this.height});
  final String? file;
  final double height;

  @override
  Widget build(BuildContext context) {
    final f = file;
    return ClipRRect(
      borderRadius: AppShape.circular(6),
      child: SizedBox(
        height: height,
        width: height * 16 / 9,
        child: f != null && File(f).existsSync()
            ? Image.file(File(f), fit: BoxFit.cover, cacheHeight: (height * 2).round())
            : ColoredBox(
                color: AppColors.surfaceHigh,
                child: Icon(Icons.movie_outlined, color: AppColors.textDim),
              ),
      ),
    );
  }
}

/// Title and "Collection · S1 E2".
class _VideoTitle extends StatelessWidget {
  const _VideoTitle(this.w);
  final NowWatching w;

  @override
  Widget build(BuildContext context) {
    final v = w.video!;
    final second = [v.collection, ?v.episodeLabel].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          v.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          second,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textDim, fontSize: 13),
        ),
      ],
    );
  }
}

/// The video's progress bar with times either side; drag to move, or the mouse wheel for 5 s.
class VideoSeekBar extends StatefulWidget {
  const VideoSeekBar({super.key});

  @override
  State<VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends State<VideoSeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final w = context.watch<NowWatching>();
    final total = w.duration;
    final times = TextStyle(color: AppColors.textDim, fontSize: 11);
    return WheelSeek(
      enabled: total > Duration.zero,
      position: () => w.position,
      duration: () => w.duration,
      onSeek: w.seek,
      child: StreamBuilder<Duration>(
        stream: w.positionStream,
        initialData: w.position,
        builder: (context, snap) {
          final maxMs = total.inMilliseconds.toDouble();
          final value = (_drag ?? (snap.data ?? Duration.zero).inMilliseconds.toDouble()).clamp(
            0.0,
            maxMs <= 0 ? 1.0 : maxMs,
          );
          return Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  _time(Duration(milliseconds: value.round())),
                  textAlign: TextAlign.right,
                  style: times,
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 32, // fits under the buttons in the 88 px bar on any screen density
                  child: Slider(
                    key: const ValueKey('video-bar-seek'),
                    value: value,
                    max: maxMs <= 0 ? 1.0 : maxMs,
                    onChanged: maxMs <= 0 ? null : (v) => setState(() => _drag = v),
                    onChangeEnd: (v) {
                      w.seek(Duration(milliseconds: v.round()));
                      setState(() => _drag = null);
                    },
                  ),
                ),
              ),
              SizedBox(width: 52, child: Text(_time(total), style: times)),
            ],
          );
        },
      ),
    );
  }
}

/// Skip back · play/pause · skip forward, for the video.
class VideoTransportControls extends StatelessWidget {
  const VideoTransportControls({super.key, this.playSize = 40});
  final double playSize;

  @override
  Widget build(BuildContext context) {
    final w = context.watch<NowWatching>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Back ${w.skipBackSeconds} seconds',
          icon: Icon(_skipIcon(false, w.skipBackSeconds)),
          onPressed: () => w.skip(forward: false),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            width: playSize,
            height: playSize,
            child: IconButton.filled(
              key: const ValueKey('video-bar-play'),
              style: IconButton.styleFrom(backgroundColor: AppColors.playButton, foregroundColor: AppColors.onPlay),
              iconSize: playSize * 0.55,
              tooltip: w.playing ? 'Pause' : 'Play',
              icon: Icon(w.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              onPressed: w.togglePlay,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Forward ${w.skipForwardSeconds} seconds',
          icon: Icon(_skipIcon(true, w.skipForwardSeconds)),
          onPressed: () => w.skip(forward: true),
        ),
      ],
    );
  }
}

/// The video's volume: speaker (mute / unmute) and a slider; the wheel over it changes it by 5.
class _VideoVolume extends StatefulWidget {
  const _VideoVolume();

  @override
  State<_VideoVolume> createState() => _VideoVolumeState();
}

class _VideoVolumeState extends State<_VideoVolume> {
  double _beforeMute = 100;

  @override
  Widget build(BuildContext context) {
    final w = context.watch<NowWatching>();
    final volume = w.volume.clamp(0.0, 100.0);
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          GestureBinding.instance.pointerSignalResolver.register(event, (e) {
            final dy = (e as PointerScrollEvent).scrollDelta.dy;
            if (dy != 0) w.setVolume(w.volume + (dy > 0 ? -5 : 5));
          });
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: volume <= 0 ? 'Unmute' : 'Mute',
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            color: volume <= 0 ? Theme.of(context).colorScheme.primary : AppColors.textDim,
            icon: Icon(volume <= 0 ? Icons.volume_off : (volume < 50 ? Icons.volume_down : Icons.volume_up)),
            onPressed: () {
              if (volume > 0) {
                _beforeMute = volume;
                w.setVolume(0);
              } else {
                w.setVolume(_beforeMute <= 0 ? 100 : _beforeMute);
              }
            },
          ),
          SizedBox(
            width: 120,
            child: Slider(value: volume, max: 100, onChanged: w.setVolume),
          ),
        ],
      ),
    );
  }
}

/// Desktop / tablet: the bottom bar while a video plays.
class VideoPlayerBar extends StatelessWidget {
  const VideoPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final w = context.watch<NowWatching>();
    return Container(
      key: const ValueKey('video-player-bar'),
      height: 88,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: w.onOpen,
              child: Row(
                children: [
                  _VideoThumb(file: w.picture, height: 50),
                  const SizedBox(width: 12),
                  Flexible(child: _VideoTitle(w)),
                ],
              ),
            ),
          ),
          const Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [VideoTransportControls(), VideoSeekBar()],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Go to the video',
                  icon: const Icon(Icons.smart_display_outlined),
                  onPressed: w.onOpen,
                ),
                const _VideoVolume(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Phone: the mini player while a video plays. Tap to go back to the video.
class VideoMiniPlayer extends StatelessWidget {
  const VideoMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final w = context.watch<NowWatching>();
    return Material(
      key: const ValueKey('video-mini-player'),
      color: AppColors.surfaceHigh,
      child: InkWell(
        onTap: w.onOpen,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
              child: Row(
                children: [
                  _VideoThumb(file: w.picture, height: 40),
                  const SizedBox(width: 12),
                  Expanded(child: _VideoTitle(w)),
                  IconButton(
                    tooltip: w.playing ? 'Pause' : 'Play',
                    icon: Icon(w.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 32),
                    onPressed: w.togglePlay,
                  ),
                ],
              ),
            ),
            StreamBuilder<Duration>(
              stream: w.positionStream,
              initialData: w.position,
              builder: (context, snap) {
                final total = w.duration.inMilliseconds;
                final v = total <= 0 ? 0.0 : ((snap.data?.inMilliseconds ?? 0) / total).clamp(0.0, 1.0);
                return LinearProgressIndicator(
                  value: v,
                  minHeight: 2,
                  color: AppColors.text,
                  backgroundColor: AppColors.faded(0.12),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
