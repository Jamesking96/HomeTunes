// The Book model: plain data describing one audiobook.
// Books aren't stored anywhere; they're rebuilt from the library's tracks by `groupBooks` in
// state/book_index.dart every time the library changes. The player's book mode, the Books tab
// and the book pages all read these. A book can be one big file (like an .m4b with chapters
// inside) or many files; the helpers below turn "file + position" into "time in the whole book"
// and list the chapters across all its files.
import 'track.dart';

/// An audiobook: one or more audio files ("parts") played in order.
class Book {
  /// Stable id built from where the book is (see `bookKey`).
  final String id;
  final String title;
  final String author;
  final String? narrator;
  final String? series;
  final double? seriesIndex;
  final int? year;

  /// About the book (from a metadata or text file beside it).
  final String? description;

  /// Files that come with the book, like a PDF (paths).
  final List<String> companions;

  /// Files in playing order.
  final List<Track> parts;

  Book({
    required this.id,
    required this.title,
    required this.author,
    this.narrator,
    this.series,
    this.seriesIndex,
    this.year,
    this.description,
    this.companions = const [],
    required this.parts,
  });

  /// First part that has a cover.
  Track? get artTrack {
    for (final t in parts) {
      if (t.art != null) return t;
    }
    return parts.isEmpty ? null : parts.first;
  }

  /// Total length of all the parts added together.
  Duration get duration => parts.fold(Duration.zero, (a, t) => a + t.duration);

  /// Newest file's modified time (for "recently added").
  int get addedMs => parts.fold<int>(0, (m, t) => (t.modifiedMs ?? 0) > m ? (t.modifiedMs ?? 0) : m);

  /// Which part (file) a track is, or -1 if it isn't part of this book.
  int indexOfPart(String trackId) => parts.indexWhere((t) => t.id == trackId);

  /// Time from the start of the book to [position] in part [partIndex].
  Duration offsetOf(int partIndex, Duration position) {
    var total = Duration.zero;
    for (var i = 0; i < partIndex && i < parts.length; i++) {
      total += parts[i].duration;
    }
    return total + position;
  }

  /// Chapters across the whole book: markers inside files, otherwise one per file.
  List<BookChapter> get chapters {
    final out = <BookChapter>[];
    var offset = Duration.zero;
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      // A file with no chapter markers counts as one chapter, named after the file's title.
      if (part.chapters.isEmpty) {
        out.add(BookChapter(part: i, start: Duration.zero, offset: offset, title: part.title));
      } else {
        // Chapters without a name get a number (counted across the whole book).
        for (final c in part.chapters) {
          out.add(BookChapter(
            part: i,
            start: c.start,
            offset: offset + c.start,
            title: c.title.isEmpty ? 'Chapter ${out.length + 1}' : c.title,
          ));
        }
      }
      offset += part.duration;
    }
    return out;
  }

  /// "Harry Potter 1" / "Harry Potter" / null.
  String? get seriesLabel {
    if (series == null) return null;
    if (seriesIndex == null) return series;
    final i = seriesIndex!;
    // Show "2" rather than "2.0", but keep in-between numbers like "2.5".
    return '$series ${i == i.roundToDouble() ? i.round() : i}';
  }

  // Two books are "the same" when their ids match, even if details were edited since.
  @override
  bool operator ==(Object other) => other is Book && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A place to jump to in a book.
class BookChapter {
  /// Which file it's in.
  final int part;

  /// Where it starts within that file.
  final Duration start;

  /// Where it starts from the beginning of the book.
  final Duration offset;
  final String title;

  const BookChapter({required this.part, required this.start, required this.offset, required this.title});
}
