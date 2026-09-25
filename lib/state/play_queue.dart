import 'dart:math';

import '../models/track.dart';

enum RepeatSetting { off, all, one }

/// Play-order logic: queue, position, shuffle and repeat. No audio here,
/// so it can be unit-tested on its own.
class PlayQueue {
  final Random _random;
  PlayQueue({Random? random}) : _random = random ?? Random();

  /// Order the tracks were queued in (used to undo shuffle).
  List<Track> _original = [];

  /// Actual play order.
  List<Track> _queue = [];
  int _pos = -1;

  bool shuffle = false;
  RepeatSetting repeat = RepeatSetting.off;

  /// Where the current list came from, e.g. "Album · Blue Train".
  String? contextLabel;

  List<Track> get tracks => List.unmodifiable(_queue);
  int get position => _pos;
  bool get isEmpty => _queue.isEmpty;
  Track? get current => (_pos >= 0 && _pos < _queue.length) ? _queue[_pos] : null;
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
      final first = tracks[start];
      final rest = [...tracks.sublist(0, start), ...tracks.sublist(start + 1)]..shuffle(_random);
      _queue = [first, ...rest];
      _pos = 0;
    } else {
      _queue = List.of(tracks);
      _pos = start;
    }
  }

  /// Moves forward. [auto] = the song finished by itself (repeat-one replays it).
  /// Returns the new current track, or null when the queue has ended.
  Track? next({bool auto = false}) {
    if (_queue.isEmpty) return null;
    if (auto && repeat == RepeatSetting.one) return current;
    if (_pos + 1 < _queue.length) {
      _pos++;
      return current;
    }
    if (repeat == RepeatSetting.all || (repeat == RepeatSetting.one && !auto)) {
      if (shuffle) {
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
    return current;
  }

  void jumpTo(int queueIndex) {
    if (queueIndex >= 0 && queueIndex < _queue.length) _pos = queueIndex;
  }

  void setShuffle(bool on) {
    if (on == shuffle) return;
    shuffle = on;
    if (_queue.isEmpty) return;
    final cur = current;
    if (on) {
      final upcoming = _queue.sublist(_pos + 1)..shuffle(_random);
      _queue = [..._queue.sublist(0, _pos + 1), ...upcoming];
    } else {
      _queue = List.of(_original);
      _pos = cur == null ? 0 : max(0, _queue.indexOf(cur));
    }
  }

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
    _original.remove(t);
  }

  /// Moves an upcoming item (indices into [upcoming]; [newIndex] is its final position).
  void moveUpcoming(int oldIndex, int newIndex) {
    final up = upcoming.length;
    if (oldIndex < 0 || oldIndex >= up) return;
    newIndex = newIndex.clamp(0, up - 1);
    final t = _queue.removeAt(_pos + 1 + oldIndex);
    _queue.insert(_pos + 1 + newIndex, t);
  }

  /// Swaps in updated copies of queued songs (e.g. after the user edits a
  /// song's details), matched by id. Order and position are unchanged.
  /// Returns true if anything changed.
  bool refresh(Track? Function(String id) lookup) {
    var changed = false;
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

  void clear() {
    _original = [];
    _queue = [];
    _pos = -1;
    contextLabel = null;
  }
}
