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

  /// The video page opened a player. It comes to the front as soon as it plays.
  void attach(VideoTransport t, {VoidCallback? onOpen}) {
    _clearSubs();
    _transport = t;
    this.onOpen = onOpen;
    _front = t.playing;
    _subs.addAll([
      t.playingStream.listen((playing) {
        if (playing) _front = true;
        notifyListeners();
      }),
      t.durationStream.listen((_) => notifyListeners()),
    ]);
    notifyListeners();
  }

  /// Opens the next / previous video in the collection on the page; null when there isn't one.
  VoidCallback? onNext, onPrevious;

  bool get hasNext => onNext != null;
  bool get hasPrevious => onPrevious != null;

  /// Which video is on the page now (it moves on to the next episode by itself).
  void showing(VideoItem v,
      {String? picture, int? skipBack, int? skipForward, VoidCallback? onNext, VoidCallback? onPrevious}) {
    video = v;
    this.picture = picture;
    this.onNext = onNext;
    this.onPrevious = onPrevious;
    if (skipBack != null) skipBackSeconds = skipBack;
    if (skipForward != null) skipForwardSeconds = skipForward;
    notifyListeners();
  }

  /// The page closed: the bar and media keys go back to the music.
  void detach(VideoTransport t) {
    if (!identical(t, _transport)) return;
    _clearSubs();
    _transport = null;
    video = null;
    picture = null;
    onOpen = null;
    onNext = null;
    onPrevious = null;
    _front = false;
    notifyListeners();
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
    if (now && !_musicWasPlaying && _front) {
      _front = false;
      notifyListeners();
    }
    _musicWasPlaying = now;
  }

  // ---- controls ----

  Future<void> play() async {
    final t = _transport;
    if (t == null) return;
    if (music.playing) await music.pause(); // one thing at a time
    _front = true;
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
    notifyListeners(); // the system controls show the new place
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
    notifyListeners();
  }

  @override
  void dispose() {
    music.removeListener(_onMusic);
    _clearSubs();
    super.dispose();
  }
}
