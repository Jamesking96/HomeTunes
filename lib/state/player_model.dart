import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' show Media, Player;

import '../models/track.dart';
import 'library_model.dart';
import 'play_queue.dart';

/// Connects the [PlayQueue] to the actual audio engine (media_kit / libmpv).
///
/// Position is exposed as a stream so the seek bar can update several times a
/// second without rebuilding the whole app.
class PlayerModel extends ChangeNotifier {
  final LibraryModel library;
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

  PlayerModel(this.library) {
    _subs.addAll([
      _player.stream.playing.listen((v) {
        playing = v;
        notifyListeners();
      }),
      _player.stream.buffering.listen((v) {
        buffering = v;
        notifyListeners();
      }),
      _player.stream.duration.listen((v) {
        duration = v;
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

  Track? get current => queue.current;
  Stream<Duration> get positionStream => _player.stream.position;
  Duration get position => _player.state.position;
  bool get shuffle => queue.shuffle;
  RepeatSetting get repeat => queue.repeat;

  /// Starts playing [tracks] from [start].
  Future<void> playTracks(List<Track> tracks, {int start = 0, bool? shuffle, String? label}) async {
    if (tracks.isEmpty) return;
    queue.setTracks(tracks, start: start, shuffle: shuffle, label: label);
    await _openCurrent();
  }

  /// Plays everything shuffled.
  Future<void> shufflePlay(List<Track> tracks, {String? label}) {
    if (tracks.isEmpty) return Future.value();
    final start = DateTime.now().microsecond % tracks.length;
    return playTracks(tracks, start: start, shuffle: true, label: label);
  }

  Future<void> _openCurrent({int skipsLeft = 20}) async {
    final t = queue.current;
    if (t == null) {
      await _player.stop();
      notifyListeners();
      return;
    }
    final uri = library.playableUri(t);
    if (uri == null) {
      // e.g. a server song while the server is switched off: skip it.
      lastError = 'Can\'t play "${t.title}" right now';
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
      await _player.open(Media(uri), play: true);
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
      // End of queue: stop at the start of the last song, like most players.
      await _player.pause();
      await _player.seek(Duration.zero);
      notifyListeners();
      return;
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

  Future<void> seek(Duration d) => _player.seek(d);
  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0.0, 100.0));

  void toggleShuffle() {
    queue.setShuffle(!queue.shuffle);
    notifyListeners();
  }

  void cycleRepeat() {
    queue.cycleRepeat();
    notifyListeners();
  }

  Future<void> jumpTo(int queueIndex) async {
    queue.jumpTo(queueIndex);
    await _openCurrent();
  }

  Future<void> playNext(Track t) async {
    final wasEmpty = queue.isEmpty;
    queue.playNext(t);
    if (wasEmpty) await _openCurrent();
    notifyListeners();
  }

  Future<void> addToQueue(Track t) async {
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

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
