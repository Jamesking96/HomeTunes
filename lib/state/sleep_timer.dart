import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'library_model.dart';

/// What the sleep timer needs from the player (the player implements it;
/// tests use a fake).
abstract class SleepTarget {
  bool get inBook;
  bool get playing;
  Track? get current;
  Duration get duration;
  Duration get position;
  Duration get bookOffset;
  int get currentChapterIndex;
  Duration chapterEnd(int i);
  double get volume;
  Future<void> setVolume(double v);
  Future<void> pause();
  void saveBookPlace();
}

enum SleepMode { minutes, endOfChapter, endOfSong }

/// Pauses playback after a while. One tap on the button beside play/pause
/// turns it on with the length set in Settings > Sleep timer (separate lengths
/// for books and music); another tap turns it off. The volume fades out
/// before it pauses.
///
/// Kept apart from the player so the once-a-second countdown only redraws
/// the timer button.
class SleepTimer extends ChangeNotifier {
  final SleepTarget player;
  final LibraryModel settings;
  SleepTimer(this.player, this.settings);

  SleepMode? _mode;
  DateTime? _until;
  int _chapter = -1;
  String? _trackId;
  double? _volumeBefore;
  Timer? _tick;
  Duration? _remaining;

  bool get active => _mode != null;
  SleepMode? get mode => _mode;

  /// Time left before it pauses (null when off).
  Duration? get remaining => _remaining;

  /// For tests.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  void toggle() => active ? cancel() : start();

  /// Starts with the length from Settings for what's playing now.
  void start() {
    final minutes = player.inBook ? settings.sleepBookMinutes : settings.sleepMusicMinutes;
    if (minutes > 0) {
      _mode = SleepMode.minutes;
      _until = now().add(Duration(minutes: minutes));
    } else if (player.inBook) {
      _mode = SleepMode.endOfChapter;
      _chapter = player.currentChapterIndex;
    } else {
      _mode = SleepMode.endOfSong;
      _trackId = player.current?.id;
    }
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

  /// Time left until the timer fires; null once its end has passed.
  Duration? _computeRemaining() {
    switch (_mode) {
      case null:
        return null;
      case SleepMode.minutes:
        return _until!.difference(now());
      case SleepMode.endOfSong:
        final t = player.current;
        if (t == null || t.id != _trackId) return null; // the song ended
        final length = player.duration > Duration.zero ? player.duration : t.duration;
        return length - player.position;
      case SleepMode.endOfChapter:
        if (!player.inBook) return null;
        if (player.currentChapterIndex > _chapter) return null; // the chapter ended
        return player.chapterEnd(_chapter) - player.bookOffset;
    }
  }

  /// Checks the time left (runs every quarter second while on).
  @visibleForTesting
  void tick() {
    final r = _computeRemaining();
    if (r == null || r <= Duration.zero) {
      _fire();
      return;
    }
    // Fade the volume down over the last few seconds.
    final fade = settings.sleepFadeSeconds;
    if (fade > 0 && player.playing && r.inMilliseconds <= fade * 1000) {
      _volumeBefore ??= player.volume;
      player.setVolume(_volumeBefore! * r.inMilliseconds / (fade * 1000));
    }
    final shownChanged = _remaining == null || _remaining!.inSeconds != r.inSeconds;
    _remaining = r;
    if (shownChanged) notifyListeners();
  }

  Future<void> _fire() async {
    _tick?.cancel();
    _tick = null;
    await player.pause();
    player.saveBookPlace();
    cancel();
  }

  void _restoreVolume() {
    final v = _volumeBefore;
    if (v != null) player.setVolume(v);
    _volumeBefore = null;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}
