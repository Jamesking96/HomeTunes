// Audiobook rules and grouping: which files count as books, and how files become Books.
//
// Plain functions with no Flutter in them, so they're easy to unit test. LibraryModel builds a
// `BookRules` from the user's settings and calls `isBook` on every song while rebuilding the
// library; the book files are then handed to `groupBooks`, which turns them into Book objects
// (one per .m4b file, or one per folder + album otherwise). Series, number and narrator are
// guessed from folder names, but anything the user edited (or a sidecar file supplied) wins.
// The bottom of the file has the sorting, grouping and filtering used by the Books tab.
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

  /// Every folder that's scanned (music and audiobook folders). Rule 5 only looks at the
  /// folder names from the scanned folder down, so an "Audiobooks" folder somewhere above it
  /// doesn't turn all the music below into books. Empty: the whole path is checked.
  final List<String> roots;

  BookRules({
    Iterable<String> genres = defaultBookGenres,
    this.bookFolders = const [],
    this.overrides = const {},
    this.roots = const [],
  }) : _genres = {for (final g in genres) normalizeGenre(g)}..remove('');

  /// True if [t] belongs on the Books tab. The checks run in order and the first that
  /// applies decides (see 03_FEATURES_AND_DESIGN_NOTES.md, "Which files are books").
  bool isBook(Track t) => why(t).$1;

  /// Whether [t] is a book, and the rule that decided it, in plain words (for the Details page).
  (bool, String) why(Track t) {
    // 1. The user's own "Move to Books/Music" choice always wins.
    final o = overrides[t.id];
    if (o != null) return (o, o ? 'You moved it to Books' : 'You moved it to Music');
    // 2. A book details file beside it, e.g. Libation's .metadata.json.
    if (t.hasBookInfo) return (true, 'It has a book details file beside it');
    // 3. A book genre, compared loosely (see normalizeGenre).
    final g = t.genre;
    if (g != null && _genres.contains(normalizeGenre(g))) return (true, 'Its genre is "$g"');
    // The remaining checks need a file path, so server songs stop here.
    final path = t.path;
    if (path == null) return (false, 'It\'s music from the server');
    // 4. .m4b is an audiobook-only format.
    if (path.toLowerCase().endsWith('.m4b')) return (true, 'It\'s an .m4b file (an audiobook format)');
    // 5. Any folder in the path named like "Audio Books" (the file name itself is left out),
    //    counting from the scanned folder the file is in (its own name included) downwards.
    //    HomeTunes (0.1.16): it used to check the whole path, so e.g. D:\Audiobooks\Music as a
    //    music folder turned every song in it into a book.
    final dirs = _foldersFromRoot(path);
    final named = dirs.where(_bookFolderName.hasMatch).firstOrNull;
    if (named != null) return (true, 'It\'s inside a folder called "$named"');
    // 6. Inside one of the folders the user marked as audiobook folders.
    final folder = bookFolders.where((f) => isInside(path, f)).firstOrNull;
    if (folder != null) return (true, 'It\'s in your audiobook folder $folder');
    return (false, 'None of the audiobook rules apply');
  }

  /// The folder names of [path] from the deepest scanned folder containing it (that folder's
  /// own name included) down to the file's folder. The whole path's folders when no scanned
  /// folder contains it.
  List<String> _foldersFromRoot(String path) {
    final parts = splitPath(path)..removeLast();
    var best = -1;
    for (final r in roots) {
      final n = splitPath(r).length;
      if (n > best && n <= parts.length + 1 && isInside(path, r)) best = n;
    }
    // Keep the root's own name (index best - 1) and everything below it.
    return best <= 0 ? parts : parts.sublist(best - 1);
  }
}

/// Path parts, whichever slashes the path uses.
List<String> splitPath(String path) => path.split(RegExp(r'[\\/]+')).where((s) => s.isNotEmpty).toList();

