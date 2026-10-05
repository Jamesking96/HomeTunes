// The music video display on Now Playing (0.1.40).
//
// The song itself keeps playing in PlayerModel's engine, exactly as before (gapless, equaliser,
// ReplayGain, media keys all unchanged). This widget opens the song's video file in a second,
// muted player that decodes pictures only, and keeps it in step with the song:
//  * play / pause follow the song;
//  * the video's position is checked against the song's twice a second. Small drifts are caught
//    up by playing the (silent) video a little faster or slower ([videoSyncRate], 0.1.56), which
//    can't be seen; only when they're more than [videoSyncTolerance] apart (after a seek, a skip
//    back, repeat-one starting again) does the video jump. Before 0.1.56 every drift over 0.4 s
//    was a jump, and each jump froze the picture for a moment: on the phone that happened every
//    few seconds (the Playback log showed it), which was the music video stutter;
//  * a new song with a video reuses the same player; the page shows the cover for songs without.
// Until the first picture arrives (or if the file can't be shown) the [fallback] (the cover) is
// shown instead, so there's never an empty black box.
// Buttons over the video (shown while the mouse is over it, or after a tap) make it bigger on
// Now Playing (Enlarge) or fill the screen (Full screen). In full screen the song's controls and
// title show over the video when the mouse moves; Esc, F or a double-click leave it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../services/video_stats.dart';
import '../../state/player_model.dart';
import '../theme.dart';

/// How far the video may drift from the song before it jumps back into step (0.1.56: was 0.4 s;
/// smaller drifts are now caught up with [videoSyncRate]).
const videoSyncTolerance = Duration(milliseconds: 1500);

/// Drift that's left alone: the two positions are only reported every so often, so smaller
/// differences are mostly noise.
const videoInStep = Duration(milliseconds: 100);

/// The video's speed to catch up a small drift: the song's speed when they're in step, else up
/// to 10 % faster (video behind) or slower (video ahead), aiming to close the gap in about
/// 3 seconds. The video is silent, so the change can't be heard and is hard to see.
double videoSyncRate({required Duration song, required Duration video, double songSpeed = 1.0}) {
  final drift = video - song; // positive: the video is ahead
  if (drift.abs() <= videoInStep) return songSpeed;
  final adjust = (drift.inMilliseconds / 3000).clamp(-0.1, 0.1);
  return songSpeed * (1 - adjust);
}

/// Where the video should jump to, or null when it's close enough to the song already.
/// [videoLength] is null while the video's length isn't known yet.
Duration? videoSeekTarget({required Duration song, required Duration video, Duration? videoLength}) {
  // A video shorter than the song (an intro cut off, say) just stays on its last picture.
  if (videoLength != null && videoLength > Duration.zero && song >= videoLength) return null;
  return (song - video).abs() > videoSyncTolerance ? song : null;
}

/// Whether the video should keep playing in this app state. Only a window that can't be seen
/// (minimised, hidden, the phone app in the background) pauses it. A window that's merely not
/// the focused one is `inactive` on Windows but still visible, so the video carries on there.
/// (Pausing on `inactive` made the video stutter: the song played on, and the paused video was
/// jumped forward to it every 2 seconds.)
bool videoVisible(AppLifecycleState? state) =>
    state == null || state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;

/// Shows [file] (a song's music video) muted and in step with the song that's playing.
class MusicVideoView extends StatefulWidget {
  /// The video file (LibraryModel.videoFileFor).
  final String file;

  /// Shown until the first picture arrives, or instead of the video if it can't be shown.
  final Widget fallback;

  /// Whether Now Playing shows the video enlarged, and the button that switches it (null: no
  /// Enlarge button).
  final bool enlarged;
  final VoidCallback? onToggleEnlarge;

  const MusicVideoView({
    super.key,
    required this.file,
    required this.fallback,
    this.enlarged = false,
    this.onToggleEnlarge,
  });

  @override
  State<MusicVideoView> createState() => _MusicVideoViewState();
}

class _MusicVideoViewState extends State<MusicVideoView> with WidgetsBindingObserver {
  // The video's own player: muted, no sound decoded, no subtitles.
  final Player _video = Player(configuration: const PlayerConfiguration(title: 'HomeTunes music video'));
  late final VideoController _controller = VideoController(_video);
  // Playback stats in the Playback log (0.1.55). Null in tests.
  late final VideoStats? _stats = VideoStats.forPlayer(_video, 'Music video');
  // Reaches the Video widget to go full screen.
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  late final PlayerModel _song;
  final List<StreamSubscription> _subs = [];

  /// True once the video has a picture size (its first frame is ready).
  bool _ready = false;

  /// The file couldn't be opened or has no pictures: the cover stays.
  bool _failed = false;

