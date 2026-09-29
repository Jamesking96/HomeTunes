// The player's buttons and bars: seek bar, play/pause row, like button, the phone mini player,
// the desktop player bar along the bottom, and the volume control (a slider in the desktop bar
// and Now Playing, a speaker button with a pop-up slider in the mini player).
//
// Shell puts MiniPlayer (phones) or DesktopPlayerBar (wide windows) under the pages; Now
// Playing reuses SeekBar and TransportControls at a bigger size. Everything reads from
// PlayerModel. When a book is playing the controls switch to book mode (chapters, skip back /
// forward, speed) instead of shuffle / repeat.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  /// Small version with the times either side of the bar (desktop player bar).
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
    final total = player.duration; // the length of the file playing now
    // The position arrives many times a second; only this StreamBuilder redraws for it.
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final maxMs = total.inMilliseconds.toDouble();
        // While the length is unknown (0), use a dummy range of 1 so the Slider doesn't complain,
        // and disable dragging.
        final value = (_dragValue ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs <= 0 ? 1.0 : maxMs);
        final shown = Duration(milliseconds: value.round());
        final times = TextStyle(color: AppColors.textDim, fontSize: widget.compact ? 11 : 12);

        final slider = Slider(
          value: value,
          max: maxMs <= 0 ? 1.0 : maxMs,
          onChanged: maxMs <= 0 ? null : (v) => setState(() => _dragValue = v),
          // Only seek once the drag ends, not on every movement.
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
  /// Size of the round play button; the other buttons scale from it.
  final double playSize;
  const TransportControls({super.key, this.playSize = 64});

  /// The big white round play/pause button (shows a spinner while loading/buffering).
  Widget _playButton(PlayerModel p) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: playSize,
          height: playSize,
          child: IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: AppColors.playButton, foregroundColor: AppColors.onPlay),
            iconSize: playSize * 0.55,
            tooltip: p.playing ? 'Pause' : 'Play',
            icon: p.buffering && p.playing
                ? SizedBox(
                    width: playSize * 0.35,
                    height: playSize * 0.35,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPlay),
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

    // Book mode: chapter and skip buttons. The skip amounts come from Settings › Audiobooks.
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

    // Music mode. Shuffle and repeat light up in the accent colour when on.
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
        onPressed: p.cycleRepeat, // off -> all -> one -> off
      ),
      sleep,
    ]);
  }
}

/// Heart button for the song playing now (adds it to / removes it from Liked Songs).
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

/// Opens the full-screen Now Playing page, sliding up from the bottom. [lyrics] true opens it
/// on the lyrics (null keeps whatever was chosen last).
/// It's pushed on the root navigator so it covers the tabs and the player bar.
void openNowPlaying(BuildContext context, {bool? lyrics}) {
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    pageBuilder: (_, _, _) => NowPlayingScreen(showLyrics: lyrics),
    transitionsBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ));
}

/// Opens the play queue as a drawer from the right, above everything like Now Playing.
void openQueue(BuildContext context) => openQueueDrawer(context); // a side drawer since 0.1.26

/// Phone: compact bar above the bottom navigation. Tap to open Now Playing.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerModel>();
    final t = p.current;
    // Nothing loaded: no mini player at all.
    if (t == null) return const SizedBox.shrink();
    // Swipe left / right for the next / previous song, or to skip in a book (0.1.17).
    return PlayerSwipe(child: Material(
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
                      style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ]),
              ),
              const LikeButton(),
              const SleepTimerButton(),
              const VolumeButton(),
              IconButton(
                tooltip: p.playing ? 'Pause' : 'Play',
                icon: Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 32),
                onPressed: p.togglePlay,
              ),
            ]),
          ),
          // A hairline progress bar along the bottom edge.
          _ThinProgress(),
        ]),
      ),
    ));
  }
}

/// Swipe-to-skip on the player (0.1.17), wired to [PlayerModel.swipe] and the "Swipe to skip"
/// setting. In an audiobook a short message says how far it skipped.
class PlayerSwipe extends StatelessWidget {
  final Widget child;
  const PlayerSwipe({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<LibraryModel, bool>((l) => l.swipeToSkip);
    void go(bool forward) {
      final p = context.read<PlayerModel>();
      final lib = context.read<LibraryModel>();
      final inBook = p.inBook;
      p.swipe(forward: forward);
      if (inBook) {
        final seconds = forward ? lib.skipForwardSeconds : lib.skipBackSeconds;
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(forward ? 'Forward $seconds s' : 'Back $seconds s'),
            duration: const Duration(milliseconds: 900),
          ));
      }
    }

    return SwipeToSkip(
      enabled: enabled,
      onForward: () => go(true),
      onBack: () => go(false),
      child: child,
    );
  }
}

