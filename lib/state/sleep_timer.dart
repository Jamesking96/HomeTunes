// The sleep timer: pauses playback after a set time, or at the end of the current chapter/song.
//
// It's switched on and off by the moon button beside play/pause. The length comes from
// Settings → Sleep timer (LibraryModel holds the numbers), with separate lengths for books and
// music; a length of 0 means "end of chapter" for books or "end of song" for music.
// It talks to the player only through the small `SleepTarget` interface below, which
// PlayerModel implements, so tests can drive it with a fake player. A quarter-second ticker
// checks the time left, fades the volume down near the end, then pauses and saves the book place.
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

/// How the timer decides when to stop: after a number of minutes, when the current book
/// chapter ends, or when the current song ends.
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

  // Which kind of timer is running (null = off).
  SleepMode? _mode;
  // For SleepMode.minutes: the clock time at which to pause.
  DateTime? _until;
  // For SleepMode.endOfChapter: the chapter that was playing when the timer started.
  int _chapter = -1;
  // For SleepMode.endOfSong: the song that was playing when the timer started.
  String? _trackId;
  // The volume just before the fade began, so it can be put back afterwards.
  double? _volumeBefore;
  // The quarter-second ticker that runs while the timer is on.
  Timer? _tick;
  // The last time-left value worked out by tick().
  Duration? _remaining;

  bool get active => _mode != null;
  SleepMode? get mode => _mode;

  /// Time left before it pauses (null when off).
  Duration? get remaining => _remaining;

  /// For tests.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// What the moon button does: turn the timer on if it's off, or off if it's on.
  void toggle() => active ? cancel() : start();

  /// Starts with the length from Settings for what's playing now.
  void start() {
    // Books and music have separate lengths. A length of 0 means "stop at the end of the
    // current chapter" (books) or "end of the current song" (music).
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
    // Check four times a second so the fade is smooth; the button itself only redraws when
    // the whole seconds shown change (see tick()).
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
        // Prefer the length the engine reports; fall back to the tagged length if it's unknown.
        final length = player.duration > Duration.zero ? player.duration : t.duration;
        return length - player.position;
      case SleepMode.endOfChapter:
        if (!player.inBook) return null;
        if (player.currentChapterIndex > _chapter) return null; // the chapter ended
        // Chapter ends and bookOffset are both measured from the start of the whole book,
        // so this works even when the book is split across several files.
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
      // Remember the starting volume once, then scale it down in proportion to the time left.
      _volumeBefore ??= player.volume;
      player.setVolume(_volumeBefore! * r.inMilliseconds / (fade * 1000));
    }
    // Only redraw the button when the whole seconds shown actually change, not every tick.
    final shownChanged = _remaining == null || _remaining!.inSeconds != r.inSeconds;
    _remaining = r;
    if (shownChanged) notifyListeners();
  }

  /// Time's up: stop the ticker, pause, save the book place, then switch off
  /// (which also puts the volume back for next time).
  Future<void> _fire() async {
    // Stop ticking first, so a tick during the await below can't fire a second time.
    _tick?.cancel();
    _tick = null;
    await player.pause();
    player.saveBookPlace();
    cancel();
  }

  /// Puts the volume back to where it was before the fade (if a fade happened).
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
