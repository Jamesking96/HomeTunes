// The TV's video player (0.2.0, step 5 of the TV interface; mockup "Video player"). It's the
// framework for watching videos on the TV: the same playing as everywhere else (a VideoSession,
// state/video_session.dart: carrying on from the saved place, the collection's speed and
// audio / subtitle choice, saving the place, previous / next, Up next at the end, pausing the
// music, the equaliser), with controls made for the remote instead of media_kit's.
//
//  * The picture fills the screen. The controls show over it when it opens and with any press,
//    and fade after a few seconds of playing.
//  * The progress bar has focus: ← → move a marker along it with the picture at that spot above
//    it (the seek preview), OK jumps there (or it jumps when the remote rests), Back cancels; OK
//    with no marker plays / pauses.
//  * ↓ to the buttons: Play / Pause, back and forward by Settings › Videos' amounts, Audio &
//    subtitles, Speed, Episodes, Next episode, and More (Watch from the beginning, Previous, Mark
//    as watched, Sleep timer, Details, Go to the collection). Each choice opens in the options
//    panel.
//  * The remote's play / pause, rewind / fast-forward and next / previous keys work at any time.
//  * At the end: Up next, with a countdown, Play now and Cancel.
//  * Back: puts the marker away, else hides the controls, else closes the player.
// [TvVideoPlayerPage] makes the real player; [TvVideoView] is the screen itself, which tests
// drive with a pretend engine.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../services/engine/video_engine.dart';
import '../../services/seek_preview.dart';
import '../../services/video_drawing.dart';
import '../../services/video_stats.dart';
import '../../state/equalizer_model.dart';
import '../../state/now_watching.dart';
import '../../state/player_model.dart';
import '../../state/video_library_model.dart';
import '../../state/video_session.dart';
import '../../state/video_shuffle.dart';
import '../../state/video_sleep_timer.dart';
import '../../state/video_tracks.dart' show trackLabel;
import '../nav.dart';
import '../screens/video_details_screen.dart' show openVideoDetails;
import '../theme.dart';
import 'tv_browse.dart';
import 'tv_detail.dart' show TvIconButton;
import 'tv_focus.dart' show TvRegion, tvActivateKeys;
import 'tv_menus.dart' show tvNotice;
import 'tv_options.dart';
import 'tv_seek_bar.dart';

/// One video, full screen, with the TV controls. Pushed over everything (AppNav.openVideo in TV
/// mode).
class TvVideoPlayerPage extends StatefulWidget {
  const TvVideoPlayerPage({super.key, required this.videoId, this.shuffle});
  final String videoId;

  /// Playing the collection shuffled (0.2.6): plays on through this order.
  final VideoShuffle? shuffle;

  @override
  State<TvVideoPlayerPage> createState() => _TvVideoPlayerPageState();
}

class _TvVideoPlayerPageState extends State<TvVideoPlayerPage> {
  final MediaKitVideoEngine _engine = MediaKitVideoEngine();
  late final VideoController _controller;
  late final VideoSession _session;
  final SeekPreviewer _preview = SeekPreviewer();

  @override
  void initState() {
    super.initState();
    final videos = context.read<VideoLibraryModel>();
    _controller = VideoController(_engine.player, configuration: videoDrawing(direct: videos.library.settings.video.videoDirectDrawing));
    _session = VideoSession(
      engine: _engine,
      videos: videos,
      music: context.read<PlayerModel>(),
      videoId: widget.videoId,
      watching: Provider.of<NowWatching?>(context, listen: false),
      equalizer: Provider.of<EqualizerModel?>(context, listen: false),
      stats: VideoStats.forPlayer(_engine.player, 'Video'),
      onCarryOn: (from) {
        if (mounted) tvNotice(context, 'Carrying on from ${tvTime(from)} · Hold OK to watch from the beginning', aboveControls: true);
      },
      shuffle: widget.shuffle,
      onOpenPage: _bringBack,
    );
    _controller.waitUntilFirstFrameRendered.then((_) => _session.shown());
  }

