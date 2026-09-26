// Audiobook bookmarks, saved in bookmarks.json.
//
// A bookmark is "this file, at this position, with this note". It stores the file's track id
// (not the book's title), so a bookmark survives the book being renamed or re-grouped. When
// LibraryModel notices that files have moved, it calls `remapIds` so bookmarks follow them;
// when files are forgotten, `removeIds` drops their bookmarks. The book page and the player's
// bookmark list use `forBook` to show a book's bookmarks in listening order.
import 'package:flutter/foundation.dart';

import '../models/book.dart';
import '../services/storage.dart';

/// A saved spot in an audiobook, with an optional note.
class Bookmark {
  /// A unique id, made from the creation time (see BookmarksModel.add).
  final String id;

  /// The file (track id) it's in, and where.
  final String partId;
  final Duration position;
  /// The user's note ('' when there isn't one).
  final String note;
  /// When it was made, in milliseconds since 1970.
  final int createdMs;

  const Bookmark({
    required this.id,
    required this.partId,
    required this.position,
    this.note = '',
    required this.createdMs,
  });

  /// A copy with a new file (after a move) and/or note. The position and id never change.
  Bookmark copyWith({String? partId, String? note}) =>
      Bookmark(id: id, partId: partId ?? this.partId, position: position, note: note ?? this.note, createdMs: createdMs);

  // Short key names keep bookmarks.json small; an empty note isn't written at all.
  Map<String, dynamic> toJson() => {
        'id': id,
        'part': partId,
        'posMs': position.inMilliseconds,
        if (note.isNotEmpty) 'note': note,
        'created': createdMs,
      };

  // Missing optional fields fall back to sensible defaults; a missing id or part throws, and
  // load() then skips that entry.
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

  /// Every bookmark in every book, in the order they were made.
  List<Bookmark> _all = [];

  /// The clock, swappable in tests.
  @visibleForTesting
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  /// Reads bookmarks.json (called at start-up and after a backup is restored).
  Future<void> load() async {
    _all = [];
    final j = await storage.read(fileName);
    // One bad entry shouldn't lose all the others, so each is read on its own. If anything was
    // skipped, a copy of the file is kept before the next save replaces it.
    var damaged = j != null && j is! Map;
    final list = j is Map ? j['bookmarks'] : null;
    if (list != null && list is! List) damaged = true;
    for (final b in list is List ? list : const []) {
      try {
        _all.add(Bookmark.fromJson(b as Map<String, dynamic>));
      } catch (_) {
        damaged = true; // damaged entry: skip it
      }
    }
    if (damaged) await storage.keepCopy(fileName);
    notifyListeners();
  }

  /// Writes every bookmark back to bookmarks.json.
  Future<void> _save() => storage.write(fileName, {
        'bookmarks': [for (final b in _all) b.toJson()],
      });

  /// A book's bookmarks, in listening order.
  List<Bookmark> forBook(Book book) {
    // Keep only bookmarks whose file is one of this book's parts.
    final list = [for (final b in _all) if (book.indexOfPart(b.partId) >= 0) b];
    // Turn "file + position" into a position in the whole book, so bookmarks in later files
    // sort after earlier ones.
    Duration at(Bookmark b) => book.offsetOf(book.indexOfPart(b.partId), b.position);
    list.sort((a, b) => at(a).compareTo(at(b)));
    return list;
  }

  /// Adds a bookmark at [position] in the file [partId] and saves straight away.
  Future<Bookmark> add(String partId, Duration position, {String note = ''}) async {
    final created = now();
    final b = Bookmark(
      // The time plus the list length, so two bookmarks made in the same millisecond differ.
      id: '$created-${_all.length}',
      partId: partId,
      position: position.isNegative ? Duration.zero : position,
      note: note.trim(),
      createdMs: created,
    );
    _all.add(b);
    // Redraw first so the UI feels instant, then save to disk.
    notifyListeners();
    await _save();
    return b;
  }

  /// Changes a bookmark's note (does nothing if the bookmark has since been removed).
  Future<void> setNote(Bookmark b, String note) async {
    final i = _all.indexWhere((x) => x.id == b.id);
    if (i < 0) return;
    _all[i] = _all[i].copyWith(note: note.trim());
    notifyListeners();
    await _save();
  }

  /// Deletes a bookmark.
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
          // A tiny inline function so we can note that something changed while building the list.
          (() {
            changed = true;
            return b.copyWith(partId: moved[b.partId]);
          })()
        else
          b,
    ];
    // Only redraw and save when a bookmark actually moved.
    if (changed) {
      notifyListeners();
      _save();
    }
  }

  /// Drops bookmarks in files that were forgotten.
  void removeIds(Set<String> ids) {
    final before = _all.length;
    _all.removeWhere((b) => ids.contains(b.partId));
    // Only save if something was removed.
    if (_all.length != before) {
      notifyListeners();
      _save();
    }
  }
}
