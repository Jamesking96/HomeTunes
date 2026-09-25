import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' show Media, NativePlayer, Player, Playlist;

import '../models/book.dart';
import '../models/track.dart';
import 'library_model.dart';
import 'listening_model.dart';
import 'play_queue.dart';
import 'sleep_timer.dart';

/// The music queue, kept aside while an audiobook plays.
class _MusicQueue {
  final List<Track> tracks;
  final int index;
  final Duration position;
  final bool shuffle;
  final RepeatSetting repeat;
  final String? label;
  const _MusicQueue(this.tracks, this.index, this.position, this.shuffle, this.repeat, this.label);
}

/// Connects the [PlayQueue] to the actual audio engine (media_kit / libmpv).
///
/// Position is exposed as a stream so the seek bar can update several times a
/// second without rebuilding the whole app.
class PlayerModel extends ChangeNotifier implements SleepTarget {
  final LibraryModel library;

  /// Remembers the place in audiobooks (null in tests that don't need it).
  final ListeningModel? listening;
  final Player _player = Player();
  final PlayQueue queue = PlayQueue();
  final List<StreamSubscription> _subs = [];

  @override
  bool playing = false;
  bool buffering = false;
  @override
  Duration duration = Duration.zero;
  @override
  double volume = 100; // 0–100
  String? lastError;

  /// How many opens are in flight (see the `completed` listener).
  int _opening = 0;

  /// Gapless playback: the audio engine holds the song playing now and,
  /// loaded ahead, the one that plays next ([_engineIds], by track id). When
  /// it moves on by itself there's no gap; HomeTunes then catches its own
  /// queue up and loads the following song. HomeTunes' queue stays in charge
  /// (shuffle, repeat, Play next…): the engine never holds more than that.
  List<String> _engineIds = [];

  /// Our own changes to the engine's list are in progress (ignore its events).
  int _engineEdits = 0;

  /// Engine settings last applied (so they're only sent when they change).
  String? _appliedReplayGain;
  bool? _appliedGapless;

  /// The audiobook playing, or null when playing music.
  Book? get book => _book;
  Book? _book;

  /// The playing book's chapters (cached; empty for music).
  List<BookChapter> get chapters => _chapters;
  List<BookChapter> _chapters = const [];

  void _setBook(Book? b) {
    _book = b;
    _chapters = b?.chapters ?? const [];
  }

  /// Playback speed (1.0 = normal).
  double speed = 1.0;

  /// The music queue waiting while a book plays.
  _MusicQueue? _music;
  Timer? _saveTimer;

