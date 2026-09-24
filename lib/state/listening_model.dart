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
  final bool finished;

  const BookProgress({
    required this.partId,
    required this.position,
    required this.updatedMs,
    this.finished = false,
  });

  BookProgress copyWith({String? partId, Duration? position, int? updatedMs, bool? finished}) => BookProgress(
        partId: partId ?? this.partId,
        position: position ?? this.position,
        updatedMs: updatedMs ?? this.updatedMs,
        finished: finished ?? this.finished,
      );

  Map<String, dynamic> toJson() => {
        'part': partId,
        'posMs': position.inMilliseconds,
        'updated': updatedMs,
        if (finished) 'finished': true,
      };

  factory BookProgress.fromJson(Map<String, dynamic> j) => BookProgress(
        partId: j['part'] as String,
        position: Duration(milliseconds: (j['posMs'] as int?) ?? 0),
        updatedMs: (j['updated'] as int?) ?? 0,
        finished: (j['finished'] as bool?) ?? false,
      );
}

enum BookState { notStarted, inProgress, finished }

/// Remembers the listener's place in every audiobook (listening.json).
class ListeningModel extends ChangeNotifier {
  final Storage storage;
  ListeningModel(this.storage);

  static const fileName = 'listening.json';

  Map<String, BookProgress> _byBook = {};

  /// For tests / time control.
  @visibleForTesting
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  Future<void> load() async {
    _byBook = {};
    final j = await storage.read(fileName) as Map<String, dynamic>?;
    final books = j?['books'];
    if (books is Map) {
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
    for (final e in _byBook.entries) {
      if (b.indexOfPart(e.value.partId) >= 0) {
        // Adopt the old entry under the book's new id.
        final p = _byBook.remove(e.key)!;
        _byBook[b.id] = p;
        _save();
        return p;
      }
    }
    return null;
  }

  BookState stateOf(Book b) {
    final p = progressFor(b);
    if (p == null) return BookState.notStarted;
    if (p.finished) return BookState.finished;
    final i = b.indexOfPart(p.partId);
    if (i <= 0 && p.position < const Duration(seconds: 5)) return BookState.notStarted;
    return BookState.inProgress;
  }

  /// How far through the book (0–1).
  double fractionDone(Book b) {
    final p = progressFor(b);
    if (p == null) return 0;
    if (p.finished) return 1;
    final total = b.duration;
    if (total <= Duration.zero) return 0;
    final i = b.indexOfPart(p.partId);
    if (i < 0) return 0;
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
      finished: finished ?? false,
    );
    _byBook[b.id] = p;
    final visible = old == null || old.partId != partId || old.finished != p.finished ||
        (old.position - p.position).abs() > const Duration(seconds: 30);
    if (visible) notifyListeners();
    await _save();
  }

  Future<void> setFinished(Book b, bool finished) async {
    final old = progressFor(b);
    if (finished) {
      _byBook[b.id] = BookProgress(
        partId: b.parts.last.id,
        position: b.parts.last.duration,
        updatedMs: now(),
        finished: true,
      );
    } else if (old != null) {
      // "Not finished" starts it over.
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

  int lastListened(Book b) => progressFor(b)?.updatedMs ?? 0;

  /// Files the progress points at (kept by the "songs not on this device" check).
  Set<String> get referencedIds => {for (final p in _byBook.values) p.partId};

  /// Files that moved (old id → new id) keep the listener's place.
  void remapIds(Map<String, String> moved) {
    var changed = false;
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