  /// The menu's "now playing" was pressed while this player was covered: show it again.
  void _bringBack() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive && !route.isCurrent) {
      Navigator.of(context).popUntil((r) => r == route || r.isFirst);
    }
  }

  @override
  void dispose() {
    _session.dispose(); // saves the place, lets the bottom bar go, closes the player
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TvVideoView(
      session: _session,
      previewer: _preview,
      picture: Video(
        controller: _controller,
        fill: Colors.black,
        controls: NoVideoControls,
        // With libass (the PC) the engine draws the subtitles; on Android the app draws them.
        subtitleViewConfiguration: SubtitleViewConfiguration(visible: Platform.isAndroid),
      ),
    );
  }
}

/// The TV video screen over [picture], driving [session]. See the top of the file.
class TvVideoView extends StatefulWidget {
  const TvVideoView({super.key, required this.session, required this.picture, this.previewer});
  final VideoSession session;
  final Widget picture;
  final SeekPreviewer? previewer;

  /// How long the controls stay up while it plays and nothing is pressed.
  static const hideAfter = Duration(seconds: 5);

  @override
  State<TvVideoView> createState() => _TvVideoViewState();
}

class _TvVideoViewState extends State<TvVideoView> {
  VideoSession get _s => widget.session;
  VideoEngine get _engine => _s.engine;

  final _bar = TvSeekBarController();
  final _barNode = FocusNode(debugLabel: 'tv video bar');
  final _catcher = FocusNode(debugLabel: 'tv video (controls hidden)');
  final _playNowNode = FocusNode(debugLabel: 'tv up next play now');
  final _playNode = FocusNode(debugLabel: 'tv video play');
  bool _shown = true;
  bool _panelOpen = false;
  String? _upNextFor; // the Up next card that has had focus moved to it
  Timer? _hideTimer;
  StreamSubscription<bool>? _playingSub;

