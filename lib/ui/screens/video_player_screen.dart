// Videos (0.1.40): one video's player page, opened from the Videos tab or a collection's page.
//
// The video plays in its own player (media_kit's Video widget with its standard controls: seek
// bar, play/pause, volume, full screen; on a computer Space, the arrow keys, F and Esc work too).
// An "Audio and subtitles" button sits in those controls, in full screen too: it lists the
// video's audio tracks and subtitles (Off for either), including subtitle files found beside it
// or in a Subs folder, which are added as choices when it opens. The choice is remembered for the
// whole collection (English audio for every episode of a dual-audio series, say), matched by
// language and name. On Windows the engine draws the subtitles itself (libass), so styled anime
// subtitles and picture-based DVD / Blu-ray ones show properly; on the phone the app draws text
// subtitles.
// Under the video are its details and buttons for Enlarge (the video fills the whole page),
// Full screen, Audio and subtitles, Edit details, Mark as watched and Show in folder, plus a link
// to its collection. It carries on from where it was left (with Start over), saves the place
// every few seconds, counts the end as watched, and then plays the next video in the collection
// after a short countdown (the same page and player, so full screen carries on). Starting a
// video pauses the music; starting music pauses the video.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/eq_preset.dart' show EqPreset, eqFilter;
import '../../models/video_item.dart';
import '../../models/video_player_look.dart';
import '../../models/volume_boost.dart';
import '../../services/path_safety.dart';
import '../../services/video_drawing.dart';
import '../../services/video_names.dart';
import '../../services/video_stats.dart';
import '../../state/equalizer_model.dart';
import '../../state/library_model.dart';
import '../../state/now_watching.dart';
import '../../state/player_model.dart';
import '../../state/video_filters.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/always_on_top_button.dart';
import '../widgets/listening_controls.dart' show SpeedButton;
import '../widgets/video_controls_look.dart';
import '../widgets/video_sleep_button.dart';
import 'edit_video.dart';
import 'equalizer_screen.dart' show openEqualizer;
import 'video_details_screen.dart' show openVideoDetails;
import 'video_pictures.dart';
import 'videos_screen.dart' show videoLength;
import '../widgets/selectable_title.dart';
import '../widgets/volume_slider.dart';
import '../widgets/window_scale.dart';

/// What the video player sends the engine for [preset]: the equaliser filter (bands at or above
/// half of [sampleRate] left out, as for music) and the overall level in dB (mpv's
/// `replaygain-fallback`). Refactor phase 1, 8 Oct 2026.
({String filter, String level}) videoEqualizerSettings(EqPreset? preset, {int? sampleRate}) =>
    (filter: eqFilter(preset, sampleRate: sampleRate), level: (preset?.level ?? 0).toStringAsFixed(1));

/// Language codes the engine reports, as words.
const _languages = {
  'eng': 'English', 'en': 'English', 'jpn': 'Japanese', 'ja': 'Japanese', 'spa': 'Spanish', 'es': 'Spanish',
  'fre': 'French', 'fra': 'French', 'fr': 'French', 'ger': 'German', 'deu': 'German', 'de': 'German',
  'ita': 'Italian', 'it': 'Italian', 'por': 'Portuguese', 'pt': 'Portuguese', 'rus': 'Russian', 'ru': 'Russian',
  'chi': 'Chinese', 'zho': 'Chinese', 'zh': 'Chinese', 'kor': 'Korean', 'ko': 'Korean', 'ara': 'Arabic',
  'hin': 'Hindi', 'dut': 'Dutch', 'nld': 'Dutch', 'swe': 'Swedish', 'nor': 'Norwegian', 'dan': 'Danish',
  'fin': 'Finnish', 'pol': 'Polish', 'tur': 'Turkish', 'gre': 'Greek', 'ell': 'Greek', 'heb': 'Hebrew',
  'tha': 'Thai', 'vie': 'Vietnamese', 'ind': 'Indonesian', 'hun': 'Hungarian', 'cze': 'Czech', 'ces': 'Czech',
};

String? languageName(String? code) => code == null ? null : _languages[code.toLowerCase()];

/// A language code for a subtitle file's label ("English" → "eng"), or null.
String? _codeFor(String label) {
  final l = label.toLowerCase();
  for (final e in _languages.entries) {
    if (e.key.length == 3 && l.contains(e.value.toLowerCase())) return e.key;
  }
  return null;
}

/// "English · 5.1 · AC3", "Full Subtitles [MK-Baal] · English".
String trackLabel(String kind, dynamic t, int n) {
  final String? title = t.title;
  final lang = languageName(t.language) ?? t.language;
  final parts = <String>[
    ?title,
    if (lang != null && lang != title) lang,
  ];
  if (kind == 'audio') {
    final ch = (t.channels ?? '') as String;
    final channels = switch (ch) {
      'unknown2' || 'stereo' => 'Stereo',
      'unknown1' || 'mono' => 'Mono',
      'unknown6' || '5.1' || '5.1(side)' => '5.1',
      'unknown8' || '7.1' => '7.1',
      _ => ch.isEmpty ? null : ch,
    };
    if (channels != null) parts.add(channels);
  }
  final String? codec = t.codec;
  if (codec != null) parts.add(codec.toUpperCase());
  if (parts.isEmpty) parts.add('${kind == 'audio' ? 'Audio' : 'Subtitles'} $n');
  return parts.join(' · ');
}

/// The audio or subtitle track in [tracks] that best matches [pick] (a choice remembered for the
/// collection): same language and name, else same language, else same name. Null when none does
/// (the file's own default is kept). [tracks] are media_kit AudioTracks or SubtitleTracks.
T? matchTrack<T>(List<T> tracks, TrackPick pick) {
  final real = [for (final t in tracks) if ((t as dynamic).id != 'auto' && (t as dynamic).id != 'no') t];
  for (final t in real) {
    final d = t as dynamic;
    if (d.language == pick.language && d.title == pick.title) return t;
  }
  for (final t in real) {
    if ((t as dynamic).language == pick.language && pick.language != null) return t;
  }
  for (final t in real) {
    if ((t as dynamic).title == pick.title && pick.title != null) return t;
  }
  return null;
}

