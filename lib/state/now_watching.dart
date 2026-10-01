// The video playing now, for everything outside its page (30 Sep): the bottom player bar /
// mini player show it, and the system media controls (keyboard media keys, the Windows media
// overlay, the phone's notification) play / pause / skip it, while it's the thing in front.
//
// The video's page (video_player_screen.dart) attaches its player here when it opens a video and
// detaches when it closes. "In front" follows whatever was started last: a video that starts
// playing takes over from the music; music that starts playing takes back over. With no video
// page open, everything is the music's as before.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../models/video_item.dart';
import 'player_model.dart';

/// What the rest of the app needs from a video player (media_kit's in the app, a fake in tests).
abstract class VideoTransport {
  bool get playing;
  Stream<bool> get playingStream;
  Duration get position;
  Stream<Duration> get positionStream;
  Duration get duration;
  Stream<Duration> get durationStream;
  double get volume; // 0–100
  Stream<double> get volumeStream;
  double get rate;
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> setVolume(double volume);
}

class NowWatching extends ChangeNotifier {
  NowWatching(this.music) {
    _musicWasPlaying = music.playing;
    music.addListener(_onMusic);
  }

  final PlayerModel music;

  bool _notifyWaiting = false, _disposed = false;

  /// Tells the bar (and the media controls) something changed, but never while the screen is
  /// being built: the video page attaches and says what's showing while it is first built, and
  /// telling the bar then left it stuck (1 Oct, after 0.1.42): it stopped hearing about the
  /// video's play / pause, position and volume until something else redrew it, such as pressing
  /// its volume slider. Then it waits until the end of that frame.
  void _notify() {
    SchedulerPhase? phase;
    try {
      phase = SchedulerBinding.instance.schedulerPhase;
    } catch (_) {
      phase = null; // plain unit tests: no screen
    }
    if (phase != SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_notifyWaiting) return;
    _notifyWaiting = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyWaiting = false;
      if (!_disposed) notifyListeners();
    });
  }

  VideoTransport? _transport;
  final List<StreamSubscription> _subs = [];
  bool _front = false;
  bool _musicWasPlaying = false;

  /// The video on the page, its picture (a file, or null) and how far the page's skip buttons go.
  VideoItem? video;
  String? picture;
  int skipBackSeconds = 10, skipForwardSeconds = 10;

  /// Brings the video's page back into view (the bottom bar's title is tapped).
  VoidCallback? onOpen;

  VideoTransport? get transport => _transport;

  /// A video page is open and the video is what the bar and media keys control.
  bool get inFront => _transport != null && video != null && _front;

  bool get playing => _transport?.playing ?? false;
  Duration get position => _transport?.position ?? Duration.zero;
  Duration get duration => _transport?.duration ?? Duration.zero;
  Stream<Duration> get positionStream => _transport?.positionStream ?? const Stream.empty();

  /// Video pages still open underneath the one in charge (1 Oct: when the top one closed, the bar
  /// used to lose the video still open below it). The last one closed hands back to the one below.
  final List<_Page> _below = [];

  /// The video page opened a player. It comes to the front as soon as it plays.
  void attach(VideoTransport t, {VoidCallback? onOpen}) {
    final current = _transport;
    if (current != null && !identical(current, t)) _below.add(_snapshot());
    _below.removeWhere((pg) => identical(pg.transport, t));
    _listenTo(t);
    this.onOpen = onOpen;
    _front = t.playing;
    _notify();
  }

  void _listenTo(VideoTransport t) {
    _clearSubs();
    _transport = t;
    _seenPlaying = t.playing;
    _subs.addAll([
      t.playingStream.listen((playing) {
        _seenPlaying = playing;
        if (playing) _front = true;
        _notify();
      }),
      t.durationStream.listen((_) => _notify()),
      // 1 Oct: the video player's own volume bar and the bottom bar's move together.
      t.volumeStream.listen((_) => _notify()),
      // 1 Oct: a safety net for the bar not switching from music to video until something else
      // redrew it. While the video moves, check what's really going on rather than trusting one
      // "started" signal to have arrived in the right order.
      t.positionStream.listen((_) => _check()),
    ]);
  }

  /// What the bar last showed for the video's play / pause.
  bool _seenPlaying = false;

  /// Brings the bar in line with the players as they are now; tells the bar only on a change.
  void _check() {
    final t = _transport;
    if (t == null) return;
    var changed = false;
    if (t.playing != _seenPlaying) {
      _seenPlaying = t.playing;
      changed = true;
    }
    // The video is going and the music isn't: the video is in front.
    if (t.playing && !music.playing && !_front) {
      _front = true;
      changed = true;
    }
    if (changed) _notify();
  }

  _Page _snapshot() =>
      _Page(_transport!, video, picture, onOpen, onNext, onPrevious, skipBackSeconds, skipForwardSeconds);

  /// Opens the next / previous video in the collection on the page; null when there isn't one.
  VoidCallback? onNext, onPrevious;

  bool get hasNext => onNext != null;
  bool get hasPrevious => onPrevious != null;

  /// Which video is on the page now (it moves on to the next episode by itself).
  /// [transport] says which page this is; a page underneath only updates its own record.
  void showing(
    VideoItem v, {
    String? picture,
    int? skipBack,
    int? skipForward,
    VoidCallback? onNext,
    VoidCallback? onPrevious,
    VideoTransport? transport,
  }) {
    if (transport != null && _transport != null && !identical(transport, _transport)) {
      final i = _below.indexWhere((pg) => identical(pg.transport, transport));
      if (i >= 0) {
        final old = _below[i];
        _below[i] = _Page(
          transport,
          v,
          picture,
          old.onOpen,
          onNext,
          onPrevious,
          skipBack ?? old.skipBack,
          skipForward ?? old.skipForward,
        );
      }
      return;
    }
    video = v;
    this.picture = picture;
    this.onNext = onNext;
    this.onPrevious = onPrevious;
    if (skipBack != null) skipBackSeconds = skipBack;
    if (skipForward != null) skipForwardSeconds = skipForward;
    _notify();
  }

  /// The page closed: the bar and media keys go back to the music.
  void detach(VideoTransport t) {
    if (!identical(t, _transport)) {
      _below.removeWhere((pg) => identical(pg.transport, t));
      return;
    }
    _clearSubs();
    if (_below.isNotEmpty) {
      // The page underneath is in charge again.
      final pg = _below.removeLast();
      _listenTo(pg.transport);
      video = pg.video;
      picture = pg.picture;
      onOpen = pg.onOpen;
      onNext = pg.onNext;
      onPrevious = pg.onPrevious;
      skipBackSeconds = pg.skipBack;
      skipForwardSeconds = pg.skipForward;
      _front = pg.transport.playing;
      _notify();
      return;
    }
    _transport = null;
    video = null;
    picture = null;
    onOpen = null;
    onNext = null;
    onPrevious = null;
    _front = false;
    _notify();
  }

  void _clearSubs() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  /// Music that starts playing takes the bar and media keys back.
  void _onMusic() {
    final now = music.playing;
    final was = _musicWasPlaying;
    _musicWasPlaying = now;
    if (now && !was && _front) {
      _front = false;
      _notify();
      return;
    }
    // The music stopped (the video paused it) while the video plays: make sure the bar shows it.
    if (!now) _check();
  }

  // ---- controls ----

  Future<void> play() async {
    final t = _transport;
    if (t == null) return;
    if (music.playing) await music.pause(); // one thing at a time
    _front = true;
    _notify();
    await t.play();
  }

  Future<void> pause() async => _transport?.pause();

  Future<void> togglePlay() => playing ? pause() : play();

  Future<void> seek(Duration to) async {
    final t = _transport;
    if (t == null) return;
    final length = t.duration;
    var at = to < Duration.zero ? Duration.zero : to;
    if (length > Duration.zero && at > length) at = length;
    await t.seek(at);
    _notify(); // the system controls show the new place
  }

  /// Back or forward by the page's skip amounts (Settings › Videos).
  Future<void> skip({required bool forward}) =>
      seek(position + Duration(seconds: forward ? skipForwardSeconds : -skipBackSeconds));

  /// The next / previous video in the collection, when there is one.
  void next() => onNext?.call();
  void previous() => onPrevious?.call();

  double get volume => _transport?.volume ?? 100;
  Future<void> setVolume(double v) async {
    await _transport?.setVolume(v.clamp(0.0, 100.0));
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    music.removeListener(_onMusic);
    _clearSubs();
    super.dispose();
  }
}

/// A video page that's open underneath the one in charge, as it last described itself.
class _Page {
  const _Page(
    this.transport,
    this.video,
    this.picture,
    this.onOpen,
    this.onNext,
    this.onPrevious,
    this.skipBack,
    this.skipForward,
  );
  final VideoTransport transport;
  final VideoItem? video;
  final String? picture;
  final VoidCallback? onOpen, onNext, onPrevious;
  final int skipBack, skipForward;
}
