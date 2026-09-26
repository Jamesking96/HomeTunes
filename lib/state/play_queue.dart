// The play queue: which songs are lined up, which one is playing, and the shuffle/repeat rules.
//
// This is pure logic with no audio in it. PlayerModel owns one PlayQueue and asks it what to
// play next; PlayerModel then tells the media_kit engine. Keeping the rules here (rather than
// using the engine's own playlist) means they can be unit tested and behave the same everywhere.
// Two lists are kept: `_queue` is the actual play order (shuffled or not), and `_original` is
// the order songs were queued in, so turning shuffle off can put things back.
import 'dart:math';

import '../models/track.dart';

/// Repeat modes, in the order the repeat button cycles through them.
enum RepeatSetting { off, all, one }

/// Play-order logic: queue, position, shuffle and repeat. No audio here,
/// so it can be unit-tested on its own.
class PlayQueue {
  // Passing in a Random with a fixed seed makes shuffles repeatable in tests.
  final Random _random;
  PlayQueue({Random? random}) : _random = random ?? Random();

  /// Order the tracks were queued in (used to undo shuffle).
  List<Track> _original = [];

  /// Actual play order.
  List<Track> _queue = [];
  // Index of the current song in _queue (-1 when the queue is empty).
  int _pos = -1;

  bool shuffle = false;
  RepeatSetting repeat = RepeatSetting.off;

  /// Where the current list came from, e.g. "Album · Blue Train".
  String? contextLabel;

  List<Track> get tracks => List.unmodifiable(_queue);

  /// The order the songs were queued in (what turning shuffle off goes back to).
  List<Track> get originalTracks => List.unmodifiable(_original);

  /// Puts back a queue saved earlier with [tracks] and [originalTracks] (used by "Back to music"
  /// after an audiobook), exactly as it was: play order, original order, place, shuffle, repeat.
  ///
  /// HomeTunes: before 0.1.15 the saved play order was loaded as if it were the original order,
  /// so after a book, turning shuffle off couldn't bring the original order back.
  void restore(
    List<Track> playOrder,
    List<Track> original, {
    required int position,
    required bool shuffle,
    required RepeatSetting repeat,
    String? label,
  }) {
    _queue = List.of(playOrder);
    // An empty or mismatched original order (shouldn't happen) falls back to the play order.
    _original = original.length == playOrder.length ? List.of(original) : List.of(playOrder);
    _pos = _queue.isEmpty ? -1 : position.clamp(0, _queue.length - 1);
    this.shuffle = shuffle;
    this.repeat = repeat;
    contextLabel = label;
  }

  int get position => _pos;
  bool get isEmpty => _queue.isEmpty;
  /// The song playing now, or null when nothing is queued.
  Track? get current => (_pos >= 0 && _pos < _queue.length) ? _queue[_pos] : null;
  /// The songs after the current one ("Up next").
  List<Track> get upcoming => _pos + 1 < _queue.length ? _queue.sublist(_pos + 1) : const [];

  /// Replaces the queue. With shuffle on, [start] plays first and the rest is shuffled.
  void setTracks(List<Track> tracks, {int start = 0, bool? shuffle, String? label}) {
    if (shuffle != null) this.shuffle = shuffle;
    contextLabel = label;
    _original = List.of(tracks);
    if (tracks.isEmpty) {
      _queue = [];
      _pos = -1;
      return;
    }
    start = start.clamp(0, tracks.length - 1);
    if (this.shuffle) {
      // The tapped song goes first; everything else (before and after it) is shuffled behind it.
      final first = tracks[start];
      final rest = [...tracks.sublist(0, start), ...tracks.sublist(start + 1)]..shuffle(_random);
      _queue = [first, ...rest];
      _pos = 0;
    } else {
      // Not shuffled: keep the list as it is and start at the tapped song, so "previous" can
      // still go back to the songs before it.
      _queue = List.of(tracks);
      _pos = start;
    }
  }

  /// Moves forward. [auto] = the song finished by itself (repeat-one replays it).
  /// Returns the new current track, or null when the queue has ended.
  Track? next({bool auto = false}) {
    if (_queue.isEmpty) return null;
    // Repeat-one only repeats when the song ends by itself; pressing Next still moves on.
    if (auto && repeat == RepeatSetting.one) return current;
    if (_pos + 1 < _queue.length) {
      _pos++;
      return current;
    }
    // At the end of the queue. Repeat-all loops back to the start. With repeat-one, pressing
    // Next on the last song also loops round rather than stopping.
    if (repeat == RepeatSetting.all || (repeat == RepeatSetting.one && !auto)) {
      if (shuffle) {
        // Each time round the loop gets a fresh shuffle.
        final last = _queue.last;
        _queue.shuffle(_random);
        // Avoid playing the same song twice in a row when the loop restarts.
        if (_queue.length > 1 && _queue.first == last) {
          _queue.add(_queue.removeAt(0));
        }
      }
      _pos = 0;
      return current;
    }
    // Repeat is off: the queue has finished.
    return null;
  }

