// The sleep timer: pauses playback after a set time, or at the end of the current chapter/song.
//
// It's switched on and off by the moon button beside play/pause. The length comes from
// Settings → Sleep timer (LibraryModel holds the numbers), with separate lengths for books and
// music; a length of 0 means "end of chapter" for books or "end of song" for music.
// It talks to the player only through the small `SleepTarget` interface below, which
// PlayerModel implements, so tests can drive it with a fake player. The ticking, the fade near
// the end and putting the volume back are shared with the video timer (SleepCountdown, refactor
// phase 2); this file says when the time is up and pauses and saves the book place.
import '../models/track.dart';
import 'library_model.dart';
import 'sleep_countdown.dart';

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
class SleepTimer extends SleepCountdown<SleepMode> {
  final SleepTarget player;
  final LibraryModel settings;
  SleepTimer(this.player, this.settings);

  // For SleepMode.minutes: the clock time at which to pause.
  DateTime? _until;
  // For SleepMode.endOfChapter: the chapter that was playing when the timer started.
  int _chapter = -1;
  // For SleepMode.endOfSong: the song that was playing when the timer started.
  String? _trackId;
  // For SleepMode.endOfSong: time left in the song at the previous tick (spots repeat-one).
  Duration? _songLeft;

  /// Starts with the length from Settings for what's playing now.
  @override
  void start() {
    // Books and music have separate lengths. A length of 0 means "stop at the end of the
    // current chapter" (books) or "end of the current song" (music).
    final minutes = player.inBook ? settings.sleepBookMinutes : settings.sleepMusicMinutes;
    if (minutes > 0) {
      _until = now().add(Duration(minutes: minutes));
      run(SleepMode.minutes);
    } else if (player.inBook) {
      _chapter = player.currentChapterIndex;
      run(SleepMode.endOfChapter);
    } else {
      _trackId = player.current?.id;
      _songLeft = null;
      run(SleepMode.endOfSong);
    }
  }

  @override
  void clearStop() => _until = null;

  /// Time left until the timer fires; null once its end has passed.
  @override
  Duration? computeRemaining() {
    switch (mode) {
      case null:
        return null;
      case SleepMode.minutes:
        return _until!.difference(now());
      case SleepMode.endOfSong:
        final t = player.current;
        if (t == null || t.id != _trackId) return null; // the song ended
        // Prefer the length the engine reports; fall back to the tagged length if it's unknown.
        final length = player.duration > Duration.zero ? player.duration : t.duration;
        final left = length - player.position;
        // HomeTunes (0.1.16): with repeat-one the song never changes, it just starts again, so
        // the check above never saw it end. Moving from its last moments back to its start
        // counts as the end too. (A seek back to the start in the last 1.5 s would also count.)
        final before = _songLeft;
        _songLeft = left;
        if (before != null &&
            before <= const Duration(milliseconds: 1500) &&
            player.position < const Duration(seconds: 2) &&
            left > before) {
          return null;
        }
        return left;
      case SleepMode.endOfChapter:
        if (!player.inBook) return null;
        if (player.currentChapterIndex > _chapter) return null; // the chapter ended
        // Chapter ends and bookOffset are both measured from the start of the whole book,
        // so this works even when the book is split across several files.
        return player.chapterEnd(_chapter) - player.bookOffset;
    }
  }

  /// Time's up: pause and save the book place.
  @override
  Future<void> stopPlayback() async {
    await player.pause();
    player.saveBookPlace();
  }

  @override
  bool get targetPlaying => player.playing;
  @override
  double get targetVolume => player.volume;
  @override
  Future<void> setTargetVolume(double v) => player.setVolume(v);
  @override
  int get fadeSeconds => settings.sleepFadeSeconds;
}