  @override
  void initState() {
    super.initState();
    _s.addListener(_changed);
    _bar.addListener(_barChanged);
    _playingSub = _engine.playingStream.listen((_) => _poke());
    _s.shownId.addListener(_newVideo);
    widget.previewer?.setVideo(_s.file);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _barNode.requestFocus();
    });
    _poke();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playingSub?.cancel();
    _s.removeListener(_changed);
    _s.shownId.removeListener(_newVideo);
    _bar.removeListener(_barChanged);
    _bar.dispose();
    _barNode.dispose();
    _catcher.dispose();
    _playNowNode.dispose();
    _playNode.dispose();
    super.dispose();
  }

  void _changed() {
    widget.previewer?.setVideo(_s.file);
    if (!mounted) return;
    setState(() {});
    // Up next appeared: the controls step aside and its Play now has focus.
    final next = _s.upNext;
    if (next != null && _upNextFor != next.id) {
      _upNextFor = next.id;
      _hide(focusCatcher: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _playNowNode.context != null) _playNowNode.requestFocus();
      });
    } else if (next == null && _upNextFor != null) {
      _upNextFor = null;
      _show();
    }
  }

  void _newVideo() {
    _bar.cancel();
    _show();
  }

  void _barChanged() {
    final to = _bar.target;
    final length = _engine.duration;
    final p = widget.previewer;
    final on = _s.settings.settings.video.videoSeekPreview;
    if (to != null && p != null && on && length > Duration.zero) p.request(to, length);
    _poke();
  }

  /// Something was pressed: the controls stay up a while longer (or until paused).
  void _poke() {
    _hideTimer?.cancel();
    if (!mounted) return;
    if (_engine.isPlaying && !_bar.scrubbing && !_panelOpen && _s.upNext == null) {
      _hideTimer = Timer(TvVideoView.hideAfter, () => _hide());
    }
  }

  void _show({bool focusBar = true}) {
    if (!mounted) return;
    final was = _shown;
    setState(() => _shown = true);
    if (!was && focusBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _barNode.requestFocus();
      });
    }
    _poke();
  }

  void _hide({bool focusCatcher = true}) {
    _hideTimer?.cancel();
    if (!mounted || !_shown) return;
    _bar.cancel();
    setState(() => _shown = false);
    if (focusCatcher) _catcher.requestFocus();
  }

  /// Back: the marker, then the controls, then the player itself. The controls go first whether
  /// it's playing or paused (27 Oct, the user: "pressing back should first hide the overlay if
  /// it's present, if not it back out of the video"; paused, Back used to close the player).
  void _back() {
    if (_bar.scrubbing) {
      _bar.cancel();
    } else if (_canHide) {
      _hide();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Back would hide the controls (rather than close the player).
  bool get _canHide => _shown && _s.problem == null && _s.upNext == null;

  /// A Back press was used here: its letting go is taken too (see [_key]).
  bool _backTaken = false;

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    // The remote's Back: Android goes back when it's let go (the system's Back, PopScope
    // below). So a press used here (the marker put away, the controls hidden) takes its letting
    // go too, or one press did that and then closed the player (27 Oct, seen on the Family room
    // TV). A press that would close the player is left to the system's Back, so its letting go
    // doesn't land on the page underneath and go back there as well.
    if (k == LogicalKeyboardKey.goBack) {
      if (e is KeyUpEvent) {
        final taken = _backTaken;
        _backTaken = false;
        return taken ? KeyEventResult.handled : KeyEventResult.ignored;
      }
      if (e is KeyDownEvent && (_bar.scrubbing || _canHide)) {
        _backTaken = true;
        _back();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    // The remote's media keys, whatever has focus.
    if (e is KeyDownEvent) {
      if (k == LogicalKeyboardKey.mediaPlayPause) return _do(_engine.playOrPause);
      if (k == LogicalKeyboardKey.mediaPlay) return _do(_engine.play);
      if (k == LogicalKeyboardKey.mediaPause) return _do(_engine.pause);
      if (k == LogicalKeyboardKey.mediaFastForward) return _do(() => _s.skip(forward: true));
      if (k == LogicalKeyboardKey.mediaRewind) return _do(() => _s.skip(forward: false));
      if (k == LogicalKeyboardKey.mediaTrackNext) return _do(() => _s.jump(forward: true));
      if (k == LogicalKeyboardKey.mediaTrackPrevious) return _do(() => _s.jump(forward: false));
      if (k == LogicalKeyboardKey.escape) {
        _back();
        return KeyEventResult.handled;
      }
    }
    final arrow =
        k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowDown;
    if (!_shown && _s.upNext == null && (arrow || tvActivateKeys.contains(k))) {
      // Hidden: the first press only brings the controls back.
      if (e is KeyDownEvent) _show();
      return KeyEventResult.handled;
    }
    // ↓ from the progress bar: Play / Pause, at the left (0.2.5). The bar spans the screen, so
    // every button was "below" it, and ↓ landed on Audio & subtitles.
    if (k == LogicalKeyboardKey.arrowDown && e is KeyDownEvent && _barNode.hasPrimaryFocus && !_bar.scrubbing && _playNode.context != null) {
      _playNode.requestFocus();
      _poke();
      return KeyEventResult.handled;
    }
    _poke();
    return KeyEventResult.ignored;
  }

  KeyEventResult _do(FutureOr<void> Function() f) {
    f();
    _show(focusBar: false);
    return KeyEventResult.handled;
  }

  /// Opens a panel; the controls stay up while it's open.
  Future<void> _panel(Future<void> Function() open) async {
    _panelOpen = true;
    _hideTimer?.cancel();
    await open();
    _panelOpen = false;
    if (mounted) _poke();
  }

  @override
  Widget build(BuildContext context) {
    final v = context.select<VideoLibraryModel, VideoItem?>((m) => m.byId(_s.id));
    final problem = _s.problem, upNext = _s.upNext;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          onKeyEvent: _key,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: problem != null ? const SizedBox.shrink() : widget.picture),
              // Takes focus while the controls are hidden, so the first press only shows them.
              Focus(focusNode: _catcher, child: const SizedBox.shrink()),
              if (problem != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Text(
                      problem,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, color: Colors.white70),
                    ),
                  ),
                ),
              if (_s.opening && problem == null)
                const Center(
                  child: SizedBox(width: 48, height: 48, child: CircularProgressIndicator(key: ValueKey('tv-video-opening'))),
                ),
              // The controls.
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_shown,
                  child: AnimatedOpacity(
                    opacity: _shown ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: ExcludeFocus(excluding: !_shown, child: _controls(context, v)),
                  ),
                ),
              ),
              if (upNext != null) Positioned(right: 40, bottom: 40, child: _upNextCard(upNext)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, VideoItem? v) {
    final video = _s.settings.settings.video;
    final back = video.videoSkipBackSeconds, ahead = video.videoSkipForwardSeconds;
    final next = _s.neighbour(_s.id, forward: true);
    final collection = v == null ? null : context.read<VideoLibraryModel>().collectionOf(v);
    final playing = _engine.isPlaying;
    return Stack(
      children: [
        // Shading top and bottom so the words show over any picture.
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 140,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xC0000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 260,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xE0000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
        if (v != null)
          Positioned(
            left: 48,
            right: 48,
            top: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A film's collection is usually its own name: then just the one title (0.2.5).
                if (v.collection != v.title || v.seasonLabel != null || v.episode != null)
                Text(
                  [
                    v.collection,
                    if (v.seasonLabel != null) 'Season ${v.seasonLabel}',
                    if (v.episode != null) 'Episode ${v.episode}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
                Text(
                  v.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                // Shuffling (0.2.6): what's shuffled and how far through.
                if (_s.shuffle case final shuffle?)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(key: const ValueKey('tv-video-shuffling'), children: [
                      const Icon(Icons.shuffle, size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('Shuffling ${shuffle.label} · ${shuffle.placeOf(v.id)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, color: Colors.white70)),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        Positioned(
          left: 48,
          right: 48,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TvSeekBar(
                key: const ValueKey('tv-video-bar'),
                controller: _bar,
                focusNode: _barNode,
                light: true,
                position: () => _engine.position,
                length: () => _engine.duration,
                positions: _engine.positionStream,
                onSeek: _engine.seek,
                onActivate: _engine.playOrPause,
                // Holding OK in the player: its options, Watch from the beginning first (23 Oct).
                onHold: () => _panel(() => _more(context, v)),
                onMoved: _poke,
                // No picture box where there can't be a picture (0.2.5): a server's video isn't
                // previewed (its stream would be fetched twice), and the box stood there empty
                // and black over the bar.
                preview: widget.previewer == null || _s.file == null || !_s.settings.settings.video.videoSeekPreview
                    ? null
                    : (target, length) => _PreviewPicture(previewer: widget.previewer!, target: target, length: length),
              ),
              const SizedBox(height: 12),
              // Its own region (23 Oct): ← → go by where the buttons are, so moving left out of the
              // scrolling part on the right reaches +s, −s and Play instead of losing its way.
              TvRegion(child: Row(
                children: [
                  TvIconButton(
                    key: const ValueKey('tv-video-play'),
                    focusNode: _playNode,
                    icon: playing ? Icons.pause : Icons.play_arrow,
                    label: playing ? 'Pause' : 'Play',
                    onPressed: _engine.playOrPause,
                  ),
                  const SizedBox(width: 10),
                  TvButton(key: const ValueKey('tv-video-back'), label: '−$back s', onPressed: () => _s.skip(forward: false)),
                  const SizedBox(width: 10),
                  TvButton(key: const ValueKey('tv-video-ahead'), label: '+$ahead s', onPressed: () => _s.skip(forward: true)),
                  const SizedBox(width: 24),
                  // The rest at the right; on a narrow screen they scroll rather than overflow.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TvButton(
                              key: const ValueKey('tv-video-tracks'),
                              label: 'Audio & subtitles',
                              icon: Icons.subtitles_outlined,
                              onPressed: () => _panel(() => _tracks(context)),
                            ),
                            const SizedBox(width: 10),
                            TvButton(
                              key: const ValueKey('tv-video-speed'),
                              label: 'Speed ${_speedText(_s.speed)}',
                              onPressed: () => _panel(() => _speed(context)),
                            ),
                            if (collection != null && collection.videos.length > 1) ...[
                              const SizedBox(width: 10),
                              TvButton(
                                key: const ValueKey('tv-video-episodes'),
                                label: 'Episodes',
                                icon: Icons.list,
                                onPressed: () => _panel(() => _episodes(context, collection)),
                              ),
                            ],
                            if (next != null) ...[
                              const SizedBox(width: 10),
                              TvButton(
                                key: const ValueKey('tv-video-next'),
                                label: 'Next',
                                icon: Icons.skip_next,
                                onPressed: () => _s.jump(forward: true),
                              ),
                            ],
                            const SizedBox(width: 10),
                            TvIconButton(
                              key: const ValueKey('tv-video-more'),
                              icon: Icons.more_horiz,
                              label: 'More options',
                              onPressed: () => _panel(() => _more(context, v)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              )),
            ],
          ),
        ),
      ],
    );
  }

  static String _speedText(double s) => '${s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toString()}×';

  Widget _upNextCard(VideoItem next) => Container(
    key: const ValueKey('tv-up-next'),
    width: 340,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xEE16181D),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.surfaceHigh),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_s.shuffle == null ? 'Up next in ${_s.countdown} s' : 'Up next (shuffled) in ${_s.countdown} s',
            style: const TextStyle(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 4),
        Text(
          [?next.episodeLabel, next.title].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            TvButton(
              key: const ValueKey('tv-up-next-play'),
              focusNode: _playNowNode,
              label: 'Play now',
              icon: Icons.play_arrow,
              primary: true,
              onPressed: _s.playUpNextNow,
            ),
            const SizedBox(width: 10),
            TvButton(key: const ValueKey('tv-up-next-cancel'), label: 'Cancel', onPressed: _s.cancelUpNext),
          ],
        ),
      ],
    ),
  );

  // ---- The panels ----

  Future<void> _tracks(BuildContext context) {
    final audio = [
      for (final t in _s.audioTracks)
        if (t.isReal) t,
    ];
    final subs = [
      for (final t in _s.subtitleTracks)
        if (t.isReal) t,
    ];
    String audioNow() {
      final i = audio.indexWhere((t) => t.id == _s.aid);
      return _s.aid == 'no' ? 'Off' : (i < 0 ? 'Automatic' : trackLabel('audio', audio[i], i + 1));
    }

    String subsNow() {
      final i = subs.indexWhere((t) => t.id == _s.sid);
      return _s.sid == 'no' || (i < 0 && subs.isEmpty) ? 'Off' : (i < 0 ? 'Automatic' : trackLabel('subtitles', subs[i], i + 1));
    }

    final collection = context.read<VideoLibraryModel>().byId(_s.id)?.collection;
    return showTvOptions(
      context,
      title: 'Audio & subtitles',
      subtitle: collection == null ? null : 'Remembered for all of $collection',
      options: [
        TvOption('Audio', Icons.volume_up_outlined, subtitle: audioNow(), opensMore: true, () {
          final current = audio.indexWhere((t) => t.id == _s.aid);
          _panel(
            () => showTvOptions(
              context,
              title: 'Audio',
              focusIndex: current < 0 ? (_s.aid == 'no' ? audio.length : 0) : current,
              options: [
                for (var i = 0; i < audio.length; i++)
                  TvOption(
                    trackLabel('audio', audio[i], i + 1),
                    audio[i].id == _s.aid ? Icons.check : Icons.volume_up_outlined,
                    () => _s.chooseAudio(audio[i]),
                  ),
                TvOption('Off (no sound)', _s.aid == 'no' ? Icons.check : Icons.volume_off_outlined, () => _s.chooseAudio(null)),
              ],
            ),
          );
        }),
        TvOption('Subtitles', Icons.subtitles_outlined, subtitle: subsNow(), opensMore: true, () {
          final current = subs.indexWhere((t) => t.id == _s.sid);
          _panel(
            () => showTvOptions(
              context,
              title: 'Subtitles',
              focusIndex: current < 0 ? 0 : current + 1,
              options: [
                TvOption('Off', _s.sid == 'no' ? Icons.check : Icons.subtitles_off_outlined, () => _s.chooseSubtitles(null)),
                for (var i = 0; i < subs.length; i++)
                  TvOption(
                    trackLabel('subtitles', subs[i], i + 1),
                    subs[i].id == _s.sid ? Icons.check : Icons.subtitles_outlined,
                    () => _s.chooseSubtitles(subs[i]),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _speed(BuildContext context) {
    const speeds = [0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0];
    final current = speeds.indexWhere((x) => (x - _s.speed).abs() < 0.001);
    return showTvOptions(
      context,
      title: 'Speed',
      subtitle: 'Remembered for this collection',
      focusIndex: current < 0 ? 3 : current,
      options: [
        for (final x in speeds)
          TvOption(
            x == 1.0 ? 'Normal (1×)' : _speedText(x),
            (x - _s.speed).abs() < 0.001 ? Icons.check : Icons.speed,
            () => _s.setSpeed(x),
          ),
      ],
    );
  }

  Future<void> _episodes(BuildContext context, VideoCollection c) {
    final model = context.read<VideoLibraryModel>();
    final list = c.videos;
    final current = list.indexWhere((x) => x.id == _s.id);
    return showTvOptions(
      context,
      title: c.name,
      subtitle: '${list.length} videos',
      focusIndex: current < 0 ? 0 : current,
      options: [
        for (final x in list)
          TvOption(
            [?x.episodeLabel, x.title].join(' · '),
            x.id == _s.id ? Icons.play_arrow : ((model.placeOf(x.id)?.watched ?? false) ? Icons.check : Icons.movie_outlined),
            subtitle: x.id == _s.id ? 'Playing now' : ((model.placeOf(x.id)?.watched ?? false) ? 'Watched' : null),
            () => _s.goTo(x.id),
          ),
      ],
    );
  }

  Future<void> _more(BuildContext context, VideoItem? v) {
    final model = context.read<VideoLibraryModel>();
    final nav = context.read<AppNav>();
    final sleep = Provider.of<VideoSleepTimer?>(context, listen: false);
    final watched = v != null && (model.placeOf(v.id)?.watched ?? false);
    final previous = _s.neighbour(_s.id, forward: false);
    return showTvOptions(
      context,
      title: v?.title ?? 'Video',
      options: [
        TvOption('Watch from the beginning', Icons.replay, _s.startOver),
        if (previous != null)
          TvOption('Previous: ${[?previous.episodeLabel, previous.title].join(' · ')}', Icons.skip_previous, () => _s.jump(forward: false)),
        // Shuffling (0.2.6): back to the collection's own order from here.
        if (_s.shuffle != null)
          TvOption('Stop shuffling', Icons.shuffle_on_outlined, subtitle: 'Carry on in the usual order', _s.stopShuffle),
        if (v != null)
          TvOption(
            watched ? 'Mark as not watched' : 'Mark as watched',
            watched ? Icons.remove_done : Icons.done,
            () => model.setWatched([v.id], !watched),
          ),
        if (sleep != null)
          TvOption(
            sleep.active ? 'Turn the sleep timer off' : 'Sleep timer',
            sleep.active ? Icons.bedtime : Icons.bedtime_outlined,
            sleep.active ? sleep.cancel : sleep.start,
          ),
        if (v != null) TvOption('Details', Icons.info_outline, () => openVideoDetails(context, v)),
        if (v != null)
          TvOption('Go to the collection', Icons.video_library_outlined, () {
            Navigator.of(context).pop();
            nav.openVideoCollection(v.collection);
          }),
      ],
    );
  }
}

/// The video's picture at the marker (or a dark box while it's fetched).
class _PreviewPicture extends StatelessWidget {
  const _PreviewPicture({required this.previewer, required this.target, required this.length});
  final SeekPreviewer previewer;
  final Duration target, length;

  @override
  Widget build(BuildContext context) {
    final kept = previewer.keptFor(target, length);
    return ValueListenableBuilder<SeekFrame?>(
      valueListenable: previewer.frame,
      builder: (context, frame, _) {
        final picture = kept ?? frame?.picture;
        // Nothing until the first picture comes, rather than a black box.
        if (picture == null) return const SizedBox.shrink();
        return ColoredBox(color: Colors.black, child: Image.memory(picture, fit: BoxFit.cover, gaplessPlayback: true));
      },
    );
  }
}
