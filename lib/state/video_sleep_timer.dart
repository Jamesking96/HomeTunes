// The sleep timer for videos (0.1.63): pauses the video after a while, or at the end of the one
// playing, fading the sound out first, like the music's SleepTimer.
//
// The user asked for the sleep timer in the video player too. The music timer is tied to the
// music player (songs, chapters), so videos have their own, which works on whatever video is in
// charge (NowWatching): the one on the video page, also shown in the bottom bar. Its length is
// Settings › Sleep timer › "Timer length for videos" (LibraryModel.sleepVideoMinutes; "End of
// video" is LibraryModel.sleepAtEnd); the fade and the "Show sleep timer button" switch are
// shared with music. The moon button is VideoSleepTimerButton (widgets/video_sleep_button.dart).
//
// "End of video" pauses just before the end (in the last half second), so the next episode's
// "Up next" countdown never starts. If the video changes anyway (the next one was opened), it
// pauses that one. When the video page closes, the timer stops and the volume is put back.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'library_model.dart';
import 'now_watching.dart';

/// What the timer needs from the video (NowWatching in the app; tests use a fake).
abstract class VideoSleepTarget {
  /// Which video is on (null when no video page is open).
  String? get videoId;
  bool get playing;
  Duration get position;
  Duration get duration;
  double get volume;
  Future<void> setVolume(double v);
  Future<void> pause();
}

/// [NowWatching] as a [VideoSleepTarget].
class WatchingSleepTarget implements VideoSleepTarget {
  WatchingSleepTarget(this.watching);
  final NowWatching watching;

  @override
  String? get videoId => watching.transport == null ? null : watching.video?.id;
  @override
  bool get playing => watching.playing;
  @override
  Duration get position => watching.position;
  @override
  Duration get duration => watching.duration;
  @override
  double get volume => watching.volume;
  @override
  Future<void> setVolume(double v) => watching.setVolume(v);
  @override
  Future<void> pause() => watching.pause();
}

/// How the video timer decides when to stop.
enum VideoSleepMode { minutes, endOfVideo }

/// Pauses the video after Settings › Sleep timer's length for videos.
class VideoSleepTimer extends ChangeNotifier {
  VideoSleepTimer(this.video, this.settings, {Listenable? changes}) : _changes = changes {
    _changes?.addListener(_onVideoChanged);
  }

  final VideoSleepTarget video;
  final LibraryModel settings;
  // Tells the timer the video changed (NowWatching); it stops when the video page closes.
  final Listenable? _changes;

  /// End of video: pause when this little is left, so the video never reaches its end (which
  /// would start the next episode's countdown).
  static const endMargin = Duration(milliseconds: 500);

  VideoSleepMode? _mode;
  DateTime? _until;
  String? _videoId;
  double? _volumeBefore;
  Timer? _tick;
  Duration? _remaining;

  bool get active => _mode != null;
  VideoSleepMode? get mode => _mode;

  /// Time left before it pauses (null when off).
  Duration? get remaining => _remaining;

  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// The moon button: on if it's off, off if it's on.
  void toggle() => active ? cancel() : start();

  /// Starts with the length for videos from Settings (needs a video to be on).
  void start() {
    if (video.videoId == null) return;
    final minutes = settings.sleepVideoMinutes;
    if (minutes > 0) {
      _mode = VideoSleepMode.minutes;
      _until = now().add(Duration(minutes: minutes));
    } else {
      _mode = VideoSleepMode.endOfVideo;
    }
    _videoId = video.videoId;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
    tick();
    notifyListeners();
  }

  /// Turns it off (and puts the volume back if it was fading).
  void cancel() {
    _tick?.cancel();
    _tick = null;
    _restoreVolume();
    _mode = null;
    _until = null;
    _remaining = null;
    notifyListeners();
  }

  /// Time left; null once it's time to pause.
  Duration? _computeRemaining() {
    switch (_mode) {
      case null:
        return null;
      case VideoSleepMode.minutes:
        return _until!.difference(now());
      case VideoSleepMode.endOfVideo:
        if (video.videoId != _videoId) return null; // it moved on to another video
        final length = video.duration;
        if (length <= Duration.zero) return const Duration(days: 1); // not known yet: wait
        final left = length - video.position;
        return left <= endMargin ? null : left;
    }
  }

  /// Checks the time left (four times a second while on).
  @visibleForTesting
  void tick() {
    if (_mode == null) return;
    if (video.videoId == null) {
      cancel(); // the video page closed
      return;
    }
    final r = _computeRemaining();
    if (r == null || r <= Duration.zero) {
      _fire();
      return;
    }
    final fade = settings.sleepFadeSeconds;
    if (fade > 0 && video.playing && r.inMilliseconds <= fade * 1000) {
      _volumeBefore ??= video.volume;
      video.setVolume(_volumeBefore! * r.inMilliseconds / (fade * 1000));
    }
    final shownChanged = _remaining == null || _remaining!.inSeconds != r.inSeconds;
    _remaining = r;
    if (shownChanged) notifyListeners();
  }

  Future<void> _fire() async {
    _tick?.cancel();
    _tick = null;
    await video.pause(); // the video page saves the place when it pauses
    cancel();
  }

  void _restoreVolume() {
    final v = _volumeBefore;
    _volumeBefore = null;
    if (v != null && video.videoId != null) video.setVolume(v);
  }

  void _onVideoChanged() {
    if (active && video.videoId == null) cancel();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _changes?.removeListener(_onVideoChanged);
    super.dispose();
  }
}
