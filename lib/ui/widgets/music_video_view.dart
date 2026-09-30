// The music video display on Now Playing (0.1.32).
//
// The song itself keeps playing in PlayerModel's engine, exactly as before (gapless, equaliser,
// ReplayGain, media keys all unchanged). This widget opens the song's video file in a second,
// muted player that decodes pictures only, and keeps it in step with the song:
//  * play / pause follow the song;
//  * the video's position is checked against the song's twice a second, and moved when they're
//    more than [videoSyncTolerance] apart (after a seek, a skip back, repeat-one starting again,
//    or slow drift between the two engines);
//  * a new song with a video reuses the same player; the page shows the cover for songs without.
// Until the first picture arrives (or if the file can't be shown) the [fallback] (the cover) is
// shown instead, so there's never an empty black box.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../state/player_model.dart';
import '../theme.dart';

/// How far the video may drift from the song before it's moved back into step.
const videoSyncTolerance = Duration(milliseconds: 400);

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

  const MusicVideoView({super.key, required this.file, required this.fallback});

  @override
  State<MusicVideoView> createState() => _MusicVideoViewState();
}

class _MusicVideoViewState extends State<MusicVideoView> with WidgetsBindingObserver {
  // The video's own player: muted, no sound decoded, no subtitles.
  final Player _video = Player(configuration: const PlayerConfiguration(title: 'HomeTunes music video'));
  late final VideoController _controller = VideoController(_video);
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
    final target = videoSeekTarget(
      song: _song.position,
      video: _video.state.position,
      videoLength: _video.state.duration,
    );
    if (target != null) {
      _nextCheck = now.add(const Duration(seconds: 2));
      _video.seek(target);
    }
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
    _video.dispose();
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
                  controller: _controller,
                  controls: NoVideoControls,
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