/// A video's page (0.1.42): a loading page shows straight away, with the video's picture and
/// "Opening …", while the real page (and its player) starts behind it; it fades away once the
/// video's first picture is on screen (or it is playing, or it can't be played; after 12 s at
/// the latest). Before, the app could look frozen for a moment while a big file opened.
class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  const VideoPlayerScreen({super.key, required this.videoId});

  /// Tests: build this instead of the real page (which needs the video engine).
  @visibleForTesting
  static Widget Function(String videoId, VoidCallback onReady)? debugPage;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  /// The real page has been started (after the page's slide-in, so that stays smooth).
  bool _started = false;

  /// The video is showing: the loading page fades away.
  bool _ready = false;

  /// The loading page has faded away and is no longer built.
  bool _gone = false;

  Animation<double>? _routeAnimation;
  Timer? _startTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || _routeAnimation != null) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) {
      // Not on its own page: start after this first frame, so the loading page shows.
      _startTimer = Timer(const Duration(milliseconds: 16), _start);
      return;
    }
    // Start once the slide-in has finished. (The page's very first frame is drawn off screen,
    // where its animation already reads as finished, so wait to be told it has finished.)
    _routeAnimation = animation..addStatusListener(_onRouteStatus);
    // In case the slide-in never reports finishing (or there isn't one).
    _startTimer = Timer(const Duration(milliseconds: 400), _start);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _start();
  }

  void _start() {
    _startTimer?.cancel();
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    if (!mounted || _started) return;
    setState(() => _started = true);
  }

  void _onReady() {
    if (!mounted || _ready) return;
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = !_started
        ? null
        : VideoPlayerScreen.debugPage?.call(widget.videoId, _onReady) ??
            _VideoPage(videoId: widget.videoId, onReady: _onReady);
    return Stack(children: [
      if (page != null) Positioned.fill(child: page),
      if (!_gone)
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _ready,
            child: AnimatedOpacity(
              opacity: _ready ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              onEnd: () {
                if (_ready && mounted) setState(() => _gone = true);
              },
              child: VideoLoadingView(videoId: widget.videoId),
            ),
          ),
        ),
    ]);
  }
}

/// The loading page: the video's name and picture, with a spinner. Back works as usual.
class VideoLoadingView extends StatelessWidget {
  final String videoId;
  const VideoLoadingView({super.key, required this.videoId});

