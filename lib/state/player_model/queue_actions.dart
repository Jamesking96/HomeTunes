// Part of PlayerModel (refactor phase 11, 9 Oct 2026: player_model.dart was over 1,000 lines).
// The queue buttons and menus: shuffle play, shuffle and repeat, jump to a song, Play next, Add to
// queue, and removing or moving what's coming up.
part of '../player_model.dart';

extension PlayerQueueActions on PlayerModel {
  /// Plays everything shuffled.
  Future<void> shufflePlay(List<Track> tracks, {String? label}) {
    if (tracks.isEmpty) return Future.value();
    final start = Random().nextInt(tracks.length);
    return playTracks(tracks, start: start, shuffle: true, label: label);
  }

  void toggleShuffle() {
    if (book != null) return; // books always play in order
    queue.setShuffle(!queue.shuffle);
    _changed();
    _syncLoadedAhead();
  }

  /// Off → all → one → off. Books don't repeat, so it does nothing during a book.
  void cycleRepeat() {
    if (book != null) return;
    queue.cycleRepeat();
    _changed();
    _syncLoadedAhead();
  }

  /// Plays the song at [queueIndex] (tapping a song in the queue list).
  Future<void> jumpTo(int queueIndex) async {
    queue.jumpTo(queueIndex);
    await _openCurrent();
  }

  /// "Play next": puts [t] straight after the current song. If nothing was playing, it starts.
  Future<void> playNext(Track t) async {
    if (book != null) {
      // Goes into the waiting music queue; the book keeps playing.
      _addToWaitingMusic(t, next: true);
      return;
    }
    final wasEmpty = queue.isEmpty;
    queue.playNext(t);
    if (wasEmpty) await _openCurrent();
    _changed();
    // The song loaded ahead in the engine is now probably wrong, so fix it up.
    await _syncLoadedAhead();
  }

  /// "Add to queue": puts [t] at the end. If nothing was playing, it starts.
  Future<void> addToQueue(Track t) async {
    if (book != null) {
      _addToWaitingMusic(t, next: false);
      return;
    }
    final wasEmpty = queue.isEmpty;
    queue.add(t);
    if (wasEmpty) await _openCurrent();
    _changed();
    await _syncLoadedAhead();
  }

  /// Removes song [i] from "Up next" (after that, the engine's preloaded song is re-checked).
  void removeUpcoming(int i) {
    queue.removeUpcoming(i);
    _changed();
    _syncLoadedAhead();
  }

  /// Drag-to-reorder in "Up next".
  void moveUpcoming(int from, int to) {
    queue.moveUpcoming(from, to);
    _changed();
    _syncLoadedAhead();
  }
}
