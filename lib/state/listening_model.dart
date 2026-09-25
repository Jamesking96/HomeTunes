// Remembers where the listener is in each audiobook, saved in listening.json.
//
// For every book it keeps: which file they were in, the position in that file, when they last
// listened, whether they finished it, and the speed they chose for it. PlayerModel calls
// `record` every few seconds while a book plays (and when pausing), and reads the place back to
// resume. The Books pages use `stateOf`, `fractionDone`, `timeLeft` and `inProgress` for the
// progress bars and the "Continue listening" row. The place is stored as "file + position"
// rather than one big offset, so it stays right even if the book's files are re-grouped.
import 'package:flutter/foundation.dart';

import '../models/book.dart';
import '../services/storage.dart';

/// Where the listener is in one book.
class BookProgress {
  /// The file (track id) they were in.
  final String partId;

  /// Position within that file.
  final Duration position;

  /// When they last listened (ms since epoch).
  final int updatedMs;
  /// True once the user finished the book (or marked it as finished).
  final bool finished;

  /// Playback speed chosen for this book (null = the default speed).
  final double? speed;

  const BookProgress({
    required this.partId,
    required this.position,
    required this.updatedMs,
    this.finished = false,
    this.speed,
  });

  // Note: because `null` means "keep the old value" here, copyWith can't clear the speed.
  BookProgress copyWith({String? partId, Duration? position, int? updatedMs, bool? finished, double? speed}) =>
      BookProgress(
        partId: partId ?? this.partId,
        position: position ?? this.position,
        updatedMs: updatedMs ?? this.updatedMs,
        finished: finished ?? this.finished,
        speed: speed ?? this.speed,
      );

  // "finished" and "speed" are only written when set, to keep the file small.
  Map<String, dynamic> toJson() => {
        'part': partId,
        'posMs': position.inMilliseconds,
        'updated': updatedMs,
        if (finished) 'finished': true,
        if (speed != null) 'speed': speed,
      };

  factory BookProgress.fromJson(Map<String, dynamic> j) => BookProgress(
        partId: j['part'] as String,
        position: Duration(milliseconds: (j['posMs'] as int?) ?? 0),
        updatedMs: (j['updated'] as int?) ?? 0,
        finished: (j['finished'] as bool?) ?? false,
        // JSON may hold a whole number like 2 instead of 2.0, so read it as any number.
        speed: (j['speed'] as num?)?.toDouble(),
      );
}

/// The three states shown on book covers and used by the Books page filters.
enum BookState { notStarted, inProgress, finished }

/// Remembers the listener's place in every audiobook (listening.json).
class ListeningModel extends ChangeNotifier {
  final Storage storage;
  ListeningModel(this.storage);

  static const fileName = 'listening.json';

  /// Saved places, keyed by book id.
  Map<String, BookProgress> _byBook = {};

  /// For tests / time control.
  @visibleForTesting
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  /// Reads listening.json (at start-up and after a backup is restored).
  Future<void> load() async {
    _byBook = {};
    final j = await storage.read(fileName) as Map<String, dynamic>?;
    final books = j?['books'];
    if (books is Map) {
      // Read each book on its own so one damaged entry doesn't lose the rest.
      for (final e in books.entries) {
        if (e.value is Map<String, dynamic>) {
          try {
            _byBook[e.key as String] = BookProgress.fromJson(e.value as Map<String, dynamic>);
          } catch (_) {
            // Damaged entry: skip it.
          }
        }
      }
    }
    notifyListeners();
  }

  Future<void> _save() => storage.write(fileName, {
        'books': {for (final e in _byBook.entries) e.key: e.value.toJson()},
      });

  /// The saved place in [b], if any. A book whose folder moved gets a new id,
  /// so this also finds its old entry through the file it was in.
  BookProgress? progressFor(Book b) {
    final direct = _byBook[b.id];
    if (direct != null) return direct;
    // No entry under this id: look for one whose file belongs to this book.
    for (final e in _byBook.entries) {
      if (b.indexOfPart(e.value.partId) >= 0) {
        // Adopt the old entry under the book's new id.
        // (We return straight after changing the map, so changing it mid-loop is safe here.)
        final p = _byBook.remove(e.key)!;
        _byBook[b.id] = p;
        _save();
        return p;
      }
    }
    return null;
  }

  /// Not started, in progress or finished.
  BookState stateOf(Book b) {
    final p = progressFor(b);
    if (p == null) return BookState.notStarted;
    if (p.finished) return BookState.finished;
    final i = b.indexOfPart(p.partId);
    // Less than 5 seconds into the first file counts as "not started", so a quick peek at a
    // book doesn't put it on the "Continue listening" row.
    if (i <= 0 && p.position < const Duration(seconds: 5)) return BookState.notStarted;
    return BookState.inProgress;
  }