  PlayerModel(this.library, {this.listening}) {
    library.addListener(_onLibraryChanged);
    _applyEngineSettings();
    // While a book plays, save the place every 10 seconds.
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (book != null && playing) saveBookPlace();
    });
    _subs.addAll([
      _player.stream.playing.listen((v) {
        final paused = playing && !v;
        playing = v;
        if (paused) saveBookPlace();
        notifyListeners();
      }),
      _player.stream.buffering.listen((v) {
        buffering = v;
        notifyListeners();
      }),
      _player.stream.duration.listen((v) {
        duration = v;
        _learnDuration(v);
        notifyListeners();
      }),
      _player.stream.volume.listen((v) {
        volume = v;
        notifyListeners();
      }),
      _player.stream.completed.listen((done) {
        // Only fires at the end of the engine's list: the queue ended, or
        // nothing was loaded ahead. Opening a new file can briefly report the
        // old one as "completed"; ignore that so we don't skip an extra song.
        if (done && _opening == 0) _advance(auto: true);
      }),
      _player.stream.playlist.listen((pl) {
        // The engine moved on to the song loaded ahead, by itself.
        if (_opening == 0 && _engineEdits == 0 && pl.index == 1 && _engineIds.length > 1) {
          _onEngineAdvanced();
        }
      }),
      _player.stream.error.listen((e) {
        lastError = e;
        notifyListeners();
      }),
    ]);
  }

  /// Keeps the queue (and the now-playing display / system media controls)
  /// showing songs' latest details after they're edited or rescanned.
  void _onLibraryChanged() {
    _applyEngineSettings();
    var changed = queue.refresh(library.byId);
    // Keep the playing book's details (and parts) current after a rescan.
    final b = book;
    final t = queue.current;
    if (b != null && t != null) {
      final fresh = library.bookOfTrack(t.id);
      if (fresh != null && !identical(fresh, b)) {
        _setBook(fresh);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// When a song's file didn't say how long it is (or said something wrong),
  /// remember the real length the player found, so lists and totals show it.
  void _learnDuration(Duration d) {
    final t = queue.current;
    if (t == null || d <= Duration.zero) return;
    if (!t.hasDuration || (d - t.duration).abs() > const Duration(seconds: 2)) {
      library.learnDuration(t.id, d);
    }
  }

  @override
  Track? get current => queue.current;
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Duration get position => _player.state.position;
  bool get shuffle => queue.shuffle;
  RepeatSetting get repeat => queue.repeat;

  /// Starts playing [tracks] from [start].
  Future<void> playTracks(List<Track> tracks, {int start = 0, bool? shuffle, String? label}) async {
    if (tracks.isEmpty) return;
    _leaveBook();
    queue.setTracks(tracks, start: start, shuffle: shuffle, label: label);
    await _openCurrent();
  }

  /// Plays everything shuffled.
  Future<void> shufflePlay(List<Track> tracks, {String? label}) {
    if (tracks.isEmpty) return Future.value();
    final start = Random().nextInt(tracks.length);
    return playTracks(tracks, start: start, shuffle: true, label: label);
  }

  Future<void> _openCurrent({int? skipsLeft, Duration? startAt}) async {
    // Skip at most once round the whole queue (all songs unavailable).
    skipsLeft ??= queue.tracks.length - 1;
    final t = queue.current;
    if (t == null) {
      await _player.stop();
      _engineIds = [];
      notifyListeners();
      return;
    }
    final uri = library.playableUri(t);
    if (uri == null) {
      // A song whose file isn't on this device (any more), or a server song
      // while the server is switched off: skip it. Its details are kept.
      lastError = t.isLocal
          ? '"${t.title}" isn\'t on this device – skipped'
          : 'Can\'t play "${t.title}" right now';
      if (skipsLeft > 0 && queue.next() != null) {
        return _openCurrent(skipsLeft: skipsLeft - 1);
      }
      notifyListeners();
      return;
    }
    lastError = null;
    duration = t.duration;
    notifyListeners();
    _opening++;
    try {
      final start = startAt != null && startAt > Duration.zero ? startAt : null;
      // Load the song after this one too, so it follows without a gap.
      final ahead = _songToLoadAhead();
      _engineIds = [t.id, if (ahead != null) ahead.$1.id];
      await _player.open(
        Playlist([Media(uri, start: start), if (ahead != null) Media(ahead.$2)], index: 0),
        play: true,
      );
      // Make sure the new song actually starts, even if playback was paused
      // (e.g. pressing Next while paused, or after the previous song ended).
      if (!_player.state.playing) await _player.play();
    } finally {
      _opening--;
    }
  }

  /// The song to load ahead in the engine (and its file / stream), if any.
  (Track, String)? _songToLoadAhead() {
    if (!library.gaplessPlayback) return null;
    final next = queue.peekNextAuto();
    if (next == null) return null;
    final uri = library.playableUri(next);
    return uri == null ? null : (next, uri);
  }

  /// The engine went on to the song loaded ahead: catch the queue up, drop
  /// the finished song from the engine and load the one after.
  Future<void> _onEngineAdvanced() async {
    // Set before anything else, so a repeated "moved on" event from the
    // engine can't advance the queue twice.
    _engineEdits++;
    Track? next;
    try {
      final expected = _engineIds[1];
      next = queue.next(auto: true);
      if (next == null || next.id != expected) {
        next = null; // out of step (shouldn't happen): reopened below
      } else {
        duration = next.duration;
        try {
          await _player.remove(0);
          _engineIds.removeAt(0);
        } catch (_) {
          // The engine's list changed underneath us; the sync below repairs it.
        }
        if (book != null) await listening?.record(book!, next.id, Duration.zero);
      }
    } finally {
      _engineEdits--;
    }
    if (next == null) {
      await _openCurrent();
      return;
    }
    notifyListeners();
    await _syncLoadedAhead();
  }

  /// After the queue changes (Play next, reorder, shuffle, repeat…), make
  /// sure the song loaded ahead in the engine is still the right one.
  Future<void> _syncLoadedAhead() async {
    if (_opening > 0 || _engineIds.isEmpty || queue.current == null) return;
    if (_engineIds.first != queue.current!.id) return; // a new song is being opened
    final want = _songToLoadAhead();
    final have = _engineIds.length > 1 ? _engineIds[1] : null;
    if (want?.$1.id == have) return;
    _engineEdits++;
    try {
      while (_engineIds.length > 1) {
        await _player.remove(_engineIds.length - 1);
        _engineIds.removeLast();
      }
      if (want != null) {
        await _player.add(Media(want.$2));
        _engineIds.add(want.$1.id);
      }
    } catch (e) {
      debugPrint('HomeTunes: couldn\'t update the song loaded ahead: $e');
    } finally {
      _engineEdits--;
    }
  }

  /// Sends the gapless and ReplayGain settings to the audio engine.
  Future<void> _applyEngineSettings() async {
    final engine = _player.platform;
    if (engine is! NativePlayer) return;
    try {
      if (_appliedGapless != library.gaplessPlayback) {
        _appliedGapless = library.gaplessPlayback;
        // "yes": no gap even between files of different formats; the next
        // file is opened early so streams from a server are ready in time.
        await engine.setProperty('gapless-audio', library.gaplessPlayback ? 'yes' : 'no');
        await engine.setProperty('prefetch-playlist', library.gaplessPlayback ? 'yes' : 'no');
        await _syncLoadedAhead();
      }
      final rg = library.replayGain.name; // off / track / album
      if (_appliedReplayGain != rg) {
        _appliedReplayGain = rg;
        await engine.setProperty('replaygain', rg == 'off' ? 'no' : rg);
      }
    } catch (e) {
      debugPrint('HomeTunes: couldn\'t apply playback settings: $e');
    }
  }

  Future<void> _advance({required bool auto}) async {
    final prev = queue.current;
    final next = queue.next(auto: auto);
    if (next == null) {
      if (book != null && auto && prev != null) {
        // The end of the book.
        await listening?.record(book!, prev.id, prev.duration, finished: true);
        await _player.pause();
        notifyListeners();
        return;
      }
      // End of queue: stop at the start of the last song, like most players.
      await _player.pause();
      await _player.seek(Duration.zero);
      notifyListeners();
      return;
    }
    if (book != null) {
      // Moving on to the next file of the book: remember that.
      await listening?.record(book!, next.id, Duration.zero);
    }
    if (auto && identical(next, prev) && queue.repeat == RepeatSetting.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    await _openCurrent();
  }

  Future<void> togglePlay() async {
    if (queue.current == null) return;
    await _player.playOrPause();
  }

  /// Resume (used by lock-screen / headset / media-key controls).
  Future<void> play() async {
    if (queue.current == null) return;
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  Future<void> next() => _advance(auto: false);

  /// Restarts the song if we're more than 3 seconds in, otherwise goes back.
  Future<void> previous() async {
    if (position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    queue.previous();
    await _openCurrent();
  }

  Future<void> seek(Duration d) async {
    await _player.seek(d);
    notifyListeners(); // lets the system media controls pick up the new position
  }
  @override
  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0.0, 100.0));

  void toggleShuffle() {
    if (book != null) return; // books always play in order
    queue.setShuffle(!queue.shuffle);
    notifyListeners();
    _syncLoadedAhead();
  }

  void cycleRepeat() {
    if (book != null) return;
    queue.cycleRepeat();
    notifyListeners();
    _syncLoadedAhead();
  }

  Future<void> jumpTo(int queueIndex) async {
    queue.jumpTo(queueIndex);
    await _openCurrent();
  }

  Future<void> playNext(Track t) async {
    if (book != null) {
      // Goes into the waiting music queue; the book keeps playing.
      _addToWaitingMusic(t, next: true);
      return;
    }
    final wasEmpty = queue.isEmpty;
    queue.playNext(t);
    if (wasEmpty) await _openCurrent();
    notifyListeners();
    await _syncLoadedAhead();
  }

  Future<void> addToQueue(Track t) async {
    if (book != null) {
      _addToWaitingMusic(t, next: false);
      return;
    }
    final wasEmpty = queue.isEmpty;
    queue.add(t);
    if (wasEmpty) await _openCurrent();
    notifyListeners();
    await _syncLoadedAhead();
  }

  void removeUpcoming(int i) {
    queue.removeUpcoming(i);
    notifyListeners();
    _syncLoadedAhead();
  }

  void moveUpcoming(int from, int to) {
    queue.moveUpcoming(from, to);
    notifyListeners();
    _syncLoadedAhead();
  }

  // ---- audiobooks ----

  /// True while an audiobook (rather than music) is playing.
  @override
  bool get inBook => book != null;

  /// A music queue is waiting to be picked up again (see [resumeMusic]).
  bool get hasWaitingMusic => _music != null && _music!.tracks.isNotEmpty;

  /// How far to go back when resuming, so the sentence isn't cut off:
  /// more the longer it's been.
  static Duration resumeRewind(Duration sinceLastListen) {
    if (sinceLastListen < const Duration(minutes: 1)) return const Duration(seconds: 2);
    if (sinceLastListen < const Duration(hours: 1)) return const Duration(seconds: 10);
    return const Duration(seconds: 30);
  }

  /// Plays [b] from where the listener left off, or from [partIndex]/[at] if
  /// given (e.g. a chapter), or from the start with [fromStart].
  Future<void> playBook(Book b, {bool fromStart = false, int? partIndex, Duration? at}) async {
    if (b.parts.isEmpty) return;
    if (book != null) {
      saveBookPlace();
    } else if (!queue.isEmpty) {
      _music = _MusicQueue(
        queue.tracks,
        queue.position,
        _player.state.position,
        queue.shuffle,
        queue.repeat,
        queue.contextLabel,
      );
    }

    var index = 0;
    var position = Duration.zero;
    if (partIndex != null) {
      index = partIndex.clamp(0, b.parts.length - 1);
      position = at ?? Duration.zero;
    } else if (!fromStart) {
      final saved = listening?.progressFor(b);
      if (saved != null && !saved.finished) {
        final i = b.indexOfPart(saved.partId);
        if (i >= 0) {
          index = i;
          final since = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - saved.updatedMs);
          position = library.rewindOnResume ? saved.position - resumeRewind(since) : saved.position;
          if (position.isNegative) position = Duration.zero;
        }
      }
    }

    _setBook(b);
    queue.setTracks(b.parts, start: index, shuffle: false, label: 'Book · ${b.title}');
    queue.repeat = RepeatSetting.off;
    await listening?.record(b, b.parts[index].id, position);
    await _applySpeed(listening?.speedFor(b) ?? library.defaultBookSpeed);
    await _openCurrent(startAt: position);
  }

  /// Saves the place in the playing book (every 10 s, on pause, when the app
  /// goes to the background, and before switching away).
  @override
  void saveBookPlace() {
    final b = book;
    final t = queue.current;
    if (b == null || t == null || _opening > 0) return;
    listening?.record(b, t.id, _player.state.position);
  }

  /// Stops being in book mode (music was chosen). The waiting music queue is
  /// dropped because new music replaces it, but its shuffle/repeat are kept.
  void _leaveBook() {
    if (book == null) return;
    saveBookPlace();
    _setBook(null);
    _applySpeed(1.0);
    final m = _music;
    if (m != null) {
      queue.shuffle = m.shuffle;
      queue.repeat = m.repeat;
    }
    _music = null;
  }

  void _addToWaitingMusic(Track t, {required bool next}) {
    final m = _music;
    if (m == null || m.tracks.isEmpty) {
      _music = _MusicQueue([t], 0, Duration.zero, queue.shuffle, RepeatSetting.off, null);
    } else {
      final list = List.of(m.tracks);
      list.insert(next ? m.index + 1 : list.length, t);
      _music = _MusicQueue(list, m.index, m.position, m.shuffle, m.repeat, m.label);
    }
    notifyListeners();
  }

  /// Leaves the book (its place is saved) and goes back to the music queue.
  Future<void> resumeMusic() async {
    final m = _music;
    if (book == null || m == null) return;
    saveBookPlace();
    _setBook(null);
    await _applySpeed(1.0);
    _music = null;
    queue.setTracks(m.tracks, start: m.index, shuffle: false, label: m.label);
    queue.shuffle = m.shuffle;
    queue.repeat = m.repeat;
    await _openCurrent(startAt: m.position);
  }

  // ---- skipping, chapters and speed ----

  /// Time from the start of the playing book to where we are.
  @override
  Duration get bookOffset {
    final b = book;
    if (b == null) return position;
    return b.offsetOf(queue.position, position);
  }

  /// The chapter we're in (-1 for music).
  @override
  int get currentChapterIndex => book == null ? -1 : chapterIndexAt(_chapters, bookOffset);

  /// Index of the chapter that [offset] (from the start of the book) is in.
  static int chapterIndexAt(List<BookChapter> chapters, Duration offset) {
    if (chapters.isEmpty) return -1;
    var found = 0;
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].offset <= offset) {
        found = i;
      } else {
        break;
      }
    }
    return found;
  }

  BookChapter? get currentChapter {
    final i = currentChapterIndex;
    return i < 0 ? null : _chapters[i];
  }

  /// Where chapter [i] ends, from the start of the book.
  @override
  Duration chapterEnd(int i) {
    final b = book;
    if (b == null || i < 0) return Duration.zero;
    return i + 1 < _chapters.length ? _chapters[i + 1].offset : b.duration;
  }

  /// Goes to [at] in file [part] of the queue (same file: just seeks).
  Future<void> _goTo(int part, Duration at) async {
    if (at.isNegative) at = Duration.zero;
    if (part == queue.position) {
      await _player.seek(at);
      notifyListeners();
    } else {
      queue.jumpTo(part);
      await _openCurrent(startAt: at);
    }
    final b = book;
    final t = queue.current;
    if (b != null && t != null) await listening?.record(b, t.id, at);
  }

  /// Jumps back or forward by [delta]. In a book this carries on into the
  /// previous / next file.
  Future<void> skipBy(Duration delta) async {
    final t = current;
    if (t == null) return;
    final b = book;
    final length = duration > Duration.zero ? duration : t.duration;
    final lengths = b == null
        ? [length]
        : [for (var i = 0; i < b.parts.length; i++) i == queue.position ? length : b.parts[i].duration];
    final target = skipTarget(lengths, b == null ? 0 : queue.position, position, delta);
    if (target == null) return next(); // past the end of a song: next song
    await _goTo(b == null ? queue.position : target.$1, target.$2);
  }

  /// Where a skip of [delta] from [position] in file [part] lands, given the
  /// lengths of the files (one file for a song). Crosses into the previous /
  /// next file of a book. Returns null when a song would skip past its end.
  static (int, Duration)? skipTarget(List<Duration> lengths, int part, Duration position, Duration delta) {
    var target = position + delta;
    while (target.isNegative && part > 0) {
      part--;
      target += lengths[part];
    }
    if (target.isNegative) target = Duration.zero;
    while (part < lengths.length - 1 && lengths[part] > Duration.zero && target >= lengths[part]) {
      target -= lengths[part];
      part++;
    }
    final length = lengths[part];
    if (length > Duration.zero && target >= length) {
      if (lengths.length == 1) return null;
      target = length - const Duration(seconds: 1); // the very end of the book
    }
    return (part, target);
  }

  Future<void> skipBack() => skipBy(-Duration(seconds: library.skipBackSeconds));
  Future<void> skipForward() => skipBy(Duration(seconds: library.skipForwardSeconds));

  /// Goes to [at] in file [part] of the playing book (e.g. a bookmark).
  Future<void> goToPart(int part, Duration at) => _goTo(part, at);

  /// Jumps to the start of chapter [i] of the playing book.
  Future<void> goToChapter(int i) async {
    if (i < 0 || i >= _chapters.length) return;
    await _goTo(_chapters[i].part, _chapters[i].start);
  }

  Future<void> nextChapter() async {
    final i = currentChapterIndex;
    if (i < 0 || i + 1 >= _chapters.length) return;
    final c = _chapters[i + 1];
    await _goTo(c.part, c.start);
  }

  /// Back to the start of this chapter, or to the previous one if we're
  /// within 3 seconds of the start.
  Future<void> previousChapter() async {
    final i = currentChapterIndex;
    if (i < 0) return;
    final c = _chapters[i];
    final into = bookOffset - c.offset;
    final target = (into > const Duration(seconds: 3) || i == 0) ? c : _chapters[i - 1];
    await _goTo(target.part, target.start);
  }

  static const speeds = [0.75, 0.9, 1.0, 1.1, 1.2, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5];

  Future<void> _applySpeed(double s) async {
    speed = s;
    await _player.setRate(s);
  }

  /// Changes the speed; for a book it's remembered for that book.
  Future<void> setSpeed(double s) async {
    await _applySpeed(s);
    final b = book;
    if (b != null) await listening?.setSpeed(b, s);
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    saveBookPlace();
    library.removeListener(_onLibraryChanged);
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
