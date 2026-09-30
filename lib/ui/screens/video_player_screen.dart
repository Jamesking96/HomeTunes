// Videos (0.1.32): one video's player page, opened from the Videos tab or a collection's page.
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
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../services/path_safety.dart';
import '../../services/video_names.dart';
import '../../state/player_model.dart';
import '../../state/video_filters.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import 'edit_video.dart';
import 'video_pictures.dart';
import 'videos_screen.dart' show videoLength;

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

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  const VideoPlayerScreen({super.key, required this.videoId});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // Windows: the engine draws subtitles (libass), so styled and picture subtitles work.
  final Player _player =
      Player(configuration: PlayerConfiguration(title: 'HomeTunes video', libass: !Platform.isAndroid));
  late final VideoController _controller = VideoController(_player);
  // Keeps the same Video widget (and its picture) when switching between normal and enlarged,
  // and reaches it to go full screen.
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  late final VideoLibraryModel _videos;
  late final PlayerModel _music;
  final List<StreamSubscription> _subs = [];
  Timer? _saveTimer;

  /// The video playing now (the page moves on to the next one in its collection).
  late String _id = widget.videoId;

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

  @override
  void initState() {
    super.initState();
    _videos = context.read<VideoLibraryModel>();
    _music = context.read<PlayerModel>();
    _music.addListener(_onMusicChanged);
    _subs.addAll([
      _player.stream.completed.listen((done) {
        if (done) _finished();
      }),
      _player.stream.error.listen((e) {
        if (mounted && _player.state.duration == Duration.zero) setState(() => _problem = 'Can\'t play this video: $e');
      }),
      _player.stream.playing.listen((playing) {
        if (!playing) _savePlace();
      }),
      _player.stream.tracks.listen((_) => _setUpTracks()),
      _player.stream.track.listen((_) => _readCurrentTracks()),
    ]);
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_player.state.playing) _savePlace();
    });
    _open(_id);
  }

  Future<void> _open(String id) async {
    final v = _videos.byId(id);
    final file = v == null ? null : _videos.playableFile(v);
    setState(() {
      _id = id;
      _problem = null;
      _tracksSetUp = false;
      _upNext = null;
      _aid = 'auto';
      _sid = 'auto';
    });
    _upNextTimer?.cancel();
    if (v == null || file == null) {
      setState(() => _problem = 'This video isn\'t there any more. Rescan your video folders to tidy the list.');
      return;
    }
    // One thing at a time: the music pauses while a video plays.
    if (_music.playing) await _music.pause();
    final start = resumeAt(_videos.placeOf(v.id), v.duration);
    await _player.open(Media(file, start: start > Duration.zero ? start : null));
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
    _music.removeListener(_onMusicChanged);
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _fullScreen() async => _videoKey.currentState?.enterFullscreen();

  /// The video with its controls, plus the Audio and subtitles button (in full screen too).
  Widget _videoWidget() {
    final tracksButton = Builder(
      builder: (context) => MaterialDesktopCustomButton(
        icon: const Icon(Icons.subtitles_outlined),
        onPressed: () => _chooseTracks(context),
      ),
    );
    final desktopBar = [
      const MaterialDesktopSkipPreviousButton(),
      const MaterialDesktopPlayOrPauseButton(),
      const MaterialDesktopSkipNextButton(),
      const MaterialDesktopVolumeButton(),
      const MaterialDesktopPositionIndicator(),
      const Spacer(),
      tracksButton,
      const MaterialDesktopFullscreenButton(),
    ];
    final phoneTracks = Builder(
      builder: (context) => MaterialCustomButton(
        icon: const Icon(Icons.subtitles_outlined),
        onPressed: () => _chooseTracks(context),
      ),
    );
    final phoneBar = [const MaterialPositionIndicator(), const Spacer(), phoneTracks, const MaterialFullscreenButton()];
    return MaterialDesktopVideoControlsTheme(
      normal: MaterialDesktopVideoControlsThemeData(bottomButtonBar: desktopBar),
      fullscreen: MaterialDesktopVideoControlsThemeData(bottomButtonBar: desktopBar),
      child: MaterialVideoControlsTheme(
        normal: MaterialVideoControlsThemeData(bottomButtonBar: phoneBar),
        fullscreen: MaterialVideoControlsThemeData(bottomButtonBar: phoneBar),
        child: Video(
          key: _videoKey,
          controller: _controller,
          fill: Colors.black,
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
          Positioned(
            right: 8,
            top: 8,
            child: _OverlayButton(icon: Icons.fullscreen, tooltip: 'Full screen', onPressed: _fullScreen),
          ),
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
        // As big as fits: the video's own shape, at most 70 % of the page's height.
        final ratio = (v.width != null && v.height != null && v.height! > 0) ? v.width! / v.height! : 16 / 9;
        var h = c.maxWidth / ratio;
        if (h > c.maxHeight * 0.7) h = c.maxHeight * 0.7;
        return ListView(children: [
          Container(color: Colors.black, height: h, child: video),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
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
              Wrap(spacing: 8, runSpacing: 8, children: [
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
  const _OverlayButton({required this.icon, required this.tooltip, required this.onPressed});

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
