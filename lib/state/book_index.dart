import '../models/book.dart';
import '../models/track.dart';

/// Pure helpers for audiobooks (no Flutter, easy to test): deciding which
/// files are books, and grouping them into [Book]s.

/// Genres that mark a file as an audiobook unless the user changes the list.
const defaultBookGenres = ['Audiobook', 'Audio Book', 'Audiobooks', 'Spoken Word'];

/// "Audio Book", "audio-book" and "AUDIOBOOK" all compare the same.
String normalizeGenre(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// A folder called "Audiobooks", "Audio Books", "Harry Potter Audio Books 1-7"…
final _bookFolderName = RegExp(r'\baudio[\s_-]?books?\b', caseSensitive: false);

/// Decides whether a file is an audiobook.
class BookRules {
  final Set<String> _genres;

  /// Folders the user chose as audiobook folders: everything inside is a book.
  final List<String> bookFolders;

  /// The user's "Move to Books" (true) / "Move to Music" (false), by track id.
  final Map<String, bool> overrides;

  BookRules({
    Iterable<String> genres = defaultBookGenres,
    this.bookFolders = const [],
    this.overrides = const {},
  }) : _genres = {for (final g in genres) normalizeGenre(g)}..remove('');

  bool isBook(Track t) {
    final o = overrides[t.id];
    if (o != null) return o;
    final g = t.genre;
    if (g != null && _genres.contains(normalizeGenre(g))) return true;
    final path = t.path;
    if (path == null) return false;
    if (path.toLowerCase().endsWith('.m4b')) return true;
    final dirs = splitPath(path)..removeLast();
    if (dirs.any(_bookFolderName.hasMatch)) return true;
    return bookFolders.any((f) => isInside(path, f));
  }
}

/// Path parts, whichever slashes the path uses.
List<String> splitPath(String path) => path.split(RegExp(r'[\\/]+')).where((s) => s.isNotEmpty).toList();

/// True when [path] is inside [folder] (case-insensitive, either slash).
bool isInside(String path, String folder) {
  final a = splitPath(path.toLowerCase());
  final b = splitPath(folder.toLowerCase());
  if (b.isEmpty || a.length <= b.length) return false;
  for (var i = 0; i < b.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Compares file names so "Part 2" comes before "Part 10".
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final x = re.allMatches(a.toLowerCase()).toList();
  final y = re.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final p = x[i].group(0)!, q = y[i].group(0)!;
    final pn = int.tryParse(p), qn = int.tryParse(q);
    final c = (pn != null && qn != null) ? pn.compareTo(qn) : p.compareTo(q);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

int comparePartsInBook(Track a, Track b) {
  final d = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
  if (d != 0) return d;
  final t = (a.trackNumber ?? 1 << 30).compareTo(b.trackNumber ?? 1 << 30);
  if (t != 0) return t;
  return naturalCompare(_fileName(a), _fileName(b));
}

String _fileName(Track t) => t.path == null ? t.title : splitPath(t.path!).last;

/// Which book a file belongs to. Each .m4b file is a book of its own; other
/// files are grouped by folder and album, so different books sharing a folder
/// stay apart. (Not by author: one file tagged "J. K. Rowling" and the rest
/// "J.K. Rowling" is still one book.) Server files have no folder, so there
/// the author is used instead.
String bookKey(Track t) {
  final path = t.path;
  if (path != null && path.toLowerCase().endsWith('.m4b')) return 'file:${t.id}';
  final album = t.album.toLowerCase();
  if (path == null) return 'server\u0000$album\u0000${bookAuthor(t).toLowerCase()}';
  final dir = (splitPath(path)..removeLast()).join('/').toLowerCase();
  return '$dir\u0000$album';
}

String bookAuthor(Track t) {
  if (t.albumArtist.isNotEmpty && t.albumArtist != 'Unknown Artist') return t.albumArtist;
  return t.artist;
}

/// "Book 01 - Title", "Vol. 2: Title", "03. Title" → (1, "Title").
final _numbered = RegExp(r'^(?:book|vol(?:ume)?\.?|part|no\.?|#)?\s*(\d+(?:\.\d+)?)\s*[-–.:)]\s*(.+)$', caseSensitive: false);

/// "Read by Stephen Fry", "Narrated by …".
final _narrator = RegExp(r'\b(?:read|narrated|performed)\s+by\s+([^;\[\](){},]+)', caseSensitive: false);

/// Series name from a folder like "Harry Potter Audio Books 1-7; Read by Stephen Fry [MP3]".
String? seriesFromFolder(String name) {
  var s = name.split(RegExp(r'[;\[(]')).first;
  s = s.replaceAll(
      RegExp(r'\b(complete|unabridged|audio[\s_-]?books?|collection|series|box\s?set)\b', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'\b\d+\s*[-–]\s*\d+\b'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceAll(RegExp(r'^[-–,:.\s]+|[-–,:.\s]+$'), '');
  return s.isEmpty ? null : s;
}

/// Builds the book from its files (already in order).
Book buildBook(String key, List<Track> parts) {
  final first = parts.first;
  final path = first.path;
  final segments = path == null ? const <String>[] : splitPath(path);
  final isFileBook = key.startsWith('file:');
  // The name that describes this book: the file for an .m4b, else its folder.
  String? own;
  String? parent;
  if (segments.length >= 2) {
    own = isFileBook ? segments.last.replaceFirst(RegExp(r'\.[^.]+$'), '') : segments[segments.length - 2];
    parent = isFileBook ? segments[segments.length - 2] : (segments.length >= 3 ? segments[segments.length - 3] : null);
  }

  double? index;
  String? series;
  var title = first.album;
  final m = own == null ? null : _numbered.firstMatch(own);
  if (m != null) {
    index = double.tryParse(m.group(1)!);
    series = parent == null ? null : seriesFromFolder(parent);
    // A title that only came from the folder name loses its "Book 01 - ".
    if (title == own) title = m.group(2)!.trim();
  }
  if (isFileBook && title == (segments.length >= 2 ? segments[segments.length - 2] : null) && own != null) {
    // No album tag on an .m4b: use its file name rather than the folder's.
    title = m?.group(2)?.trim() ?? own;
  }

  // Details the user set win over what the folder names suggest.
  T? fromEdits<T>(T? Function(Track t) f) {
    for (final t in parts) {
      final v = f(t);
      if (v != null) return v;
    }
    return null;
  }

  final editedSeries = fromEdits((t) => t.series);
  if (editedSeries != null) series = editedSeries.isEmpty ? null : editedSeries; // "" = not in a series
  index = fromEdits((t) => t.seriesIndex) ?? index;

  final editedNarrator = fromEdits((t) => t.narrator);
  String? narrator;
  if (editedNarrator != null) {
    narrator = editedNarrator.isEmpty ? null : editedNarrator; // "" = none
  } else {
    for (final name in [own, parent]) {
      final n = name == null ? null : _narrator.firstMatch(name);
      if (n != null) {
        narrator = n.group(1)!.trim();
        break;
      }
    }
  }

  final years = parts.map((t) => t.year).whereType<int>().where((y) => y > 0);
  // The author most of the files agree on.
  final votes = <String, int>{};
  for (final t in parts) {
    final a = bookAuthor(t);
    votes[a] = (votes[a] ?? 0) + 1;
  }
  final author = votes.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  return Book(
    id: 'book:$key',
    title: title,
    author: author,
    narrator: narrator,
    series: series,
    seriesIndex: series == null ? null : index,
    year: years.isEmpty ? null : years.reduce((a, b) => a < b ? a : b),
    parts: parts,
  );
}

/// Groups audiobook files into books, sorted by title.
List<Book> groupBooks(Iterable<Track> tracks) {
  final map = <String, List<Track>>{};
  for (final t in tracks) {
    (map[bookKey(t)] ??= []).add(t);
  }
  final books = [
    for (final e in map.entries) buildBook(e.key, e.value..sort(comparePartsInBook)),
  ];
  books.sort((a, b) => naturalCompare(a.title, b.title));
  return books;
}

List<String> _searchWords(String q) =>
    q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// Books whose title, author, narrator or series contain every word of [q].
/// Titles that start with the search come first.
List<Book> searchBookList(Iterable<Book> books, String q) {
  final words = _searchWords(q);
  if (words.isEmpty) return const [];
  final query = words.join(' ');
  final hits = [
    for (final b in books)
      if (words.every('${b.title} ${b.author} ${b.narrator ?? ''} ${b.series ?? ''}'.toLowerCase().contains)) b
  ];
  int rank(Book b) {
    final t = b.title.toLowerCase();
    if (t.startsWith(query)) return 0;
    if (t.contains(query)) return 1;
    return 2;
  }

  hits.sort((a, b) {
    final c = rank(a).compareTo(rank(b));
    return c != 0 ? c : naturalCompare(a.title, b.title);
  });
  return hits;
}

/// Chapters whose name contains every word of [q] (e.g. "diagon alley").
List<({Book book, int chapter})> searchChapterList(Iterable<Book> books, String q, {int limit = 40}) {
  final words = _searchWords(q);
  if (words.isEmpty) return const [];
  final out = <({Book book, int chapter})>[];
  for (final b in books) {
    final chapters = b.chapters;
    for (var i = 0; i < chapters.length; i++) {
      final title = chapters[i].title.toLowerCase();
      if (words.every(title.contains)) {
        out.add((book: b, chapter: i));
        if (out.length >= limit) return out;
      }
    }
  }
  return out;
}
