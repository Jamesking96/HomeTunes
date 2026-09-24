import 'package:flutter/foundation.dart';

import '../models/book.dart';
import '../services/storage.dart';

/// A saved spot in an audiobook, with an optional note.
class Bookmark {
  final String id;

  /// The file (track id) it's in, and where.
  final String partId;
  final Duration position;
  final String note;
  final int createdMs;

  const Bookmark({
    required this.id,
    required this.partId,
    required this.position,
    this.note = '',
    required this.createdMs,
  });

  Bookmark copyWith({String? partId, String? note}) =>
      Bookmark(id: id, partId: partId ?? this.partId, position: position, note: note ?? this.note, createdMs: createdMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'part': partId,
        'posMs': position.inMilliseconds,
        if (note.isNotEmpty) 'note': note,
        'created': createdMs,
      };

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        id: j['id'] as String,
        partId: j['part'] as String,
        position: Duration(milliseconds: (j['posMs'] as int?) ?? 0),
        note: (j['note'] as String?) ?? '',
        createdMs: (j['created'] as int?) ?? 0,
      );
}

/// Bookmarks in audiobooks (bookmarks.json). They point at a file and a
/// position, so they follow a book when it's renamed or its files move.
class BookmarksModel extends ChangeNotifier {
  final Storage storage;
  BookmarksModel(this.storage);

  static const fileName = 'bookmarks.json';

  List<Bookmark> _all = [];

  @visibleForTesting
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  Future<void> load() async {
    _all = [];
    final j = await storage.read(fileName) as Map<String, dynamic>?;
    for (final b in (j?['bookmarks'] as List? ?? const [])) {
      try {
        _all.add(Bookmark.fromJson(b as Map<String, dynamic>));
      } catch (_) {
        // Damaged entry: skip it.
      }
    }
    notifyListeners();
  }

  Future<void> _save() => storage.write(fileName, {
        'bookmarks': [for (final b in _all) b.toJson()],
      });

  /// A book's bookmarks, in listening order.
  List<Bookmark> forBook(Book book) {
    final list = [for (final b in _all) if (book.indexOfPart(b.partId) >= 0) b];
    Duration at(Bookmark b) => book.offsetOf(book.indexOfPart(b.partId), b.position);
    list.sort((a, b) => at(a).compareTo(at(b)));
    return list;
  }

  Future<Bookmark> add(String partId, Duration position, {String note = ''}) async {
    final created = now();
    final b = Bookmark(
      id: '$created-${_all.length}',
      partId: partId,
      position: position.isNegative ? Duration.zero : position,
      note: note.trim(),
      createdMs: created,
    );
    _all.add(b);
    notifyListeners();
    await _save();
    return b;
  }

  Future<void> setNote(Bookmark b, String note) async {
    final i = _all.indexWhere((x) => x.id == b.id);
    if (i < 0) return;
    _all[i] = _all[i].copyWith(note: note.trim());
    notifyListeners();
    await _save();
  }

  Future<void> remove(Bookmark b) async {
    _all.removeWhere((x) => x.id == b.id);
    notifyListeners();
    await _save();
  }

  /// Files bookmarks point at (kept by the "songs not on this device" check).
  Set<String> get referencedIds => {for (final b in _all) b.partId};

  /// Files that moved (old id → new id): bookmarks follow them.
  void remapIds(Map<String, String> moved) {
    var changed = false;
    _all = [
      for (final b in _all)
        if (moved.containsKey(b.partId))
          (() {
            changed = true;
            return b.copyWith(partId: moved[b.partId]);
          })()
        else
          b,
    ];
    if (changed) {
      notifyListeners();
      _save();
    }
  }

  /// Drops bookmarks in files that were forgotten.
  void removeIds(Set<String> ids) {
    final before = _all.length;
    _all.removeWhere((b) => ids.contains(b.partId));
    if (_all.length != before) {
      notifyListeners();
      _save();
    }
  }
}