  /// How far through the book (0–1).
  double fractionDone(Book b) {
    final p = progressFor(b);
    if (p == null) return 0;
    if (p.finished) return 1;
    final total = b.duration;
    // Avoid dividing by zero for books whose lengths aren't known yet.
    if (total <= Duration.zero) return 0;
    final i = b.indexOfPart(p.partId);
    if (i < 0) return 0;
    // offsetOf turns "file + position" into a position in the whole book.
    return (b.offsetOf(i, p.position).inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Time left to listen.
  Duration timeLeft(Book b) {
    final p = progressFor(b);
    if (p == null) return b.duration;
    if (p.finished) return Duration.zero;
    final i = b.indexOfPart(p.partId);
    if (i < 0) return b.duration;
    final left = b.duration - b.offsetOf(i, p.position);
    return left.isNegative ? Duration.zero : left;
  }

  /// Saves the listener's place. Doesn't notify listeners unless something
  /// visible changes (called every few seconds while playing).
  Future<void> record(Book b, String partId, Duration position, {bool? finished}) async {
    final old = progressFor(b);
    final p = BookProgress(
      partId: partId,
      position: position.isNegative ? Duration.zero : position,
      updatedMs: now(),
      // Recording a place without saying "finished" marks the book as not finished, so
      // listening to a finished book again puts it back in progress.
      finished: finished ?? false,
      speed: old?.speed, // keep the book's chosen speed
    );
    _byBook[b.id] = p;
    // Redrawing the whole Books page every few seconds would be wasteful, so only notify when
    // the change is big enough to show (new file, finished state, or a jump of over 30 s).
    final visible = old == null || old.partId != partId || old.finished != p.finished ||
        (old.position - p.position).abs() > const Duration(seconds: 30);
    if (visible) notifyListeners();
    await _save();
  }

  /// The speed chosen for [b], or null for the default.
  double? speedFor(Book b) => progressFor(b)?.speed;

  /// Remembers a speed for [b]. If the book has never been played, a place at the very start
  /// is saved along with it, since the speed lives in the book's progress entry.
  Future<void> setSpeed(Book b, double speed) async {
    final old = progressFor(b);
    _byBook[b.id] = old?.copyWith(speed: speed) ??
        BookProgress(partId: b.parts.first.id, position: Duration.zero, updatedMs: now(), speed: speed);
    notifyListeners();
    await _save();
  }

  /// Marks [b] as finished (placing the listener at the very end), or not finished.
  Future<void> setFinished(Book b, bool finished) async {
    final old = progressFor(b);
    if (finished) {
      _byBook[b.id] = BookProgress(
        partId: b.parts.last.id,
        position: b.parts.last.duration,
        updatedMs: now(),
        finished: true,
        speed: old?.speed,
      );
    } else if (old != null) {
      // "Not finished" starts it over.
      // (This also forgets the book's chosen speed, as it's stored in the same entry.)
      _byBook.remove(b.id);
    }
    notifyListeners();
    await _save();
  }

  /// Books being listened to, most recent first.
  List<Book> inProgress(Iterable<Book> books) {
    final list = [for (final b in books) if (stateOf(b) == BookState.inProgress) b];
    list.sort((a, b) => lastListened(b).compareTo(lastListened(a)));
    return list;
  }

  /// When [b] was last listened to (ms since epoch), or 0 if never.
  int lastListened(Book b) => progressFor(b)?.updatedMs ?? 0;

  /// Files the progress points at (kept by the "songs not on this device" check).
  Set<String> get referencedIds => {for (final p in _byBook.values) p.partId};

  /// Files that moved (old id → new id) keep the listener's place.
  void remapIds(Map<String, String> moved) {
    var changed = false;
    // Rebuild the map, swapping in the new file id wherever a file moved. The little inline
    // function lets us note that something changed while building it.
    _byBook = {
      for (final e in _byBook.entries)
        e.key: moved.containsKey(e.value.partId)
            ? (() {
                changed = true;
                return e.value.copyWith(partId: moved[e.value.partId]);
              })()
            : e.value,
    };
    if (changed) {
      notifyListeners();
      _save();
    }
  }

  /// Forgets the place in books whose files were forgotten.
  void removeIds(Set<String> ids) {
    final before = _byBook.length;
    _byBook.removeWhere((_, p) => ids.contains(p.partId));
    if (_byBook.length != before) {
      notifyListeners();
      _save();
    }
  }
}