/// True when [path] is inside [folder] (case-insensitive, either slash).
bool isInside(String path, String folder) {
  final a = splitPath(path.toLowerCase());
  final b = splitPath(folder.toLowerCase());
  // The path must be longer than the folder (a file inside it), and start with the same parts.
  // Comparing whole parts means "C:/Books2/x.mp3" doesn't count as inside "C:/Books".
  if (b.isEmpty || a.length <= b.length) return false;
  for (var i = 0; i < b.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Compares file names so "Part 2" comes before "Part 10".
int naturalCompare(String a, String b) {
  // Split both names into runs of digits and runs of non-digits, then compare run by run:
  // number runs as numbers, text runs as text (ignoring case).
  final re = RegExp(r'(\d+)|(\D+)');
  final x = re.allMatches(a.toLowerCase()).toList();
  final y = re.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final p = x[i].group(0)!, q = y[i].group(0)!;
    final pn = int.tryParse(p), qn = int.tryParse(q);
    final c = (pn != null && qn != null) ? pn.compareTo(qn) : p.compareTo(q);
    if (c != 0) return c;
  }
  // All shared runs are equal: the shorter name comes first.
  return x.length.compareTo(y.length);
}

/// Orders a book's files: by disc, then track number, then file name (naturally).
/// Files without a track number go after those with one.
int comparePartsInBook(Track a, Track b) {
  final d = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
  if (d != 0) return d;
  final t = (a.trackNumber ?? 1 << 30).compareTo(b.trackNumber ?? 1 << 30);
  if (t != 0) return t;
  return naturalCompare(_fileName(a), _fileName(b));
}

/// The file name (or the title for server files, which have no path).
String _fileName(Track t) => t.path == null ? t.title : splitPath(t.path!).last;

/// Which book a file belongs to. Each .m4b file is a book of its own; other
/// files are grouped by folder and album, so different books sharing a folder
/// stay apart. (Not by author: one file tagged "J. K. Rowling" and the rest
/// "J.K. Rowling" is still one book.) Server files have no folder, so there
/// the author is used instead.
String bookKey(Track t) {
  final path = t.path;
  // The \u0000 character separates the parts, as it can't appear in a name.
  if (path != null && path.toLowerCase().endsWith('.m4b')) return 'file:${t.id}';
  final album = t.album.toLowerCase();
  if (path == null) return 'server\u0000$album\u0000${bookAuthor(t).toLowerCase()}';
  final dir = (splitPath(path)..removeLast()).join('/').toLowerCase();
  return '$dir\u0000$album';
}

/// A file's author: the album artist, unless it's blank or the "Unknown Artist" placeholder,
/// in which case the (track) artist.
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
  // Keep only what comes before any ";", "[" or "(" (these usually hold the narrator/format).
  var s = name.split(RegExp(r'[;\[(]')).first;
  // Drop filler words like "Complete", "Unabridged", "Audio Books", "Box Set"…
  s = s.replaceAll(
      RegExp(r'\b(complete|unabridged|audio[\s_-]?books?|collection|series|box\s?set)\b', caseSensitive: false), ' ');
  // …number ranges like "1-7"…
  s = s.replaceAll(RegExp(r'\b\d+\s*[-–]\s*\d+\b'), ' ');
  // …then tidy up the spaces and any stray punctuation left at either end.
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceAll(RegExp(r'^[-–,:.\s]+|[-–,:.\s]+$'), '');
  return s.isEmpty ? null : s;
}

/// Builds the book from its files (already in order).
Book buildBook(String key, List<Track> parts) {
  // 1. Find the names that describe this book: its own name (the .m4b file or the folder the
  //    files are in) and the one above it (often a series folder).
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

  // 2. Guess the series number and name. A name like "Book 01 - Title" gives the number,
  //    and then the folder above is taken as the series name.
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

  // 3. Series details from edits or sidecars replace the guesses.
  final editedSeries = fromEdits((t) => t.series);
  if (editedSeries != null) series = editedSeries.isEmpty ? null : editedSeries; // "" = not in a series
  index = fromEdits((t) => t.seriesIndex) ?? index;

  // 4. The narrator: from edits/sidecars if set, else "Read by …" in the book's folder names.
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

  // 5. The year is the earliest one found on any file.
  final years = parts.map((t) => t.year).whereType<int>().where((y) => y > 0);
  // The author most of the files agree on.
  final votes = <String, int>{};
  for (final t in parts) {
    final a = bookAuthor(t);
    votes[a] = (votes[a] ?? 0) + 1;
  }
  // On a tie, the author seen first wins.
  final author = votes.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  return Book(
    id: 'book:$key',
    title: title,
    author: author,
    narrator: narrator,
    series: series,
    // A number without a series name makes no sense on its own, so it's dropped.
    seriesIndex: series == null ? null : index,
    year: years.isEmpty ? null : years.reduce((a, b) => a < b ? a : b),
    description: fromEdits((t) => t.description),
    // PDFs etc. from every file, without duplicates.
    companions: {for (final t in parts) ...t.companions}.toList(),
    parts: parts,
  );
}

