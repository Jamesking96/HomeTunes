// One open video page's playback (refactor phase 5, 9 Oct 2026). Everything the video page used
// to run itself, moved here unchanged so the page only draws: opening a video (carrying on from
// its place, rewinding a little after a break, the collection's speed), previous / next in the
// collection, Up next after the end, the audio and subtitle choice remembered per collection,
// saving the place, the videos' equaliser, the volume boost's top, pausing the music (and being
// paused by it), and the bottom bar / media keys (NowWatching). The player is a [VideoEngine]
// (services/engine/video_engine.dart): media_kit in the app, a fake in tests.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/video_item.dart';
import '../models/volume_boost.dart';
import '../services/engine/audio_chain.dart';
import '../services/engine/video_engine.dart';
import '../services/path_safety.dart';
import '../services/video_names.dart';
import '../services/video_stats.dart';
import 'equalizer_model.dart';
import 'library_model.dart';
import 'now_watching.dart';
import 'player_model.dart';
import 'video_filters.dart';
import 'video_library_model.dart';
import 'video_tracks.dart';

class VideoSession extends ChangeNotifier {
  VideoSession({
    required this.engine,
    required this.videos,
    required this.music,
    required String videoId,
    this.watching,
    this.equalizer,
    this.stats,
    this.onReady,
    this.onCarryOn,
    VoidCallback? onOpenPage,
    this.upNextTick = const Duration(seconds: 1),
    this.tracksSettle = const Duration(milliseconds: 200),
    this.openingTimeout = const Duration(seconds: 12),
  })  : _id = videoId,
        shownId = ValueNotifier(videoId) {
    transport = VideoEngineTransport(engine, maxVolume: () => settings.maxVolume);
    music.addListener(_onMusicChanged);
    // The bottom bar and the system media controls show and control this video (30 Sep).
    watching?.attach(transport, onOpen: onOpenPage);
    equalizer?.addListener(_applyEqualizer);
    // Volume boost (0.1.62): the volume can go above 100 up to Settings › Playback's top.
    settings.addListener(_followVolumeTop);
    if (engine.hasOptions) engine.setOption('volume-max', '$engineVolumeMax');
    _subs.addAll([
      engine.completedStream.listen((done) {
        if (done) _finished();
      }),
      engine.errorStream.listen((e) {
        if (!_disposed && engine.duration == Duration.zero) {
          problem = 'Can\'t play this video: $e';
          notifyListeners();
          shown();
        }
      }),
      // Playing and moving on: it's showing (some files never report a first picture).
      engine.positionStream.listen((at) {
        stats?.moved(at); // 0.1.58: skips are noted in the Playback log
        if (opening && at > Duration.zero && engine.isPlaying) shown();
      }),
      engine.playingStream.listen((playing) {
        // One thing at a time: whenever the video starts (or carries on), the music or
        // audiobook pauses (30 Sep: before, only when the page first opened).
        if (playing && music.playing) music.pause();
        if (!playing) savePlace();
        stats?.playing(playing);
      }),
      engine.bufferingStream.listen((b) => stats?.buffering(b)),
      engine.sampleRateStream.listen(_chain.sampleRateChanged),
      engine.tracksStream.listen((_) => _setUpTracks()),
      engine.trackStream.listen((_) => _readCurrentTracks()),
    ]);
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (engine.isPlaying) savePlace();
    });
    open(_id);
  }

  final VideoEngine engine;
  final VideoLibraryModel videos;
  final PlayerModel music;

  /// What the bottom bar and media keys use to reach this player. Null in tests without one.
  final NowWatching? watching;

  /// The equaliser (Settings › Videos can give videos their own preset). Null in tests without one.
  final EqualizerModel? equalizer;

  /// Playback stats in the Playback log (0.1.55): decoding, dropped pictures, waits. Null in tests.
  final VideoStats? stats;

  /// Called once, when the first video is showing (or can't be played): the loading page fades.
  final VoidCallback? onReady;

  /// A video opened part-way through, at this place: the page offers Start over.
  final void Function(Duration from)? onCarryOn;

  /// How fast Up next counts down, how long added subtitle files get to show up, and the longest
  /// the opening spinner stays up (shorter in tests).
  final Duration upNextTick, tracksSettle, openingTimeout;

  late final VideoEngineTransport transport;

  LibraryModel get settings => videos.library;

  // Sends the videos' preset to this player (services/engine/audio_chain.dart, shared with the
  // music player): the bands as a filter, with those at or above half the sound's sample rate
  // left out (refactor phase 1), and the overall level as mpv's `replaygain-fallback` (the gain
  // used for files without ReplayGain tags, as videos are), so the volume slider stays the
  // listener's. A volume filter in the lavfi graph stalled playback on this engine
  // (tool/bench/frame_picker_engine_test.dart).
  late final AudioChain _chain = AudioChain(
    preset: () => equalizer?.activeForVideos,
    hasOptions: () => engine.hasOptions,
    setOption: engine.setOption,
    level: EqLevel.replayGainFallback,
    name: 'video player',
  );

  final List<StreamSubscription> _subs = [];
  Timer? _saveTimer, _upNextTimer, _openingTimer;
  bool _disposed = false;

  /// The video playing now (the page moves on to the next one in its collection).
  String get id => _id;
  String _id;

  /// The video on screen, for the previous / next buttons (0.1.71). They listen to this rather
  /// than being built with a fixed target: full screen keeps the controls it was opened with, so
  /// a target worked out then went stale after one press, and the next press replayed the video
  /// now playing.
  final ValueNotifier<String> shownId;

  /// The speed now (starts at the collection's own, else Settings › Videos' usual one).
  double speed = 1.0;

  /// The file couldn't be found or opened.
  String? problem;

  // Tracks: set up once per file, when the engine first lists them.
  bool tracksSetUp = false;
  String aid = 'auto', sid = 'auto';

  // Playing on: the next video and the seconds left before it starts.
  VideoItem? upNext;
  int countdown = 0;

  /// Opening (0.1.42): a video is being opened and isn't showing yet. The first time, the loading
  /// page covers the whole page; for the next / previous video a spinner shows on the picture.
  bool opening = false;

  /// The first video has shown, and [onReady] was called.
  bool get toldReady => _toldReady;
  bool _toldReady = false;

  /// The video is showing (or can't be played): stop the spinner and lift the loading page.
  void shown() {
    _openingTimer?.cancel();
    if (_disposed) return;
    if (opening) {
      opening = false;
      notifyListeners();
    }
    if (!_toldReady) {
      _toldReady = true;
      // Not straight away: this can happen while the page is first being built.
      final ready = onReady;
      if (ready != null) Future.microtask(ready);
    }
  }

  /// The previous / next video buttons: keep this one's place, then open that one.
  void goTo(String id) {
    if (_disposed || id == _id) return;
    savePlace();
    open(id);
  }

  /// The video before / after [id] in its collection, or null at either end.
  VideoItem? neighbour(String id, {required bool forward}) {
    final v = videos.byId(id);
    if (v == null) return null;
    return forward ? videos.after(v) : videos.before(v);
  }

  /// Previous / next video, worked out when pressed from the video playing now (0.1.71).
  void jump({required bool forward}) {
    final target = neighbour(_id, forward: forward);
    if (target != null) goTo(target.id);
  }

  Future<void> open(String id) async {
    final v = videos.byId(id);
    final file = v == null ? null : videos.playableFile(v);
    shownId.value = id;
    _id = id;
    problem = null;
    tracksSetUp = false;
    upNext = null;
    aid = 'auto';
    sid = 'auto';
    opening = true;
    notifyListeners();
    _upNextTimer?.cancel();
    // At the latest after 12 s: don't keep a spinner up for ever.
    _openingTimer?.cancel();
    _openingTimer = Timer(openingTimeout, shown);
    if (v == null || file == null) {
      problem = 'This video isn\'t there any more. Rescan your video folders to tidy the list.';
      notifyListeners();
      shown();
      return;
    }
    final next = videos.after(v), previous = videos.before(v);
    watching?.showing(v,
        picture: videos.thumbFile(v),
        skipBack: settings.videoSkipBackSeconds,
        skipForward: settings.videoSkipForwardSeconds,
        onNext: next == null ? null : () => jump(forward: true),
        onPrevious: previous == null ? null : () => jump(forward: false),
        transport: transport);
    // One thing at a time: the music pauses while a video plays.
    if (music.playing) await music.pause();
    final place = videos.placeOf(v.id);
    var start = resumeAt(place, v.duration);
    // Settings › Videos: go back a little, more after a long break (like audiobooks).
    if (start > Duration.zero && place != null && settings.videoRewindOnResume) {
      final since = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(place.updatedMs));
      start -= PlayerModel.resumeRewind(since);
      if (start < Duration.zero) start = Duration.zero;
    }
    await _applyEqualizer();
    stats?.started(v.episodeLabel == null ? v.title : '${v.collection} ${v.episodeLabel}');
    await engine.open(file, start: start > Duration.zero ? start : null);
    speed = videos.speedFor(v.collection);
    await engine.setRate(speed);
    if (_disposed) return;
    notifyListeners();
    if (start > Duration.zero) onCarryOn?.call(start);
  }

  /// "Start over" after carrying on part-way through.
  Future<void> startOver() => engine.seek(Duration.zero);

  // ---- audio and subtitles ----

  List<MediaTrack> get audioTracks => engine.audioTracks;
  List<MediaTrack> get subtitleTracks => engine.subtitleTracks;

  /// When the file's tracks are known: add the subtitle files beside it, then pick the audio and
  /// subtitles last chosen in this collection.
  Future<void> _setUpTracks() async {
    if (tracksSetUp) return;
    final real = engine.audioTracks.where((t) => t.isReal);
    if (real.isEmpty && engine.duration == Duration.zero) return; // not loaded yet
    tracksSetUp = true;
    final v = videos.byId(_id);
    if (v == null) return;
    if (engine.hasOptions) {
      for (final s in v.subtitles) {
        // Only files inside the video folders (a restored backup could name any path).
        if (!isUsableLocalFile(s, roots: settings.videoFolders, extensions: subtitleExtensions)) continue;
        final label = subtitleLabel(s, v.path);
        try {
          await engine.command(['sub-add', s, 'auto', '$label (file)', languageCodeFor(label) ?? '']);
        } catch (_) {}
      }
    }
    final choice = videos.trackChoiceFor(v.collection);
    await Future<void>.delayed(tracksSettle); // let the added files show up
    if (choice.audio != null) {
      if (choice.audio!.off) {
        await engine.setAudioTrack(null);
      } else {
        final t = matchTrack(engine.audioTracks, choice.audio!);
        if (t != null) await engine.setAudioTrack(t.id);
      }
    }
    if (choice.subtitles != null) {
      if (choice.subtitles!.off) {
        await engine.setSubtitleTrack(null);
      } else {
        final t = matchTrack(engine.subtitleTracks, choice.subtitles!);
        if (t != null) await engine.setSubtitleTrack(t.id);
      }
    }
    await _readCurrentTracks();
  }

  /// Which audio and subtitle track the engine is really using ("auto" resolves to one).
  Future<void> _readCurrentTracks() async {
    if (!engine.hasOptions) return;
    try {
      final a = await engine.getOption('aid');
      final s = await engine.getOption('sid');
      if (!_disposed) {
        aid = a;
        sid = s;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// The listener chose an audio track (null: no sound); remembered for the whole collection.
  Future<void> chooseAudio(MediaTrack? t) async {
    await engine.setAudioTrack(t?.id);
    final collection = videos.byId(_id)?.collection;
    if (collection != null) {
      videos.rememberTrackChoice(collection,
          audio: t == null ? TrackPick.none : TrackPick(language: t.language, title: t.title));
    }
    await _readCurrentTracks();
  }

  /// The listener chose subtitles (null: off); remembered for the whole collection.
  Future<void> chooseSubtitles(MediaTrack? t) async {
    await engine.setSubtitleTrack(t?.id);
    final collection = videos.byId(_id)?.collection;
    if (collection != null) {
      videos.rememberTrackChoice(collection,
          subtitles: t == null ? TrackPick.none : TrackPick(language: t.language, title: t.title));
    }
    await _readCurrentTracks();
  }

  // ---- skipping, speed, the volume and the equaliser (Settings › Videos) ----

  /// Back ([forward] false) or forward by the seconds set in Settings › Videos.
  void skip({required bool forward}) {
    final by = Duration(seconds: forward ? settings.videoSkipForwardSeconds : settings.videoSkipBackSeconds);
    var to = forward ? engine.position + by : engine.position - by;
    if (to < Duration.zero) to = Duration.zero;
    final length = engine.duration;
    if (length > Duration.zero && to > length) to = length;
    engine.seek(to);
  }

  /// A new speed, remembered for the rest of the collection.
  Future<void> setSpeed(double value) async {
    await engine.setRate(value);
    if (!_disposed) {
      speed = value;
      notifyListeners();
    }
    final v = videos.byId(_id);
    if (v != null) videos.rememberSpeed(v.collection, value);
  }

  /// ↑ / ↓ on the video: the volume up or down by [step], up to the volume boost's top.
  void stepVolume(double step) => engine.setVolume(stepEngineVolume(engine.volume, step, settings.maxVolume));

  /// The volume boost's top was lowered (or the boost turned off): bring a louder volume down.
  void _followVolumeTop() {
    final max = settings.maxVolume;
    if (sliderVolume(engine.volume) > max + 0.01) engine.setVolume(engineVolume(max));
  }

  /// Sends the videos' equaliser preset to this player, if it changed (see [_chain]).
  Future<void> _applyEqualizer() => _chain.update();

  // ---- places and playing on ----

  /// Music started while the video plays: pause the video.
  void _onMusicChanged() {
    if (music.playing && engine.isPlaying) engine.pause();
  }

  void savePlace({bool end = false}) {
    final length = engine.duration;
    if (length <= Duration.zero) return;
    final at = end ? length : engine.position;
    if (at <= Duration.zero) return;
    videos.savePlace(_id, at, length);
  }

  /// The end: counts as watched, then the next video in the collection starts after a countdown.
  void _finished() {
    savePlace(end: true);
    final v = videos.byId(_id);
    final next = v == null ? null : videos.after(v);
    if (next == null || _disposed) return;
    upNext = next;
    countdown = 10;
    notifyListeners();
    _upNextTimer?.cancel();
    _upNextTimer = Timer.periodic(upNextTick, (t) {
      if (_disposed) return t.cancel();
      if (countdown <= 1) {
        t.cancel();
        open(next.id);
      } else {
        countdown--;
        notifyListeners();
      }
    });
  }

  /// Up next's Cancel.
  void cancelUpNext() {
    _upNextTimer?.cancel();
    upNext = null;
    notifyListeners();
  }

  /// Up next's Play now.
  void playUpNextNow() {
    final next = upNext;
    if (next != null) open(next.id);
  }

  @override
  void dispose() {
    _disposed = true;
    // Save the place once this frame is done (telling the Videos tab during dispose would redraw
    // it while the widget tree is locked).
    final length = engine.duration, at = engine.position;
    final id = _id, library = videos;
    if (length > Duration.zero && at > Duration.zero) Future.microtask(() => library.savePlace(id, at, length));
    _saveTimer?.cancel();
    _upNextTimer?.cancel();
    _openingTimer?.cancel();
    music.removeListener(_onMusicChanged);
    watching?.detach(transport);
    equalizer?.removeListener(_applyEqualizer);
    _chain.close();
    settings.removeListener(_followVolumeTop);
    for (final s in _subs) {
      s.cancel();
    }
    stats?.dispose();
    engine.dispose();
    shownId.dispose();
    super.dispose();
  }
}

/// A video page's player as seen by [NowWatching] (the bottom bar and the system media controls).
/// The volume here is on the sliders' scale (0–100, or up to the volume boost's top, 0.1.62);
/// the engine's own number differs above 100 (models/volume_boost.dart). Was `MediaKitTransport`
/// in video_player_screen.dart until refactor phase 5.
class VideoEngineTransport implements VideoTransport, VolumeTop {
  VideoEngineTransport(this.engine, {double Function()? maxVolume}) : _maxVolume = maxVolume ?? (() => 100);
  final VideoEngine engine;
  final double Function() _maxVolume;

  @override
  double get maxVolume => _maxVolume();

  @override
  bool get playing => engine.isPlaying;
  @override
  Stream<bool> get playingStream => engine.playingStream;
  @override
  Duration get position => engine.position;
  @override
  Stream<Duration> get positionStream => engine.positionStream;
  @override
  Duration get duration => engine.duration;
  @override
  Stream<Duration> get durationStream => engine.durationStream;
  @override
  double get volume => sliderVolume(engine.volume);
  @override
  Stream<double> get volumeStream => engine.volumeStream.map(sliderVolume);
  @override
  double get rate => engine.rate;
  @override
  Future<void> play() => engine.play();
  @override
  Future<void> pause() => engine.pause();
  @override
  Future<void> seek(Duration to) => engine.seek(to);
  @override
  Future<void> setVolume(double volume) => engine.setVolume(engineVolume(volume.clamp(0.0, maxVolume)));
}