/// Calls [onForward] when [child] is swiped to the left and [onBack] when it's swiped to the
/// right, with a light tap of haptic feedback. Only touch (and stylus) swipes count, so dragging
/// with a mouse on a PC does nothing, and a swipe has to be quick or long enough to be meant.
/// Taps still reach [child].
class SwipeToSkip extends StatefulWidget {
  final Widget child;
  final VoidCallback onForward;
  final VoidCallback onBack;
  final bool enabled;
  const SwipeToSkip({super.key, required this.child, required this.onForward, required this.onBack, this.enabled = true});

  /// A swipe counts when it's at least this fast (logical pixels a second)…
  static const minVelocity = 300.0;

  /// …or at least this long.
  static const minDistance = 80.0;

  @override
  State<SwipeToSkip> createState() => _SwipeToSkipState();
}

class _SwipeToSkipState extends State<SwipeToSkip> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return GestureDetector(
      supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus},
      onHorizontalDragStart: (_) => _dx = 0,
      onHorizontalDragUpdate: (d) => _dx += d.delta.dx,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        final forward = v <= -SwipeToSkip.minVelocity || (v.abs() < SwipeToSkip.minVelocity && _dx <= -SwipeToSkip.minDistance);
        final back = v >= SwipeToSkip.minVelocity || (v.abs() < SwipeToSkip.minVelocity && _dx >= SwipeToSkip.minDistance);
        if (!forward && !back) return;
        HapticFeedback.selectionClick();
        forward ? widget.onForward() : widget.onBack();
      },
      child: widget.child,
    );
  }
}

/// The mini player's thin progress line; like SeekBar, only it redraws on position updates.
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
        return LinearProgressIndicator(value: v, minHeight: 2, color: AppColors.text, backgroundColor: AppColors.faded(0.12));
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
                              style: TextStyle(color: AppColors.textDim, fontSize: 13)),
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
            // Books get speed and chapters; songs get a lyrics button.
            if (p.inBook) const SpeedButton(),
            if (p.inBook)
              IconButton(
                tooltip: 'Chapters',
                icon: const Icon(Icons.format_list_bulleted),
                onPressed: () => showChaptersSheet(context),
              ),
            if (t != null && !p.inBook)
              IconButton(
                tooltip: 'Lyrics',
                icon: const Icon(Icons.lyrics_outlined),
                onPressed: () => openNowPlaying(context, lyrics: true),
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
///
/// Used in the desktop player bar (fixed width), across Now Playing (fills the row, so it's
/// there with the cover and with the lyrics) and inside [VolumeButton]'s pop-up (0.1.22).
class VolumeControl extends StatelessWidget {
  /// Width of the slider; null makes it fill the space it's given.
  final double? sliderWidth;
  const VolumeControl({super.key, this.sliderWidth = 120});

  /// How much one notch of the wheel changes the volume (out of 100).
  static const wheelStep = 5.0;

  /// The speaker icon for a volume (0–100): crossed out when silent, one wave below half.
  static IconData iconFor(double volume) =>
      volume <= 0 ? Icons.volume_off : (volume < 50 ? Icons.volume_down : Icons.volume_up);

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
        // Touchpad two-finger swipe: move smoothly with the fingers (up = louder).
        final player = context.read<PlayerModel>();
        player.setVolume((player.volume - event.panDelta.dy * 0.25).clamp(0.0, 100.0));
      },
      child: Tooltip(
        message: 'Volume ${volume.round()}% – scroll to change',
        waitDuration: const Duration(milliseconds: 800),
        child: Row(mainAxisSize: sliderWidth == null ? MainAxisSize.max : MainAxisSize.min, children: [
          // The speaker icon is a quick mute / unmute (0.1.27).
          IconButton(
            key: const ValueKey('mute-toggle'),
            tooltip: volume <= 0 ? 'Unmute' : 'Mute',
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            color: volume <= 0 ? Theme.of(context).colorScheme.primary : AppColors.textDim,
            icon: Icon(iconFor(volume)),
            onPressed: () => context.read<PlayerModel>().toggleMute(),
          ),
          if (sliderWidth == null)
            Expanded(child: Slider(value: volume, max: 100, onChanged: p.setVolume))
          else
            SizedBox(
              width: sliderWidth,
              child: Slider(value: volume, max: 100, onChanged: p.setVolume),
            ),
        ]),
      ),
    );
  }
}

/// Phone mini player: a speaker button that opens a small volume slider above it (0.1.22).
/// The slider stays open while it's dragged; tapping anywhere else closes it.
class VolumeButton extends StatelessWidget {
  const VolumeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final volume = context.select<PlayerModel, double>((p) => p.volume.clamp(0.0, 100.0));
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.surfaceHigh),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
      ),
      menuChildren: const [VolumeControl(key: ValueKey('volume-popup'), sliderWidth: 200)],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Volume ${volume.round()}%',
        icon: Icon(VolumeControl.iconFor(volume)),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
