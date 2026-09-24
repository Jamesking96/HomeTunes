import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' show Media, Player;

import '../models/book.dart';
import '../models/track.dart';
import 'library_model.dart';
import 'listening_model.dart';
import 'play_queue.dart';

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
class PlayerModel extends ChangeNotifier {
  final LibraryModel library;

  /// Remembers the place in audiobooks (null in tests that don't need it).
  final ListeningModel? listening;
  final Player _player = Player();
  final PlayQueue queue = PlayQueue();
  final List<StreamSubscription> _subs = [];

  bool playing = false;
  bool buffering = false;
  Duration duration = Duration.zero;
  double volume = 100; // 0–100
  String? lastError;

  /// How many opens are in flight (see the `completed` listener).
  int _opening = 0;

  /// The audiobook playing, or null when playing music.
  Book? book;

  /// The music queue waiting while a book plays.
  _MusicQueue? _music;
  Timer? _saveTimer;

  PlayerModel(this.library, {this.listening}) {
    library.addListener(_onLibraryChanged);
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
        // Opening a new file can briefly report the old one as "completed";
        // ignore that so we don't skip an extra song.
        if (done && _opening == 0) _advance(auto: true);
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
    var changed = queue.refresh(library.byId);
    // Keep the playing book's details (and parts) current after a rescan.
    final b = book;
    final t = queue.current;
    if (b != null && t != null) {
      final fresh = library.bookOfTrack(t.id);
      if (fresh != null && !identical(fresh, b)) {
        book = fresh;
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

  Track? get current => queue.current;
  Stream<Duration> get positionStream => _player.stream.position;
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
      await _player.open(Media(uri, start: start), play: true);
      // Make sure the new song actually starts, even if playback was paused
      // (e.g. pressing Next while paused, or after the previous song ended).
      if (!_player.state.playing) await _player.play();
    } finally {
      _opening--;
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
  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0.0, 100.0));

  void toggleShuffle() {
    if (book != null) return; // books always play in order
    queue.setShuffle(!queue.shuffle);
    notifyListeners();
  }

  void cycleRepeat() {
    if (book != null) return;
    queue.cycleRepeat();
    notifyListeners();
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
  }

  void removeUpcoming(int i) {
    queue.removeUpcoming(i);
    notifyListeners();
  }

  void moveUpcoming(int from, int to) {
    queue.moveUpcoming(from, to);
    notifyListeners();
  }

  // ---- audiobooks ----

  /// True while an audiobook (rather than music) is playing.
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
          position = saved.position - resumeRewind(since);
          if (position.isNegative) position = Duration.zero;
        }
      }
    }

    book = b;
    queue.setTracks(b.parts, start: index, shuffle: false, label: 'Book · ${b.title}');
    queue.repeat = RepeatSetting.off;
    await listening?.record(b, b.parts[index].id, position);
    await _openCurrent(startAt: position);
  }

  /// Saves the place in the playing book (every 10 s, on pause, when the app
  /// goes to the background, and before switching away).
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
    book = null;
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
    book = null;
    _music = null;
    queue.setTracks(m.tracks, start: m.index, shuffle: false, label: m.label);
    queue.shuffle = m.shuffle;
    queue.repeat = m.repeat;
    await _openCurrent(startAt: m.position);
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