  /// What will play when the current song ends by itself, without moving
  /// (used to load it early, for gapless playback). Null when the queue would
  /// end there, or when it can't be known yet: repeat-all with shuffle
  /// reshuffles when it loops.
  Track? peekNextAuto() {
    final cur = current;
    if (cur == null) return null;
    if (repeat == RepeatSetting.one) return cur;
    if (_pos + 1 < _queue.length) return _queue[_pos + 1];
    if (repeat == RepeatSetting.all && !shuffle) return _queue.first;
    return null;
  }

  /// Moves back one track (wraps round with repeat-all).
  Track? previous() {
    if (_queue.isEmpty) return null;
    if (_pos > 0) {
      _pos--;
    } else if (repeat == RepeatSetting.all) {
      _pos = _queue.length - 1;
    }
    // On the first song with repeat off, this just returns the same song (the player restarts it).
    return current;
  }

  /// Makes the song at [queueIndex] the current one (tapping a song in the queue list).
  void jumpTo(int queueIndex) {
    if (queueIndex >= 0 && queueIndex < _queue.length) _pos = queueIndex;
  }

  /// Turns shuffle on or off without interrupting the current song.
  void setShuffle(bool on) {
    if (on == shuffle) return;
    shuffle = on;
    if (_queue.isEmpty) return;
    final cur = current;
    if (on) {
      // Songs already played (and the current one) stay put; only what's coming up is shuffled.
      final upcoming = _queue.sublist(_pos + 1)..shuffle(_random);
      _queue = [..._queue.sublist(0, _pos + 1), ...upcoming];
    } else {
      // Go back to the original order and find the current song in it. If the same song is
      // queued twice, this lands on its first appearance.
      _queue = List.of(_original);
      _pos = cur == null ? 0 : max(0, _queue.indexOf(cur));
    }
  }

  /// Moves the repeat setting on to the next one (off → all → one → off) and returns it.
  RepeatSetting cycleRepeat() {
    repeat = RepeatSetting.values[(repeat.index + 1) % RepeatSetting.values.length];
    return repeat;
  }

  /// Inserts right after the current track.
  void playNext(Track t) {
    if (_queue.isEmpty) {
      setTracks([t]);
      return;
    }
    _queue.insert(_pos + 1, t);
    // Also slot it in after the current song in the original order, so it stays "next"
    // if shuffle is later turned off.
    final cur = current;
    final oi = cur == null ? -1 : _original.indexOf(cur);
    _original.insert(oi + 1, t);
  }

  /// Appends to the end of the queue.
  void add(Track t) {
    if (_queue.isEmpty) {
      setTracks([t]);
      return;
    }
    _queue.add(t);
    _original.add(t);
  }

  /// Removes an upcoming item; [upcomingIndex] is an index into [upcoming].
  void removeUpcoming(int upcomingIndex) {
    final i = _pos + 1 + upcomingIndex;
    if (i <= _pos || i >= _queue.length) return;
    final t = _queue.removeAt(i);
    // Removes the first copy in the original order (the same if the song is only queued once).
    _original.remove(t);
  }

  /// Moves an upcoming item (indices into [upcoming]; [newIndex] is its final position).
  void moveUpcoming(int oldIndex, int newIndex) {
    final up = upcoming.length;
    if (oldIndex < 0 || oldIndex >= up) return;
    newIndex = newIndex.clamp(0, up - 1);
    // Only the play order changes; the original order is left alone.
    final t = _queue.removeAt(_pos + 1 + oldIndex);
    _queue.insert(_pos + 1 + newIndex, t);
  }

  /// Swaps in updated copies of queued songs (e.g. after the user edits a
  /// song's details), matched by id. Order and position are unchanged.
  /// Returns true if anything changed.
  bool refresh(Track? Function(String id) lookup) {
    var changed = false;
    // Songs the lookup can't find (null) or that are already the same object are kept as is.
    List<Track> swap(List<Track> list) => [
          for (final t in list)
            () {
              final u = lookup(t.id);
              if (u == null || identical(u, t)) return t;
              changed = true;
              return u;
            }(),
        ];
    _queue = swap(_queue);
    _original = swap(_original);
    return changed;
  }

  /// Empties the queue completely.
  void clear() {
    _original = [];
    _queue = [];
    _pos = -1;
    contextLabel = null;
  }
}