  @override
  Widget build(BuildContext context) {
    final videos = Provider.of<VideoLibraryModel?>(context);
    final v = videos?.byId(videoId);
    final picture = v == null ? null : videos!.thumbFile(v);
    final label = v == null ? null : [v.collection, ?v.episodeLabel].join(' · ');
    return Scaffold(
      key: const ValueKey('video-loading'),
      appBar: AppBar(title: Text(v?.title ?? 'Video', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: AppShape.circular(8),
                  child: Stack(fit: StackFit.expand, children: [
                    Container(color: Colors.black),
                    if (picture != null)
                      Opacity(
                        opacity: 0.6,
                        child: Image.file(File(picture), fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      ),
                    const Center(child: CircularProgressIndicator()),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                v == null ? 'Opening the video…' : 'Opening ${v.title}…',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              if (label != null) ...[
                const SizedBox(height: 4),
                Text(label, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final String videoId;

  /// Called once, when the first video is showing (or can't be played).
  final VoidCallback? onReady;
  const _VideoPage({required this.videoId, this.onReady});

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  // Windows: the engine draws subtitles (libass), so styled and picture subtitles work.
  final Player _player =
      Player(configuration: PlayerConfiguration(title: 'HomeTunes video', libass: !Platform.isAndroid));
  // 0.1.57: on a phone, drawn straight from the video chip unless Settings › Videos says not
  // (services/video_drawing.dart). First used in initState, after _settings is set.
  late final VideoController _controller =
      VideoController(_player, configuration: videoDrawing(direct: _settings.videoDirectDrawing));
  // Playback stats in the Playback log (0.1.55): decoding, dropped pictures, waits. Null in tests.
  late final VideoStats? _stats = VideoStats.forPlayer(_player, 'Video');
  // Keeps the same Video widget (and its picture) when switching between normal and enlarged,
  // and reaches it to go full screen.
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  late final VideoLibraryModel _videos;
  late final PlayerModel _music;
  late final LibraryModel _settings;
  // The equaliser (Settings › Videos can give videos their own preset). Null in tests without one.
  EqualizerModel? _eq;
  String? _appliedEq;
  // The video's sound's sample rate: equaliser bands at or above half of it are left out, or the
  // engine rejects the whole equaliser (refactor phase 1: before, the 16 kHz band was always sent,
  // so a video with 22 kHz sound had no equaliser at all). Same rule as the music player.
  int? _sampleRate;
  // What the bottom bar and media keys use to reach this player. Null in tests without one.
  NowWatching? _watching;
  late final VideoTransport _transport = MediaKitTransport(_player, maxVolume: () => _settings.maxVolume);

  /// The speed now (starts at the collection's own, else Settings › Videos' usual one).
  double _speed = 1.0;
  final List<StreamSubscription> _subs = [];
  Timer? _saveTimer;

  /// The video playing now (the page moves on to the next one in its collection).
  late String _id = widget.videoId;

  /// The video on screen, for the previous / next buttons (0.1.71). They listen to this rather
  /// than being built with a fixed target: full screen keeps the controls it was opened with, so
  /// a target worked out then went stale after one press, and the next press replayed the video
  /// now playing.
  late final ValueNotifier<String> _shownId = ValueNotifier(widget.videoId);

  /// The video fills the whole page (the details are hidden).
  bool _enlarged = false;

  /// The file couldn't be found or opened.
  String? _problem;

  // Tracks: set up once per file, when the engine first lists them.
  bool _tracksSetUp = false;
  String _aid = 'auto', _sid = 'auto';

  // Playing on: the next video and the seconds left before it starts.
  VideoItem? _upNext;
  int _countdown = 0;
  Timer? _upNextTimer;

  // Opening (0.1.42): a video is being opened and isn't showing yet. The first time, the loading
  // page covers the whole page; for the next / previous video a spinner shows on the picture.
  bool _opening = false;
  Timer? _openingTimer;
  bool _toldReady = false;

  /// The video is showing (or can't be played): stop the spinner and lift the loading page.
  void _shown() {
    _openingTimer?.cancel();
    if (!mounted) return;
    if (_opening) setState(() => _opening = false);
    if (!_toldReady) {
      _toldReady = true;
      // Not straight away: this can happen while the page is first being built.
      final onReady = widget.onReady;
      if (onReady != null) Future.microtask(onReady);
    }
  }

  @override
  void initState() {
    super.initState();
    _videos = context.read<VideoLibraryModel>();
    _music = context.read<PlayerModel>();
    _music.addListener(_onMusicChanged);
    // The bottom bar and the system media controls show and control this video (30 Sep).
    _watching = Provider.of<NowWatching?>(context, listen: false);
    _watching?.attach(_transport, onOpen: _bringBack);
    _settings = _videos.library;
    _eq = Provider.of<EqualizerModel?>(context, listen: false);
    _eq?.addListener(_applyEqualizer);
    // Volume boost (0.1.62): the volume can go above 100 up to Settings › Playback's top.
    _settings.addListener(_followVolumeTop);
    _engine?.setProperty('volume-max', '$engineVolumeMax');
    _subs.addAll([
      _player.stream.completed.listen((done) {
        if (done) _finished();
      }),
      _player.stream.error.listen((e) {
        if (mounted && _player.state.duration == Duration.zero) {
          setState(() => _problem = 'Can\'t play this video: $e');
          _shown();
        }
      }),
      // Playing and moving on: it's showing (some files never report a first picture).
      _player.stream.position.listen((at) {
        _stats?.moved(at); // 0.1.58: skips are noted in the Playback log
        if (_opening && at > Duration.zero && _player.state.playing) _shown();
      }),
      _player.stream.playing.listen((playing) {
        // One thing at a time: whenever the video starts (or carries on), the music or
        // audiobook pauses (30 Sep: before, only when the page first opened).
        if (playing && _music.playing) _music.pause();
        if (!playing) _savePlace();
        _stats?.playing(playing);
      }),
      _player.stream.buffering.listen((b) => _stats?.buffering(b)),
      _player.stream.audioParams.listen((a) {
        final r = a.sampleRate;
        if (r != null && r > 0 && r != _sampleRate) {
          _sampleRate = r;
          _applyEqualizer();
        }
      }),
      _player.stream.tracks.listen((_) => _setUpTracks()),
      _player.stream.track.listen((_) => _readCurrentTracks()),
    ]);
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_player.state.playing) _savePlace();
    });
    // The first video's first picture is on screen (this only happens once per player).
    _controller.waitUntilFirstFrameRendered.then((_) => _shown());
    _open(_id);
  }

  /// The previous / next video buttons: keep this one's place, then open that one.
  void _goTo(String id) {
    if (!mounted || id == _id) return;
    _savePlace();
    _open(id);
  }

  /// The video before / after [id] in its collection, or null at either end.
  VideoItem? _neighbour(String id, {required bool forward}) {
    final v = _videos.byId(id);
    if (v == null) return null;
    return forward ? _videos.after(v) : _videos.before(v);
  }

  /// Previous / next video, worked out when pressed from the video playing now (0.1.71).
  void _jump({required bool forward}) {
    final target = _neighbour(_id, forward: forward);
    if (target != null) _goTo(target.id);
  }

  Future<void> _open(String id) async {
    final v = _videos.byId(id);
    final file = v == null ? null : _videos.playableFile(v);
    _shownId.value = id;
    setState(() {
      _id = id;
      _problem = null;
      _tracksSetUp = false;
      _upNext = null;
      _aid = 'auto';
      _sid = 'auto';
      _opening = true;
    });
    _upNextTimer?.cancel();
    // At the latest after 12 s: don't keep a spinner up for ever.
    _openingTimer?.cancel();
    _openingTimer = Timer(const Duration(seconds: 12), _shown);
    if (v == null || file == null) {
      setState(() => _problem = 'This video isn\'t there any more. Rescan your video folders to tidy the list.');
      _shown();
      return;
    }
    final next = _videos.after(v), previous = _videos.before(v);
    _watching?.showing(v,
        picture: _videos.thumbFile(v),
        skipBack: _settings.videoSkipBackSeconds,
        skipForward: _settings.videoSkipForwardSeconds,
        onNext: next == null ? null : () => _jump(forward: true),
        onPrevious: previous == null ? null : () => _jump(forward: false),
        transport: _transport);
    // One thing at a time: the music pauses while a video plays.
    if (_music.playing) await _music.pause();
    final place = _videos.placeOf(v.id);
    var start = resumeAt(place, v.duration);
    // Settings › Videos: go back a little, more after a long break (like audiobooks).
    if (start > Duration.zero && place != null && _settings.videoRewindOnResume) {
      final since = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(place.updatedMs));
      start -= PlayerModel.resumeRewind(since);
      if (start < Duration.zero) start = Duration.zero;
    }
    await _applyEqualizer();
    _stats?.started(v.episodeLabel == null ? v.title : '${v.collection} ${v.episodeLabel}');
    await _player.open(Media(file, start: start > Duration.zero ? start : null));
    _speed = _videos.speedFor(v.collection);
    await _player.setRate(_speed);
    if (start > Duration.zero && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Carrying on from ${videoLength(start)}'),
        action: SnackBarAction(label: 'Start over', onPressed: () => _player.seek(Duration.zero)),
      ));
    }
  }

  // ---- audio and subtitles ----

  NativePlayer? get _engine => _player.platform is NativePlayer ? _player.platform as NativePlayer : null;

  /// When the file's tracks are known: add the subtitle files beside it, then pick the audio and
  /// subtitles last chosen in this collection.
  Future<void> _setUpTracks() async {
    if (_tracksSetUp) return;
    final real = _player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no');
    if (real.isEmpty && _player.state.duration == Duration.zero) return; // not loaded yet
    _tracksSetUp = true;
    final v = _videos.byId(_id);
    if (v == null) return;
    final engine = _engine;
    if (engine != null) {
      for (final s in v.subtitles) {
        // Only files inside the video folders (a restored backup could name any path).
        if (!isUsableLocalFile(s, roots: _videos.library.videoFolders, extensions: subtitleExtensions)) continue;
        final label = subtitleLabel(s, v.path);
        try {
          await engine.command(['sub-add', s, 'auto', '$label (file)', _codeFor(label) ?? '']);
        } catch (_) {}
      }
    }
    final choice = _videos.trackChoiceFor(v.collection);
    await Future<void>.delayed(const Duration(milliseconds: 200)); // let the added files show up
    if (choice.audio != null) {
      final t = choice.audio!.off ? AudioTrack.no() : _match(_player.state.tracks.audio, choice.audio!);
      if (t != null) await _player.setAudioTrack(t);
    }
    if (choice.subtitles != null) {
      final t = choice.subtitles!.off ? SubtitleTrack.no() : _match(_player.state.tracks.subtitle, choice.subtitles!);
      if (t != null) await _player.setSubtitleTrack(t);
    }
    await _readCurrentTracks();
  }

  T? _match<T>(List<T> tracks, TrackPick pick) => matchTrack(tracks, pick);

  /// Which audio and subtitle track the engine is really using ("auto" resolves to one).
  Future<void> _readCurrentTracks() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      final aid = await engine.getProperty('aid');
      final sid = await engine.getProperty('sid');
      if (mounted) {
        setState(() {
          _aid = aid;
          _sid = sid;
        });
      }
    } catch (_) {}
  }

  // ---- skipping, speed and the equaliser (Settings › Videos) ----

  /// Back ([forward] false) or forward by the seconds set in Settings › Videos.
  void _skip({required bool forward}) {
    final by = Duration(seconds: forward ? _settings.videoSkipForwardSeconds : _settings.videoSkipBackSeconds);
    var to = forward ? _player.state.position + by : _player.state.position - by;
    if (to < Duration.zero) to = Duration.zero;
    final length = _player.state.duration;
    if (length > Duration.zero && to > length) to = length;
    _player.seek(to);
  }

  static IconData skipIcon({required bool forward, required int seconds}) => switch ((forward, seconds)) {
        (false, 5) => Icons.replay_5,
        (false, 10) => Icons.replay_10,
        (false, 30) => Icons.replay_30,
        (true, 5) => Icons.forward_5,
        (true, 10) => Icons.forward_10,
        (true, 30) => Icons.forward_30,
        (false, _) => Icons.fast_rewind,
        (true, _) => Icons.fast_forward,
      };

  Future<void> _setSpeed(double speed) async {
    await _player.setRate(speed);
    if (mounted) setState(() => _speed = speed);
    final v = _videos.byId(_id);
    if (v != null) _videos.rememberSpeed(v.collection, speed);
  }

  Future<void> _chooseSpeed(BuildContext from) async {
    final collection = _videos.byId(_id)?.collection;
    final picked = await showDialog<double>(
      context: from,
      useRootNavigator: true,
      builder: (context) => SimpleDialog(
        title: const Text('Speed'),
        children: [
          for (final s in PlayerModel.speeds)
            SimpleDialogOption(
              key: ValueKey('speed-$s'),
              onPressed: () => Navigator.of(context).pop(s),
              child: Row(children: [
                Icon(s == _speed ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 20, color: s == _speed ? Theme.of(context).colorScheme.primary : null),
                const SizedBox(width: 12),
                Text(SpeedButton.label(s)),
              ]),
            ),
          if (collection != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text('Used for the rest of "$collection" too.', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ),
        ],
      ),
    );
    if (picked != null) await _setSpeed(picked);
  }

  /// The volume boost's top was lowered (or the boost turned off): bring a louder volume down.
  void _followVolumeTop() {
    final max = _settings.maxVolume;
    if (sliderVolume(_player.state.volume) > max + 0.01) _player.setVolume(engineVolume(max));
  }

  /// Sends the videos' equaliser preset to this player: the bands as a filter, and the overall
  /// level as mpv's `replaygain-fallback` (the gain used for files without ReplayGain tags, as
  /// videos are), so the volume slider stays the listener's. A volume filter in the lavfi graph
  /// stalled playback on this engine (tool/bench/frame_picker_engine_test.dart).
  Future<void> _applyEqualizer() async {
    if (_eqBusy) {
      _eqAgain = true;
      return;
    }
    _eqBusy = true;
    try {
      do {
        _eqAgain = false;
        await _sendEqualizer();
      } while (_eqAgain && mounted);
    } finally {
      _eqBusy = false;
    }
  }

  bool _eqBusy = false;
  bool _eqAgain = false;

  Future<void> _sendEqualizer() async {
    final (:filter, :level) = videoEqualizerSettings(_eq?.activeForVideos, sampleRate: _sampleRate);
    if ('$filter|$level' == _appliedEq) return;
    final engine = _engine;
    if (engine == null) return;
    _appliedEq = '$filter|$level';
    try {
      await engine.setProperty('af', filter);
      await engine.setProperty('replaygain-fallback', level);
    } catch (e) {
      debugPrint('HomeTunes: the video player refused the equaliser: $e');
    }
  }

  /// The frame on screen now becomes the video's picture.
  Future<void> _useThisFrame(VideoItem v) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final shot = await _player.screenshot(format: 'image/jpeg');
      if (shot == null) throw const FormatException('No picture came from the video yet');
      await _videos.setPicture(v, await preparePicture(shot));
      messenger?.showSnackBar(const SnackBar(content: Text('This frame is now its picture')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t use this frame: ${e is FormatException ? e.message : e}')));
    }
  }

  Future<void> _chooseTracks(BuildContext from) async {
    await showDialog<void>(
      context: from,
      useRootNavigator: true,
      builder: (_) => StatefulBuilder(builder: (context, setDialog) {
        final audio = [for (final t in _player.state.tracks.audio) if (t.id != 'auto' && t.id != 'no') t];
        final subs = [for (final t in _player.state.tracks.subtitle) if (t.id != 'auto' && t.id != 'no') t];
        final collection = _videos.byId(_id)?.collection;
        Future<void> pickAudio(AudioTrack? t) async {
          await _player.setAudioTrack(t ?? AudioTrack.no());
          if (collection != null) {
            _videos.rememberTrackChoice(collection,
                audio: t == null ? TrackPick.none : TrackPick(language: t.language, title: t.title));
          }
          await _readCurrentTracks();
          setDialog(() {});
        }

        Future<void> pickSub(SubtitleTrack? t) async {
          await _player.setSubtitleTrack(t ?? SubtitleTrack.no());
          if (collection != null) {
            _videos.rememberTrackChoice(collection,
                subtitles: t == null ? TrackPick.none : TrackPick(language: t.language, title: t.title));
          }
          await _readCurrentTracks();
          setDialog(() {});
        }

        Widget option(String label, bool selected, VoidCallback onTap, {Key? key}) => ListTile(
              key: key,
              dense: true,
              leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? Theme.of(context).colorScheme.primary : null),
              title: Text(label),
              onTap: onTap,
            );

        return AlertDialog(
          title: const Text('Audio and subtitles'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Audio', style: TextStyle(fontWeight: FontWeight.w700)),
                for (var i = 0; i < audio.length; i++)
                  option(trackLabel('audio', audio[i], i + 1), _aid == audio[i].id, () => pickAudio(audio[i]),
                      key: ValueKey('audio-${audio[i].id}')),
                option('Off (no sound)', _aid == 'no', () => pickAudio(null), key: const ValueKey('audio-off')),
                const SizedBox(height: 12),
                const Text('Subtitles', style: TextStyle(fontWeight: FontWeight.w700)),
                option('Off', _sid == 'no', () => pickSub(null), key: const ValueKey('subtitles-off')),
                for (var i = 0; i < subs.length; i++)
                  option(trackLabel('subtitles', subs[i], i + 1), _sid == subs[i].id, () => pickSub(subs[i]),
                      key: ValueKey('subtitles-${subs[i].id}')),
                if (subs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text('This video has no subtitles.', style: TextStyle(color: AppColors.textDim)),
                  ),
                if (collection != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Your choice is used for the rest of "$collection" too.',
                        style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
        );
      }),
    );
  }

  // ---- places and playing on ----

  /// Music started while the video plays: pause the video.
  void _onMusicChanged() {
    if (_music.playing && _player.state.playing) _player.pause();
  }

  void _savePlace({bool end = false}) {
    final length = _player.state.duration;
    if (length <= Duration.zero) return;
    final at = end ? length : _player.state.position;
    if (at <= Duration.zero) return;
    _videos.savePlace(_id, at, length);
  }

  /// The end: counts as watched, then the next video in the collection starts after a countdown.
  void _finished() {
    _savePlace(end: true);
    final v = _videos.byId(_id);
    final next = v == null ? null : _videos.after(v);
    if (next == null || !mounted) return;
    setState(() {
      _upNext = next;
      _countdown = 10;
    });
    _upNextTimer?.cancel();
    _upNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_countdown <= 1) {
        t.cancel();
        _open(next.id);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _cancelUpNext() {
    _upNextTimer?.cancel();
    setState(() => _upNext = null);
  }

  @override
  void dispose() {
    // Save the place once this frame is done (telling the Videos tab during dispose would redraw
    // it while the widget tree is locked).
    final length = _player.state.duration, at = _player.state.position;
    final id = _id, videos = _videos;
    if (length > Duration.zero && at > Duration.zero) Future.microtask(() => videos.savePlace(id, at, length));
    _saveTimer?.cancel();
    _upNextTimer?.cancel();
    _openingTimer?.cancel();
    _music.removeListener(_onMusicChanged);
    _watching?.detach(_transport);
    _eq?.removeListener(_applyEqualizer);
    _settings.removeListener(_followVolumeTop);
    for (final s in _subs) {
      s.cancel();
    }
    _stats?.dispose();
    _player.dispose();
    _shownId.dispose();
    super.dispose();
  }

  Future<void> _fullScreen() async => _videoKey.currentState?.enterFullscreen();

  /// The bottom bar's video was tapped: back to the Videos tab, with this page on top.
  ///
  /// 1 Oct fix: this used selectTab, which on the Videos tab itself went back to the tab's first
  /// page (closing this one), and then popUntil never found this page and emptied the tab, which
  /// stayed blank until a restart. Now the tab is only switched to, pages above this one are closed
  /// only while this one is still in the stack, and the tab's first page is never closed.
  void _bringBack() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    context.read<AppNav>().showTab(AppNav.videosTab);
    if (route != null && route.isActive && !route.isCurrent) {
      Navigator.of(context).popUntil((r) => r == route || r.isFirst);
    }
  }

  /// The video with its controls, plus the Audio and subtitles button (in full screen too).
  Widget _videoWidget() {
    final tracksButton = Builder(
      builder: (context) => MaterialDesktopCustomButton(
        icon: const Icon(Icons.subtitles_outlined),
        onPressed: () => _chooseTracks(context),
      ),
    );
    // Skip buttons and speed (Settings › Videos sets how far the skips go).
    final back = _settings.videoSkipBackSeconds, ahead = _settings.videoSkipForwardSeconds;
    // Colours, sizes and the backing behind each button (Settings › Appearance › Video player).
    final look = _settings.videoPlayerLook, accent = AppColors.accent;
    final speedButton = Builder(
      builder: (context) => MaterialDesktopCustomButton(icon: const Icon(Icons.speed), onPressed: () => _chooseSpeed(context)),
    );
    // Previous / next video in the collection (30 Sep); greyed out at either end. Worked out from
    // the video on screen each time it changes, and again when pressed (0.1.71): full screen keeps
    // these controls from when it opened, so nothing here may hold on to one video.
    final buttonColour = look.buttons(accent);
    Widget jump({required bool forward, required double size}) => ValueListenableBuilder<String>(
          valueListenable: _shownId,
          builder: (context, id, _) {
            final target = _neighbour(id, forward: forward);
            return IconButton(
              key: ValueKey(forward ? 'video-next' : 'video-previous'),
              tooltip: target == null
                  ? (forward ? 'No next video' : 'No previous video')
                  : '${forward ? 'Next' : 'Previous'}: ${[?target.episodeLabel, target.title].join(' · ')}',
              iconSize: size,
              color: buttonColour,
              disabledColor: buttonColour.withValues(alpha: 0.3),
              icon: Icon(forward ? Icons.skip_next_rounded : Icons.skip_previous_rounded),
              onPressed: target == null ? null : () => _jump(forward: forward),
            );
          },
        );

    final desktopBar = [
      jump(forward: false, size: look.size.desktop),
      MaterialDesktopCustomButton(
          icon: Icon(skipIcon(forward: false, seconds: back)), onPressed: () => _skip(forward: false)),
      const MaterialDesktopPlayOrPauseButton(),
      MaterialDesktopCustomButton(
          icon: Icon(skipIcon(forward: true, seconds: ahead)), onPressed: () => _skip(forward: true)),
      jump(forward: true, size: look.size.desktop),
      // 0.1.62: our own volume (media_kit's stops at 100), up to the volume boost's top.
      _VideoBarVolume(player: _player, maxVolume: () => _settings.maxVolume, look: look, accent: accent),
      paddedTime(MaterialDesktopPositionIndicator(style: timeTextStyle(look, accent))),
      const Spacer(),
      // The sleep timer (0.1.63).
      VideoSleepTimerButton(iconSize: look.size.desktop, color: look.buttons(accent)),
      speedButton,
      tracksButton,
      const MaterialDesktopFullscreenButton(),
    ];
    // Keys: as media_kit's, but ← → and J / L skip by the chosen amounts.
    final keys = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.mediaPlay): _player.play,
      const SingleActivator(LogicalKeyboardKey.mediaPause): _player.pause,
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): _player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.space): _player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.keyK): _player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _skip(forward: false),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => _skip(forward: true),
      const SingleActivator(LogicalKeyboardKey.keyJ): () => _skip(forward: false),
      const SingleActivator(LogicalKeyboardKey.keyL): () => _skip(forward: true),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
          _player.setVolume(stepEngineVolume(_player.state.volume, 5, _settings.maxVolume)),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          _player.setVolume(stepEngineVolume(_player.state.volume, -5, _settings.maxVolume)),
      // Shift+N / Shift+P: next / previous video (as on YouTube).
      // (Worked out when pressed, 0.1.71: full screen keeps these keys from when it opened.)
      const SingleActivator(LogicalKeyboardKey.keyN, shift: true): () => _jump(forward: true),
      const SingleActivator(LogicalKeyboardKey.keyP, shift: true): () => _jump(forward: false),
      const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () => _jump(forward: true),
      const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () => _jump(forward: false),
      const SingleActivator(LogicalKeyboardKey.keyF): () => _videoKey.currentState?.toggleFullscreen(),
      const SingleActivator(LogicalKeyboardKey.escape): () => _videoKey.currentState?.exitFullscreen(),
    };
    final phoneTracks = Builder(
      builder: (context) => MaterialCustomButton(
        icon: const Icon(Icons.subtitles_outlined),
        onPressed: () => _chooseTracks(context),
      ),
    );
    final phoneSpeed = Builder(
      builder: (context) => MaterialCustomButton(icon: const Icon(Icons.speed), onPressed: () => _chooseSpeed(context)),
    );
    final phoneBar = [
      jump(forward: false, size: look.size.phone),
      MaterialCustomButton(icon: Icon(skipIcon(forward: false, seconds: back)), onPressed: () => _skip(forward: false)),
      MaterialCustomButton(icon: Icon(skipIcon(forward: true, seconds: ahead)), onPressed: () => _skip(forward: true)),
      jump(forward: true, size: look.size.phone),
      paddedTime(MaterialPositionIndicator(style: timeTextStyle(look, accent, phone: true))),
      const Spacer(),
      VideoSleepTimerButton(iconSize: look.size.phone, color: look.buttons(accent)), // 0.1.63
      phoneSpeed,
      phoneTracks,
      const MaterialFullscreenButton(),
    ];
    // Full screen (0.1.59): a round "Leave full screen" button in the top corner, like the ones
    // on the picture in the page, shown and hidden with the other controls.
    final fullTop = <Widget>[
      // (No padding: media_kit gives the row its side margins, and a button bar's height.)
      Builder(
        builder: (context) => _OverlayButton(
          key: const ValueKey('video-leave-fullscreen'),
          icon: Icons.fullscreen_exit,
          tooltip: 'Leave full screen',
          onPressed: () => exitFullscreen(context),
        ),
      ),
      // And the "Always on top" pin in the other corner (0.1.60, the PC only).
      const Spacer(),
      const AlwaysOnTopButton(round: true),
    ];
    // Double-tap the left or right of the picture on a phone: skip by the chosen amounts too.
    MaterialVideoControlsThemeData phone({bool full = false}) => phoneControlsTheme(look, accent,
        bar: phoneBar,
        skipBack: Duration(seconds: back),
        skipForward: Duration(seconds: ahead),
        top: full ? fullTop : const []);
    MaterialDesktopVideoControlsThemeData desktop({bool full = false}) =>
        desktopControlsTheme(look, accent, bar: desktopBar, keys: keys, top: full ? fullTop : const []);
    return MaterialDesktopVideoControlsTheme(
      normal: desktop(),
      fullscreen: desktop(full: true),
      child: MaterialVideoControlsTheme(
        normal: phone(),
        fullscreen: phone(full: true),
        child: Video(
          key: _videoKey,
          controller: _controller,
          fill: Colors.black,
          // The mouse wheel: 5 s skips over the progress bar, volume elsewhere (30 Sep).
          controls: (state) => VideoWheel(
              player: _player,
              look: look,
              maxVolume: () => _settings.maxVolume,
              child: AdaptiveVideoControls(state)),
          // With libass the engine draws the subtitles into the picture; the app's own text
          // subtitles would show them twice.
          subtitleViewConfiguration: SubtitleViewConfiguration(visible: Platform.isAndroid),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = context.select<VideoLibraryModel, VideoItem?>((m) => m.byId(_id));
    final watched = context.select<VideoLibraryModel, bool>((m) => m.placeOf(_id)?.watched ?? false);
    // Settings › Appearance › Shrink to fit small windows (for the small-window layout, 0.1.68).
    final scaleWithWindow = context.select<LibraryModel, bool>((l) => l.scaleWithWindow);
    if (v == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This video isn\'t in your library any more.')));
    }

    final video = Stack(children: [
      Positioned.fill(
        child: _problem != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_problem!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                ),
              )
            : _videoWidget(),
      ),
      // The next / previous video is opening: a spinner over the picture until it shows.
      if (_opening && _problem == null && _toldReady)
        const Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              key: ValueKey('video-opening'),
              color: Colors.black45,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      if (_upNext != null)
        Positioned(
          right: 16,
          bottom: 80,
          child: Material(
            color: Colors.black87,
            borderRadius: AppShape.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Up next in $_countdown s', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    [?_upNext!.episodeLabel, _upNext!.title].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(onPressed: _cancelUpNext, child: const Text('Cancel')),
                  FilledButton(onPressed: () => _open(_upNext!.id), child: const Text('Play now')),
                ]),
              ]),
            ),
          ),
        ),
    ]);

    // Enlarged: the video fills the page, with a small bar to shrink it again.
    if (_enlarged) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(child: video),
          Positioned(
            left: 8,
            top: 8,
            child: _OverlayButton(
              icon: Icons.fullscreen_exit,
              tooltip: 'Shrink',
              onPressed: () => setState(() => _enlarged = false),
            ),
          ),
          // (0.1.59: no Full screen button at the top any more; the player's own one is in the
          // bottom corner.)
        ]),
      );
    }

    final facts = [
      ?v.episodeLabel,
      if (v.year != null) '${v.year}',
      if (v.genre != null) v.genre!,
      if (v.duration > Duration.zero) videoLength(v.duration),
      if (v.resolution != null) v.resolution!,
      v.format,
    ].join(' · ');
    final currentAudio = _player.state.tracks.audio.where((t) => t.id == _aid).firstOrNull;
    final currentSubs = _player.state.tracks.subtitle.where((t) => t.id == _sid).firstOrNull;
    final tracksSummary = [
      'Audio: ${_aid == 'no' ? 'off' : currentAudio == null ? 'normal' : trackLabel('audio', currentAudio, 1)}',
      'Subtitles: ${_sid == 'no' || currentSubs == null ? 'off' : trackLabel('subtitles', currentSubs, 1)}',
    ].join('   ');

    return Scaffold(
      appBar: AppBar(
        title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit details',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showEditVideos(context, [v]),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        // A small window on a computer (0.1.68): the video comes first. It may take more of the
        // page (70 % up to 85 % of its height), and the text and buttons under it shrink, but
        // never below three quarters of their usual size on screen (widgets/window_scale.dart).
        final view = View.of(context);
        final window = view.physicalSize / view.devicePixelRatio;
        final desktop = WindowScale.isDesktop;
        final appFactor = desktop && scaleWithWindow ? WindowScale.factorFor(window) : 1.0;
        final share = desktop ? WindowScale.videoShare(window) : 0.7;
        final infoScale = desktop ? WindowScale.videoInfoScale(window, appFactor: appFactor) : 1.0;
        // As big as fits: the video's own shape, at most [share] of the page's height.
        final ratio = (v.width != null && v.height != null && v.height! > 0) ? v.width! / v.height! : 16 / 9;
        var h = c.maxWidth / ratio;
        if (h > c.maxHeight * share) h = c.maxHeight * share;
        return ListView(children: [
          // 0.1.59: Enlarge on the picture too (like Shrink when it's enlarged); the buttons below
          // stay. Full screen is the player's own button in the bottom corner (a second one at
          // the top was taken off: the user found it doubled up).
          Container(
            color: Colors.black,
            height: h,
            child: Stack(children: [
              Positioned.fill(child: video),
              Positioned(
                left: 8,
                top: 8,
                child: _OverlayButton(
                  key: const ValueKey('video-overlay-enlarge'),
                  icon: Icons.open_in_full,
                  tooltip: 'Enlarge',
                  onPressed: () => setState(() => _enlarged = true),
                ),
              ),
            ]),
          ),
          ShrinkToWidth(
            scale: infoScale,
            child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableTitle(v.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              InkWell(
                onTap: () => context.read<AppNav>().openVideoCollection(v.collection),
                child: Text(v.collection,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 4),
              Text(facts, style: TextStyle(color: AppColors.textDim)),
              if (_tracksSetUp) Text(tracksSummary, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              const SizedBox(height: 12),
              // Main buttons first (watching); the others on a row below.
              Wrap(key: const ValueKey('main-buttons'), spacing: 8, runSpacing: 8, children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.open_in_full),
                  label: const Text('Enlarge'),
                  onPressed: () => setState(() => _enlarged = true),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.fullscreen),
                  label: const Text('Full screen'),
                  onPressed: _problem == null ? _fullScreen : null,
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('audio-and-subtitles'),
                  icon: const Icon(Icons.subtitles_outlined),
                  label: const Text('Audio and subtitles'),
                  onPressed: _problem == null ? () => _chooseTracks(context) : null,
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('video-speed'),
                  icon: const Icon(Icons.speed),
                  label: Text('Speed ${SpeedButton.label(_speed)}'),
                  onPressed: _problem == null ? () => _chooseSpeed(context) : null,
                ),
              ]),
              // The less-used ones on their own row, under the main ones.
              const SizedBox(height: 10),
              Wrap(key: const ValueKey('secondary-buttons'), spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.equalizer),
                  label: const Text('Equaliser'),
                  onPressed: () => openEqualizer(context, forVideos: true),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit details'),
                  onPressed: () => showEditVideos(context, [v]),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('use-this-frame'),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Use this frame as its picture'),
                  onPressed: _problem == null ? () => _useThisFrame(v) : null,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Change picture…'),
                  onPressed: () => showVideoPictureOptions(context, v),
                ),
                // Where it comes from and what's inside the file (0.1.44).
                OutlinedButton.icon(
                  key: const ValueKey('video-details'),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Details'),
                  onPressed: () => openVideoDetails(context, v),
                ),
                OutlinedButton.icon(
                  icon: Icon(watched ? Icons.remove_done : Icons.check_circle_outline),
                  label: Text(watched ? 'Mark as not watched' : 'Mark as watched'),
                  onPressed: () => _videos.setWatched([v.id], !watched),
                ),
                if (Platform.isWindows)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Show in folder'),
                    onPressed: () {
                      final file = _videos.playableFile(v);
                      if (file != null) Process.run('explorer', ['/select,', p.normalize(file)]);
                    },
                  ),
              ]),
              if (v.description != null) ...[
                const SizedBox(height: 16),
                SelectableText(v.description!),
              ],
              const SizedBox(height: 24),
            ]),
          ),
          ),
        ]);
      }),
    );
  }
}

