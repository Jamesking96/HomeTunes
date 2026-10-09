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
// Since refactor phase 5 (9 Oct 2026) the playing itself is a VideoSession
// (state/video_session.dart): this page draws it and turns taps into calls on it.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../models/video_player_look.dart';
import '../../models/volume_boost.dart';
import '../../services/engine/video_engine.dart';
import '../../services/video_drawing.dart';
import '../../services/video_stats.dart';
import '../../state/equalizer_model.dart';
import '../../state/library_model.dart';
import '../../state/now_watching.dart';
import '../../state/player_model.dart';
import '../../state/video_library_model.dart';
import '../../state/video_session.dart';
import '../../state/video_tracks.dart';
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

// The track helpers moved to state/video_tracks.dart (refactor phase 5); still available here.
export '../../state/video_tracks.dart' show languageName, trackLabel, matchTrack;
// videoEqualizerSettings moved to state/video_session.dart (refactor phase 7); still available here.
export '../../state/video_session.dart' show videoEqualizerSettings;

part 'video_player/video_bar_volume.dart';
part 'video_player/video_controls.dart';

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
  final MediaKitVideoEngine _engine = MediaKitVideoEngine();
  // 0.1.57: on a phone, drawn straight from the video chip unless Settings › Videos says not
  // (services/video_drawing.dart). Made in initState, after _settings is set.
  late final VideoController _controller =
      VideoController(_engine.player, configuration: videoDrawing(direct: _settings.videoDirectDrawing));
  // Keeps the same Video widget (and its picture) when switching between normal and enlarged,
  // and reaches it to go full screen.
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  late final LibraryModel _settings;

  /// Everything about playing (refactor phase 5): opening, previous / next, Up next, tracks,
  /// speed, places, the equaliser, the music and the bottom bar. This page only draws it.
  late final VideoSession _session;

  /// The video fills the whole page (the details are hidden).
  bool _enlarged = false;

  @override
  void initState() {
    super.initState();
    final videos = context.read<VideoLibraryModel>();
    _settings = videos.library;
    _controller; // made before the first video opens, as before
    _session = VideoSession(
      engine: _engine,
      videos: videos,
      music: context.read<PlayerModel>(),
      videoId: widget.videoId,
      watching: Provider.of<NowWatching?>(context, listen: false),
      equalizer: Provider.of<EqualizerModel?>(context, listen: false),
      // Playback stats in the Playback log (0.1.55). Null in tests.
      stats: VideoStats.forPlayer(_engine.player, 'Video'),
      onReady: widget.onReady,
      onCarryOn: _carryOn,
      onOpenPage: _bringBack,
    )..addListener(_redraw);
    // The first video's first picture is on screen (this only happens once per player).
    _controller.waitUntilFirstFrameRendered.then((_) => _session.shown());
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  /// The video opened part-way through: say so, with Start over.
  void _carryOn(Duration start) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Carrying on from ${videoLength(start)}'),
      action: SnackBarAction(label: 'Start over', onPressed: _session.startOver),
    ));
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

  @override
  void dispose() {
    _session.removeListener(_redraw);
    _session.dispose(); // saves the place, lets the bottom bar go, closes the player
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

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final id = s.id;
    final v = context.select<VideoLibraryModel, VideoItem?>((m) => m.byId(id));
    final watched = context.select<VideoLibraryModel, bool>((m) => m.placeOf(id)?.watched ?? false);
    // Settings › Appearance › Shrink to fit small windows (for the small-window layout, 0.1.68).
    final scaleWithWindow = context.select<LibraryModel, bool>((l) => l.scaleWithWindow);
    if (v == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This video isn\'t in your library any more.')));
    }
    final problem = s.problem, upNext = s.upNext;

    final video = Stack(children: [
      Positioned.fill(
        child: problem != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(problem, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                ),
              )
            : _videoWidget(),
      ),
      // The next / previous video is opening: a spinner over the picture until it shows.
      if (s.opening && problem == null && s.toldReady)
        const Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              key: ValueKey('video-opening'),
              color: Colors.black45,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      if (upNext != null)
        Positioned(
          right: 16,
          bottom: 80,
          child: Material(
            color: Colors.black87,
            borderRadius: AppShape.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Up next in ${s.countdown} s', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    [?upNext.episodeLabel, upNext.title].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(onPressed: s.cancelUpNext, child: const Text('Cancel')),
                  FilledButton(onPressed: s.playUpNextNow, child: const Text('Play now')),
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
    final currentAudio = s.audioTracks.where((t) => t.id == s.aid).firstOrNull;
    final currentSubs = s.subtitleTracks.where((t) => t.id == s.sid).firstOrNull;
    final tracksSummary = [
      'Audio: ${s.aid == 'no' ? 'off' : currentAudio == null ? 'normal' : trackLabel('audio', currentAudio, 1)}',
      'Subtitles: ${s.sid == 'no' || currentSubs == null ? 'off' : trackLabel('subtitles', currentSubs, 1)}',
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
              if (s.tracksSetUp) Text(tracksSummary, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
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
                  onPressed: problem == null ? _fullScreen : null,
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('audio-and-subtitles'),
                  icon: const Icon(Icons.subtitles_outlined),
                  label: const Text('Audio and subtitles'),
                  onPressed: problem == null ? () => _chooseTracks(context) : null,
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('video-speed'),
                  icon: const Icon(Icons.speed),
                  label: Text('Speed ${SpeedButton.label(s.speed)}'),
                  onPressed: problem == null ? () => _chooseSpeed(context) : null,
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
                  onPressed: problem == null ? () => _useThisFrame(v) : null,
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
                  onPressed: () => context.read<VideoLibraryModel>().setWatched([v.id], !watched),
                ),
                if (Platform.isWindows)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Show in folder'),
                    onPressed: () {
                      final file = context.read<VideoLibraryModel>().playableFile(v);
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
