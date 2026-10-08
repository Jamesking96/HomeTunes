// The sleep timer for videos (0.1.63): pauses the video after a while, or at the end of the one
// playing, fading the sound out first, like the music's SleepTimer.
//
// The user asked for the sleep timer in the video player too. The music timer is tied to the
// music player (songs, chapters), so videos have their own, which works on whatever video is in
// charge (NowWatching): the one on the video page, also shown in the bottom bar. Its length is
// Settings › Sleep timer › "Timer length for videos" (LibraryModel.sleepVideoMinutes; "End of
// video" is LibraryModel.sleepAtEnd); the fade and the "Show sleep timer button" switch are
// shared with music. The moon button is VideoSleepTimerButton (widgets/video_sleep_button.dart).
// The ticking, the fade and putting the volume back are shared with the music timer
// (SleepCountdown, refactor phase 2).
//
// "End of video" pauses just before the end (in the last half second), so the next episode's
// "Up next" countdown never starts. If the video changes anyway (the next one was opened), it
// pauses that one. When the video page closes, the timer stops and the volume is put back.
import 'package:flutter/foundation.dart';

import 'library_model.dart';
import 'now_watching.dart';
import 'sleep_countdown.dart';

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
class VideoSleepTimer extends SleepCountdown<VideoSleepMode> {
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

  DateTime? _until;
  String? _videoId;

  /// Starts with the length for videos from Settings (needs a video to be on).
  @override
  void start() {
    if (video.videoId == null) return;
    final minutes = settings.sleepVideoMinutes;
    if (minutes > 0) _until = now().add(Duration(minutes: minutes));
    _videoId = video.videoId;
    run(minutes > 0 ? VideoSleepMode.minutes : VideoSleepMode.endOfVideo);
  }

  @override
  void clearStop() => _until = null;

  /// Not running: nothing to do. The video page closed: stop (and put the volume back).
  @override
  bool beforeTick() {
    if (mode == null) return true;
    if (video.videoId == null) {
      cancel();
      return true;
    }
    return false;
  }

  /// Time left; null once it's time to pause.
  @override
  Duration? computeRemaining() {
    switch (mode) {
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

  /// The video page saves the place when it pauses.
  @override
  Future<void> stopPlayback() => video.pause();

  @override
  bool get targetPlaying => video.playing;
  @override
  double get targetVolume => video.volume;
  @override
  Future<void> setTargetVolume(double v) => video.setVolume(v);
  @override
  int get fadeSeconds => settings.sleepFadeSeconds;
  @override
  bool get canRestoreVolume => video.videoId != null;

  void _onVideoChanged() {
    if (active && video.videoId == null) cancel();
  }

  @override
  void dispose() {
    _changes?.removeListener(_onVideoChanged);
    super.dispose();
  }
}