  // Seeking a video takes a moment (it decodes from the nearest keyframe), so after a seek the
  // video isn't checked again for a little while, or it would keep chasing the song.
  DateTime _nextCheck = DateTime.fromMillisecondsSinceEpoch(0);
  // The app can be seen (the video pauses while it can't, to save battery). See [videoVisible].
  bool _onScreen = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _song = context.read<PlayerModel>();
    _onScreen = videoVisible(WidgetsBinding.instance.lifecycleState);
    _setUp();
  }

  Future<void> _setUp() async {
    final engine = _video.platform;
    if (engine is NativePlayer) {
      try {
        // The song plays in the main player; this one never makes a sound.
        await engine.setProperty('aid', 'no');
        await engine.setProperty('sid', 'no');
      } catch (_) {}
    }
    await _video.setVolume(0);
    _subs.addAll([
      _video.stream.width.listen((w) {
        final ready = (w ?? 0) > 0;
        if (ready != _ready && mounted) setState(() => _ready = ready);
      }),
      // The shape can change when the height arrives after the width: redraw to fit it.
      _video.stream.height.listen((_) {
        if (_ready && mounted) setState(() {});
      }),
      _video.stream.error.listen((_) {
        // Only give up if nothing has been shown yet; a hiccup mid-video isn't worth hiding it.
        if (!_ready && mounted) setState(() => _failed = true);
      }),
      _song.positionStream.listen((_) => _keepInStep()),
      _video.stream.playing.listen((p) => _stats?.playing(p)),
      _video.stream.buffering.listen((b) => _stats?.buffering(b)),
    ]);
    _song.addListener(_followPlayPause);
    await _open(widget.file);
  }

  Future<void> _open(String file) async {
    if (!mounted) return;
    setState(() {
      _ready = false;
      _failed = false;
    });
    _nextCheck = DateTime.now().add(const Duration(seconds: 1));
    try {
      final at = _song.position;
      _stats?.started(_song.current?.title ?? p.basenameWithoutExtension(file));
      _setRate(_song.speed, force: true); // a new file starts at the song's own speed
      await _video.open(Media(file, start: at > Duration.zero ? at : null), play: _shouldPlay);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  bool get _shouldPlay => _song.playing && _onScreen;

  /// Play and pause with the song.
  void _followPlayPause() {
    if (_failed) return;
    if (_shouldPlay != _video.state.playing) {
      _shouldPlay ? _video.play() : _video.pause();
      // Starting again: line up with the song straight away.
      _nextCheck = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  /// Called on each tick of the song's position: moves the video if it has drifted.
  void _keepInStep() {
    if (_failed || !_ready) return;
    final now = DateTime.now();
    if (now.isBefore(_nextCheck)) return;
    _nextCheck = now.add(const Duration(milliseconds: 500));
    _followPlayPause();
    // Out of sight the video is paused on purpose: don't drag it along behind the song.
    // It's lined up again as soon as the window can be seen (didChangeAppLifecycleState).
    if (!_onScreen) return;
    // Still settling after a jump: wait for it (up to 3 s) rather than measuring a half-finished
    // seek.
    if (_video.state.buffering && now.isBefore(_settleUntil)) return;
    final song = _song.position, video = _video.state.position, length = _video.state.duration;
    final target = videoSeekTarget(song: song, video: video, videoLength: length);
    if (target != null) {
      // Far apart (the song was moved, or the video was paused out of sight): jump.
      _nextCheck = now.add(const Duration(seconds: 2));
      _settleUntil = now.add(const Duration(seconds: 3));
      _stats?.jumped();
      _setRate(_song.speed);
      _video.seek(target);
      return;
    }
    // Past the end of a shorter video: it stays on its last picture.
    if (length > Duration.zero && song >= length) return;
    // Close: nudge the video's speed so it catches up without a visible jump (0.1.56).
    _setRate(videoSyncRate(song: song, video: video, songSpeed: _song.speed));
  }

  // The video's speed now (1.0 unless catching up), and until when a jump is still settling.
  double _rate = 1.0;
  DateTime _settleUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Changes the video's speed, skipping tiny changes (each one is a call into the engine), but
  /// always going back exactly to the song's speed once in step.
  void _setRate(double r, {bool force = false}) {
    if (!force && r == _rate) return;
    if (!force && (r - _rate).abs() < 0.01 && r != _song.speed) return;
    _rate = r;
    _video.setRate(r);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = videoVisible(state);
    if (visible == _onScreen) return;
    _onScreen = visible;
    _followPlayPause();
    // Back in sight: line up with the song straight away.
    if (visible) _nextCheck = DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  void didUpdateWidget(MusicVideoView old) {
    super.didUpdateWidget(old);
    // The next song has a video too: reuse this player.
    if (old.file != widget.file) _open(widget.file);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _song.removeListener(_followPlayPause);
    for (final s in _subs) {
      s.cancel();
    }
    _stats?.dispose();
    // Still full screen (e.g. the next song has no video): leave it first, and let the
    // full-screen page go before its player does.
    final state = _videoKey.currentState;
    if (state != null && state.isFullscreen()) {
      state.exitFullscreen();
      Future<void>.delayed(const Duration(milliseconds: 500), _video.dispose);
    } else {
      _video.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The video is drawn (invisibly) even before its first picture, so it can start.
    return Stack(alignment: Alignment.center, children: [
      if (!_failed)
        Offstage(
          offstage: !_ready,
          child: LayoutBuilder(builder: (context, box) {
            // As big as fits, keeping the video's own shape (16:9 until it's known).
            final w = _video.state.width, h = _video.state.height;
            final ratio = (w != null && h != null && w > 0 && h > 0) ? w / h : 16 / 9;
            var width = box.maxWidth;
            var height = width / ratio;
            if (height > box.maxHeight) {
              height = box.maxHeight;
              width = height * ratio;
            }
            return ClipRRect(
              borderRadius: AppShape.circular(8),
              child: SizedBox(
                width: width,
                height: height,
                child: Video(
                  key: _videoKey,
                  controller: _controller,
                  controls: (state) => MusicVideoControls(
                    enlarged: widget.enlarged,
                    onToggleEnlarge: widget.onToggleEnlarge,
                  ),
                  fill: Colors.black,
                  // The video plays and pauses with the song; see didChangeAppLifecycleState.
                  pauseUponEnteringBackgroundMode: false,
                ),
              ),
            );
          }),
        ),
      if (_failed || !_ready) widget.fallback,
    ]);
  }
}

/// The buttons over a music video. On Now Playing: Enlarge / Shrink and Full screen, in the
/// bottom corner. In full screen: the song's title, previous / play-pause / next and a button to
/// leave full screen. Both fade in when the mouse moves (or on a tap) and out after 3 seconds.
/// Keys in full screen: Esc or F leaves, Space plays or pauses the song. Double-click switches
/// full screen on and off.
class MusicVideoControls extends StatefulWidget {
  final bool enlarged;
  final VoidCallback? onToggleEnlarge;
  const MusicVideoControls({super.key, this.enlarged = false, this.onToggleEnlarge});

  @override
  State<MusicVideoControls> createState() => _MusicVideoControlsState();
}

class _MusicVideoControlsState extends State<MusicVideoControls> {
  bool _visible = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _poke();
  }

  /// Shows the buttons and hides them again after a few seconds of no movement.
  void _poke() {
    _hide?.cancel();
    if (!_visible) setState(() => _visible = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || !isFullscreen(context)) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape || e.logicalKey == LogicalKeyboardKey.keyF) {
      exitFullscreen(context);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.space) {
      context.read<PlayerModel>().togglePlay();
      _poke();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final full = isFullscreen(context);
    return Focus(
      autofocus: full,
      onKeyEvent: _onKey,
      child: MouseRegion(
        onHover: (_) => _poke(),
        cursor: _visible || !full ? MouseCursor.defer : SystemMouseCursors.none,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _poke,
          onDoubleTap: () => toggleFullscreen(context),
          child: Stack(children: [
            const Positioned.fill(child: SizedBox.expand()),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_visible,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: full ? const _FullScreenBar() : _cornerButtons(context),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _cornerButtons(BuildContext context) => Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.onToggleEnlarge != null)
              _RoundButton(
                icon: widget.enlarged ? Icons.close_fullscreen : Icons.open_in_full,
                tooltip: widget.enlarged ? 'Make the video smaller' : 'Enlarge the video',
                onPressed: widget.onToggleEnlarge!,
              ),
            const SizedBox(width: 8),
            _RoundButton(icon: Icons.fullscreen, tooltip: 'Full screen', onPressed: () => enterFullscreen(context)),
          ]),
        ),
      );
}

/// Full screen: the song's title and controls along the bottom, and a way out.
class _FullScreenBar extends StatelessWidget {
  const _FullScreenBar();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerModel>();
    final t = p.current;
    return Stack(children: [
      Positioned(
        left: 16,
        top: 16,
        child: _RoundButton(icon: Icons.fullscreen_exit, tooltip: 'Leave full screen (Esc)', onPressed: () => exitFullscreen(context)),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
          ),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                Text(t?.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 16)),
              ]),
            ),
            IconButton(
              tooltip: 'Previous',
              iconSize: 32,
              color: Colors.white,
              icon: const Icon(Icons.skip_previous),
              onPressed: () => p.previous(),
            ),
            IconButton(
              tooltip: p.playing ? 'Pause' : 'Play',
              iconSize: 48,
              color: Colors.white,
              icon: Icon(p.playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
              onPressed: p.togglePlay,
            ),
            IconButton(
              tooltip: 'Next',
              iconSize: 32,
              color: Colors.white,
              icon: const Icon(Icons.skip_next),
              onPressed: p.next,
            ),
            const SizedBox(width: 12),
            _RoundButton(icon: Icons.fullscreen_exit, tooltip: 'Leave full screen', onPressed: () => exitFullscreen(context)),
          ]),
        ),
      ),
    ]);
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _RoundButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: Colors.white),
          onPressed: onPressed,
        ),
      );
}