/// Groups audiobook files into books, sorted by title.
List<Book> groupBooks(Iterable<Track> tracks) {
  // Bucket the files by book key, put each bucket's files in order, then build the books.
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

/// Splits a search into lower-case words.
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
  // 0 = title starts with the search, 1 = title contains it, 2 = matched elsewhere.
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
    // Stop as soon as we have enough, so a short query over a big library stays quick.
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

// ---------------------------------------------------------------- Books tab sorting & filtering

/// The sort choices on the Books page.
enum BookSort { recentlyListened, title, author, narrator, series, recentlyAdded }

/// Header for books with no narrator / not in a series (listed last).
const noNarrator = 'Narrator not known';
const noSeries = 'Not in a series';

/// Series order: by series name (books outside a series by their title),
/// then number in the series, then title.
int compareBySeries(Book a, Book b) {
  final c = naturalCompare(a.series ?? a.title, b.series ?? b.title);
  if (c != 0) return c;
  final n = (a.seriesIndex ?? double.infinity).compareTo(b.seriesIndex ?? double.infinity);
  return n != 0 ? n : naturalCompare(a.title, b.title);
}

/// Books in display order, split into headed groups for the author /
/// narrator / series sorts. Inside a group, books in a series follow their
/// series number.
List<(String?, List<Book>)> sortBooks(
  List<Book> books,
  BookSort sort, {
  int Function(Book b)? lastListened,
}) {
  int byTitle(Book a, Book b) => naturalCompare(a.title, b.title);
  // Title, recently added and recently listened give one list with no headings (null);
  // author, narrator and series give one headed group per name.
  switch (sort) {
    case BookSort.title:
      return [(null, [...books]..sort(byTitle))];
    case BookSort.recentlyAdded:
      return [(null, [...books]..sort((a, b) => b.addedMs.compareTo(a.addedMs)))];
    case BookSort.recentlyListened:
      // Most recently listened first; books never listened to fall back to series order.
      final listened = lastListened ?? (_) => 0;
      return [
        (
          null,
          [...books]
            ..sort((a, b) {
              final c = listened(b).compareTo(listened(a));
              return c != 0 ? c : compareBySeries(a, b);
            })
        )
      ];
    case BookSort.author:
    case BookSort.narrator:
    case BookSort.series:
      // The "not known" group always goes at the end of the list.
      final last = switch (sort) {
        BookSort.narrator => noNarrator,
        BookSort.series => noSeries,
        _ => '',
      };
      String keyOf(Book b) => switch (sort) {
            BookSort.author => b.author,
            BookSort.narrator => b.narrator ?? noNarrator,
            _ => b.series ?? noSeries,
          };
      // Bucket the books by name, then sort the headings, keeping the "not known" one last.
      final map = <String, List<Book>>{};
      for (final b in books) {
        (map[keyOf(b)] ??= []).add(b);
      }
      final keys = map.keys.toList()
        ..sort((a, b) {
          if (a == last) return 1;
          if (b == last) return -1;
          return naturalCompare(a, b);
        });
      return [for (final k in keys) (k, map[k]!..sort(compareBySeries))];
  }
}

/// Narrowing the Books tab to one author, narrator and/or series.
class BookFilters {
  final String? author;
  final String? narrator;
  final String? series;
  const BookFilters({this.author, this.narrator, this.series});

  /// No filters: every book shows.
  static const none = BookFilters();

  bool get isEmpty => author == null && narrator == null && series == null;

  /// True if [b] passes every filter that is set (unset filters let everything through).
  bool matches(Book b) =>
      (author == null || b.author == author) &&
      (narrator == null || b.narrator == narrator) &&
      (series == null || b.series == series);

  // null means "keep as is", so the clear… flags are how a filter gets removed.
  BookFilters copyWith({String? author, String? narrator, String? series, bool clearAuthor = false,
          bool clearNarrator = false, bool clearSeries = false}) =>
      BookFilters(
        author: clearAuthor ? null : (author ?? this.author),
        narrator: clearNarrator ? null : (narrator ?? this.narrator),
        series: clearSeries ? null : (series ?? this.series),
      );

  /// The authors / narrators / series to choose from, with how many books each has.
  static Map<String, int> choices(Iterable<Book> books, String? Function(Book b) of) {
    final counts = <String, int>{};
    for (final b in books) {
      final v = of(b);
      if (v != null && v.isNotEmpty) counts[v] = (counts[v] ?? 0) + 1;
    }
    final keys = counts.keys.toList()..sort(naturalCompare);
    return {for (final k in keys) k: counts[k]!};
  }
}

// ---------------------------------------------------------------- the Series tab (0.1.74)

/// The order the series come in on the Audiobooks Series tab. Inside a series the books always
/// follow their number, and "Not in a series" is always last.
enum SeriesSort { name, author, recentlyListened, recentlyAdded, mostBooks }

/// [books] in one headed group per series (the heading is the series name), ordered by [sort]
/// (the other way round when [reverse]), then the books that aren't in a series under
/// [noSeries], by title.
List<(String?, List<Book>)> sortSeries(
  List<Book> books,
  SeriesSort sort, {
  int Function(Book b)? lastListened,
  bool reverse = false,
}) {
  final map = <String, List<Book>>{};
  final loose = <Book>[];
  for (final b in books) {
    final s = b.series;
    if (s == null || s.trim().isEmpty) {
      loose.add(b);
    } else {
      (map[s] ??= []).add(b);
    }
  }
  for (final g in map.values) {
    g.sort(compareBySeries);
  }
  final listened = lastListened ?? (_) => 0;
  int latest(List<Book> g) => g.fold(0, (m, b) => listened(b) > m ? listened(b) : m);
  int added(List<Book> g) => g.fold(0, (m, b) => b.addedMs > m ? b.addedMs : m);
  final keys = map.keys.toList()
    ..sort((a, b) {
      final ga = map[a]!, gb = map[b]!;
      final c = switch (sort) {
        SeriesSort.name => 0,
        SeriesSort.author => naturalCompare(ga.first.author, gb.first.author),
        SeriesSort.recentlyListened => latest(gb).compareTo(latest(ga)),
        SeriesSort.recentlyAdded => added(gb).compareTo(added(ga)),
        SeriesSort.mostBooks => gb.length.compareTo(ga.length),
      };
      return c != 0 ? c : naturalCompare(a, b);
    });
  return [
    for (final k in reverse ? keys.reversed : keys) (k, map[k]!),
    if (loose.isNotEmpty) (noSeries, loose..sort((a, b) => naturalCompare(a.title, b.title))),
  ];
}

// ---------------------------------------------------------------- series (0.1.75)

/// One audiobook series: its name and its books in reading order. Series have no file of their
/// own; they're the books that share a series name.
class BookSeries {
  final String name;
  final List<Book> books;
  const BookSeries(this.name, this.books);

  /// The authors, most books first ("A. Writer" or "A. Writer, B. Other").
  List<String> get authors {
    final counts = <String, int>{};
    for (final b in books) {
      if (b.author.isNotEmpty) counts[b.author] = (counts[b.author] ?? 0) + 1;
    }
    return counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  /// The first book with a cover, for the series' picture.
  Book get coverBook => books.firstWhere((b) => b.artTrack != null, orElse: () => books.first);
}

/// The series [name]'s books in reading order, or null when no book has that series.
BookSeries? seriesNamed(Iterable<Book> books, String name) {
  final list = [for (final b in books) if (b.series == name) b];
  return list.isEmpty ? null : BookSeries(name, list..sort(compareBySeries));
}

/// [groups] from [sortSeries] as series (the "Not in a series" group left out).
List<BookSeries> seriesOf(List<(String?, List<Book>)> groups) => [
      for (final (h, g) in groups)
        if (h != null && h != noSeries) BookSeries(h, g)
    ];