/// A round, see-through button over a video.
class _OverlayButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _OverlayButton({super.key, required this.icon, required this.tooltip, required this.onPressed});

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

/// The video bar's volume on a computer (0.1.62, in place of media_kit's, which stops at 100):
/// the speaker (mute / unmute) and a slider from 0 to 100, or up to the volume boost's top.
/// Above 100 the sound is amplified (models/volume_boost.dart).
class _VideoBarVolume extends StatefulWidget {
  final Player player;
  final double Function() maxVolume;
  final VideoPlayerLook look;
  final Color accent;
  const _VideoBarVolume({required this.player, required this.maxVolume, required this.look, required this.accent});

  @override
  State<_VideoBarVolume> createState() => _VideoBarVolumeState();
}

class _VideoBarVolumeState extends State<_VideoBarVolume> {
  double _beforeMute = 100;

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    final buttons = widget.look.buttons(widget.accent), track = widget.look.seekTrack(widget.accent);
    // Redrawn as soon as the volume boost is changed in Settings, not only when the volume
    // moves (0.1.70).
    final top = context.select<LibraryModel?, double?>((l) => l?.maxVolume);
    return StreamBuilder<double>(
      stream: p.stream.volume,
      initialData: p.state.volume,
      builder: (context, snap) {
        final max = top ?? widget.maxVolume();
        final volume = sliderVolume(snap.data ?? 100).clamp(0.0, max);
        void set(double v) => p.setVolume(engineVolume(v.clamp(0.0, max)));
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            key: const ValueKey('video-bar-mute'),
            tooltip: volume <= 0 ? 'Unmute' : 'Mute',
            iconSize: widget.look.size.desktop,
            color: buttons,
            icon: Icon(volume <= 0 ? Icons.volume_off : (volume < 50 ? Icons.volume_down : Icons.volume_up)),
            onPressed: () {
              if (volume > 0) {
                _beforeMute = volume;
                set(0);
              } else {
                set(_beforeMute <= 0 ? 100 : _beforeMute);
              }
            },
          ),
          SizedBox(
            width: 96,
            child: Tooltip(
              message: 'Volume ${volume.round()}%',
              waitDuration: const Duration(milliseconds: 800),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: buttons,
                  inactiveTrackColor: track,
                  thumbColor: buttons,
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: VolumeSlider(sliderKey: const ValueKey('video-bar-volume'), value: volume, max: max, onChanged: set),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

/// A media_kit player as seen by [NowWatching] (the bottom bar and the system media controls).
/// The volume here is on the sliders' scale (0–100, or up to the volume boost's top, 0.1.62);
/// the engine's own number differs above 100 (models/volume_boost.dart).
class MediaKitTransport implements VideoTransport, VolumeTop {
  MediaKitTransport(this.player, {double Function()? maxVolume}) : _maxVolume = maxVolume ?? (() => 100);
  final Player player;
  final double Function() _maxVolume;

  @override
  double get maxVolume => _maxVolume();

  @override
  bool get playing => player.state.playing;
  @override
  Stream<bool> get playingStream => player.stream.playing;
  @override
  Duration get position => player.state.position;
  @override
  Stream<Duration> get positionStream => player.stream.position;
  @override
  Duration get duration => player.state.duration;
  @override
  Stream<Duration> get durationStream => player.stream.duration;
  @override
  double get volume => sliderVolume(player.state.volume);
  @override
  Stream<double> get volumeStream => player.stream.volume.map(sliderVolume);
  @override
  double get rate => player.state.rate;
  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> seek(Duration to) => player.seek(to);
  @override
  Future<void> setVolume(double volume) => player.setVolume(engineVolume(volume.clamp(0.0, maxVolume)));
}
