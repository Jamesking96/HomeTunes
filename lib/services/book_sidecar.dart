// Audiobook "side files": the extra files that sit next to audio files (metadata JSON, covers,
// description text, PDFs). local_scanner.dart calls findSidecars() for every file it reads and,
// when there's a metadata file, BookInfo.parse() to pull out the book's details, which then
// win over the (often messy) tags. Having a metadata file also marks the file as a book.
// Note: on Android the app can only see audio files in shared storage, so this mostly helps
// on Windows. The long doc comment below lists exactly which files are recognised.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/track.dart';

/// Extra files that often sit next to audiobooks, and what HomeTunes uses
/// from them:
/// - `<name>.metadata.json` (Libation / audible-cli: Audible's details) or an
///   Audiobookshelf `metadata.json`: title, authors, narrators, series and
///   number, year, genres, description, and chapters for files that have none.
/// - a cover image: `<name>.jpg`, `cover.jpg`, `folder.jpg`, `<folder>.jpg`, or
///   the only picture in the folder.
/// - a description: `<name>.txt`, `desc.txt`, `description.txt`, `summary.txt`,
///   `info.txt` or `readme.txt`.
/// - companion files (PDFs that come with some books).
///
/// Everything here is pure file reading, safe to run in a background isolate.

// File names that are recognised (all compared in lower case).
const imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
const _coverNames = ['cover', 'folder', 'front', 'album', 'poster'];
const _descriptionNames = ['desc', 'description', 'summary', 'info', 'readme', 'about'];
const companionExtensions = {'.pdf', '.epub'};

/// Book details from a metadata file.
class BookInfo {
  final String? title;
  final String? subtitle;
  final List<String> authors;
  final List<String> narrators;
  final String? series;
  final double? seriesIndex;
  final int? year;
  final List<String> genres;
  final String? description;

  /// Chapters from the start of the audio (already adjusted for Audible's
  /// "brand" intro when the file has had it removed). Only trusted when the
  /// book is a single file of about [runtime].
  final List<Chapter> chapters;
  final Duration? runtime;

  /// Audible's intro and outro ("This is Audible"), which tools like Libation
  /// can cut from the file.
  final Duration brandIntro;
  final Duration brandOutro;

  const BookInfo({
    this.title,
    this.subtitle,
    this.authors = const [],
    this.narrators = const [],
    this.series,
    this.seriesIndex,
    this.year,
    this.genres = const [],
    this.description,
    this.chapters = const [],
    this.runtime,
    this.brandIntro = Duration.zero,
    this.brandOutro = Duration.zero,
  });

  /// All authors / narrators as one line, like "A, B".
  String? get author => authors.isEmpty ? null : authors.join(', ');
  String? get narrator => narrators.isEmpty ? null : narrators.join(', ');

  /// The chapters, lined up with a file that is [fileLength] long. Empty if
  /// the file doesn't look like the audio the chapters describe.
  List<Chapter> chaptersFor(Duration fileLength) {
    if (chapters.isEmpty) return const [];  // nothing to line up
    final full = runtime;
    // Length unknown on either side: keep the chapters as long as they fit inside the file.
    if (full == null || full <= Duration.zero || fileLength <= Duration.zero) {
      return chapters.last.start < fileLength || fileLength <= Duration.zero ? chapters : const [];
    }
    // Is this file the full Audible audio, or a copy with the Audible intro/outro cut off?
    // Whichever length is closer tells us; a cut copy starts earlier, so shift the chapters.
    final trimmed = full - brandIntro - brandOutro;
    final diffFull = (fileLength - full).inMilliseconds.abs();
    final diffTrimmed = (fileLength - trimmed).inMilliseconds.abs();
    // More than a minute out either way: a different recording or edition.
    if (diffFull > 60000 && diffTrimmed > 60000) return const [];
    final shift = diffTrimmed < diffFull ? brandIntro : Duration.zero;
    return [
      for (final c in chapters)
        Chapter(c.start - shift < Duration.zero ? Duration.zero : c.start - shift, c.title),
    ];
  }

  /// Reads either format. Null if it isn't a book metadata file.
  static BookInfo? parse(String text) {
    Object? j;
    try {
      j = jsonDecode(text.startsWith('﻿') ? text.substring(1) : text);
    } catch (_) {
      return null;
    }
    if (j is! Map<String, dynamic>) return null;
    // Tell the two formats apart: Audible's has ChapterInfo, product images or authors with
    // an "asin" (Amazon's id). Anything else that looks like a book is Audiobookshelf's.
    final audible = j['ChapterInfo'] is Map ||
        j['product_images'] != null ||
        (j['authors'] is List && (j['authors'] as List).any((a) => a is Map && a['asin'] != null));
    if (audible) return _fromAudible(j);
    if (j['title'] is String || j['authors'] is List || j['chapters'] is List) return _fromAudiobookshelf(j);
    return null;
  }

  /// Libation / audible-cli: Audible's own product details.
  static BookInfo _fromAudible(Map<String, dynamic> j) {
    // Audible lists people as [{"name": ..., "asin": ...}].
    List<String> names(Object? list) => [
          for (final a in (list is List ? list : const []))
            if (a is Map && a['name'] is String) (a['name'] as String).trim(),
        ].where((s) => s.isNotEmpty).toList();

    // "David French - translator", "Stephen Fry - introductions": not the author.
    final allAuthors = names(j['authors']);
    final authors = allAuthors.where((a) => !RegExp(r'\s[-–]\s*\w').hasMatch(a)).toList();

    // Only the first series is used (a book can belong to several).
    String? series;
    double? index;
    final s = j['series'];
    if (s is List && s.isNotEmpty && s.first is Map) {
      series = _str((s.first as Map)['title']);
      index = parseSeriesNumber(_str((s.first as Map)['sequence']));
    }

    // Audible files genres as "ladders" (e.g. Fiction > Fantasy > Epic); use the last,
    // most specific step of each.
    final genres = <String>[];
    final ladders = j['category_ladders'];
    if (ladders is List) {
      for (final l in ladders) {
        final steps = l is Map ? l['ladder'] : null;
        if (steps is List && steps.isNotEmpty && steps.last is Map) {
          final g = _str((steps.last as Map)['name']);
          if (g != null && !genres.contains(g)) genres.add(g);
        }
      }
    }

    // Milliseconds that might arrive as a number or as text.
    Duration? ms(Object? v) {
      final n = v is num ? v : num.tryParse('${v ?? ''}');
      return n == null ? null : Duration(milliseconds: n.round());
    }

    final chapters = <Chapter>[];
    final info = j['ChapterInfo'];
    if (info is Map) {
      // Chapters can be nested (a Part with chapters inside). Walk them all and flatten them,
      // naming the inner ones "Part: Chapter" so they still make sense on their own.
      void walk(Object? list, String? parent) {
        if (list is! List) return;
        for (var i = 0; i < list.length; i++) {
          final c = list[i];
          if (c is! Map) continue;
          final title = _str(c['title']) ?? '';
          final start = ms(c['start_offset_ms']) ?? Duration.zero;
          final kids = c['chapters'];
          final named = parent == null ? title : '$parent: $title';
          if (kids is List && kids.isNotEmpty) {
            // A heading ("A Grain of Truth") that only leads into its parts:
            // keep it only if it's more than a few seconds long.
            final length = ms(c['length_ms']) ?? Duration.zero;
            if (length > const Duration(seconds: 10)) chapters.add(Chapter(start, named));
            walk(kids, named);
          } else {
            chapters.add(Chapter(start, named));
          }
        }
      }

      walk(info['chapters'], null);
      chapters.sort((a, b) => a.start.compareTo(b.start));  // nested lists may be out of order
    }

    return BookInfo(
      title: _str(j['title']),
      subtitle: _str(j['subtitle']),
      authors: authors.isEmpty ? allAuthors : authors,  // if everyone was filtered out
      narrators: names(j['narrators']),
      series: series,
      seriesIndex: index,
      year: _year(_str(j['release_date']) ?? _str(j['issue_date']) ?? _str(j['publication_datetime'])),
      genres: genres,
      description: htmlToText(_str(j['publisher_summary']) ?? _str(j['merchandising_summary'])),
      chapters: chapters,
      runtime: info is Map ? ms(info['runtime_length_ms']) : null,
      brandIntro: info is Map ? ms(info['brandIntroDurationMs']) ?? Duration.zero : Duration.zero,
      brandOutro: info is Map ? ms(info['brandOutroDurationMs']) ?? Duration.zero : Duration.zero,
    );
  }

  /// Audiobookshelf's metadata.json.
  static BookInfo _fromAudiobookshelf(Map<String, dynamic> j) {
    // Audiobookshelf may list names as plain strings or as {"name": ...} objects.
    List<String> strings(Object? v) => [
          for (final x in (v is List ? v : const []))
            if (x is String && x.trim().isNotEmpty) x.trim() else if (x is Map && x['name'] is String) (x['name'] as String).trim(),
        ];
    String? series;
    double? index;
    final s = strings(j['series']);
    if (s.isNotEmpty) {
      // "The Witcher #3"
      final m = RegExp(r'^(.*?)\s*#\s*([\d.]+)\s*$').firstMatch(s.first);
      series = m == null ? s.first : m.group(1)!.trim();
      index = m == null ? null : parseSeriesNumber(m.group(2));
    }
    // Chapter starts here are in seconds (with decimals).
    final chapters = <Chapter>[
      for (final c in (j['chapters'] is List ? j['chapters'] as List : const []))
        if (c is Map && c['start'] is num)
          Chapter(Duration(milliseconds: ((c['start'] as num) * 1000).round()), _str(c['title']) ?? ''),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final desc = _str(j['description']);
    return BookInfo(
      title: _str(j['title']),
      subtitle: _str(j['subtitle']),
      authors: strings(j['authors']),
      narrators: strings(j['narrators']),
      series: series,
      seriesIndex: index,
      year: _year(_str(j['publishedYear']) ?? _str(j['publishedDate'])),
      genres: strings(j['genres']),
      description: desc == null ? null : (desc.contains('<') ? htmlToText(desc) : desc),
      chapters: chapters,
    );
  }
}

/// A tidy string from any JSON value. Python-made files sometimes write "None" for empty.
String? _str(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty || s == 'None' || s == 'null' ? null : s;
}

/// The first believable year (1500-2999) in a date like "2019-05-07".
int? _year(String? s) {
  final m = s == null ? null : RegExp(r'\b(1[5-9]\d\d|2\d\d\d)\b').firstMatch(s);
  return m == null ? null : int.parse(m.group(1)!);
}

/// "3" → 3, "0.1" → 0.1, "1-5" → 1, "" → null.
double? parseSeriesNumber(String? s) {
  final m = s == null ? null : RegExp(r'\d+(?:\.\d+)?').firstMatch(s);
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// Store descriptions are HTML: turn paragraphs and line breaks into new
/// lines and drop the rest of the markup.
String? htmlToText(String? html) {
  if (html == null) return null;
  // 1. Turn block ends into line breaks, list items into bullets, then drop all other tags.
  var s = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>|</div>|</h\d>|</ul>|</ol>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  // 2. Decode the common HTML character codes.
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
  // 3. Trim each line and allow at most one blank line in a row.
  s = s.split('\n').map((l) => l.trim()).join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return s.isEmpty ? null : s;
}

/// What sits next to one audio file.
class Sidecars {
  /// Path of the book metadata JSON, if any.
  final String? metadataFile;

  /// The metadata file is named after this audio file (not shared by a folder).
  final bool metadataIsOwn;
  /// Path of the best cover picture found, if any.
  final String? image;

  /// The picture is named after this audio file, so it wins over the art
  /// inside the file (usually it's the same cover, bigger).
  final bool imageIsOwn;
  /// Path of a text file with the book's description.
  final String? descriptionFile;
  /// PDFs / EPUBs that come with the book.
  final List<String> companions;

  /// Changes whenever any of these files is added, removed or changed, so a
  /// rescan knows to read the audio file's details again.
  final int stamp;

  const Sidecars({
    this.metadataFile,
    this.metadataIsOwn = false,
    this.image,
    this.imageIsOwn = false,
    this.descriptionFile,
    this.companions = const [],
    this.stamp = 0,
  });

  /// Nothing found.
  static const none = Sidecars();

  bool get isEmpty => metadataFile == null && image == null && descriptionFile == null && companions.isEmpty;
}

/// Lists folders once per scan batch (many files share a folder).
class FolderCache {
  // Folder path -> the files in it. An unreadable folder counts as empty.
  final Map<String, List<File>> _files = {};

  List<File> filesIn(String dir) => _files[dir] ??= () {
        try {
          return Directory(dir).listSync(followLinks: false).whereType<File>().toList();
        } on FileSystemException {
          return <File>[];
        }
      }();
}

/// Finds the extra files for the audio file at [audioPath].
Sidecars findSidecars(String audioPath, FolderCache folders) {
  final dir = p.dirname(audioPath);
  final base = p.basenameWithoutExtension(audioPath).toLowerCase();
  final folderName = p.basename(dir).toLowerCase();
  final files = folders.filesIn(dir);
  // How many audio files share this folder: with just one, any side file must be for it.
  final audioInFolder = files.where((f) => _isAudio(f.path)).length;

  String? metadata, image, description;
  var metadataIsOwn = false;
  var imageRank = 99, descRank = 99;
  final companions = <String>[];
  // Side files that affect this track; their names and dates make up the [stamp].
  final used = <File>[];

  // Look at every file in the folder once and sort it into the right kind.
  for (final f in files) {
    final name = p.basename(f.path).toLowerCase();
    final ext = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    if (name == '$base.metadata.json' || name == '$base.json') {
      metadata = f.path;
      metadataIsOwn = true;
      used.add(f);
    } else if (name == 'metadata.json' && metadata == null) {
      metadata = f.path;
      used.add(f);
    } else if (imageExtensions.contains(ext)) {
      // Best picture wins: named after the audio file, then cover/folder/..., then named
      // after the folder, then any other picture.
      final rank = stem == base
          ? 0
          : _coverNames.contains(stem)
              ? 1
              : stem == folderName
                  ? 2
                  : 3;
      if (rank < imageRank) {
        imageRank = rank;
        image = f.path;
      }
      used.add(f);
    } else if (ext == '.txt') {
      // Same idea for text: named after the audio file first, then desc.txt, description.txt...
      final named = _descriptionNames.indexOf(stem);
      final rank = stem == base ? 0 : (named < 0 ? 99 : named + 1);
      if (rank < descRank) {
        descRank = rank;
        description = f.path;
      }
      if (rank < 99) used.add(f);  // ignore unrelated .txt files
    } else if (companionExtensions.contains(ext)) {
      // With several books in one folder, only files named after this one.
      if (audioInFolder <= 1 || stem.startsWith(base) || base.startsWith(stem)) companions.add(f.path);
      used.add(f);
    }
  }
  // Any other picture only counts if it's the one picture in the folder.
  if (imageRank == 3 && files.where((f) => imageExtensions.contains(p.extension(f.path).toLowerCase())).length > 1) {
    image = null;
  }
  companions.sort();

  // A collection folder above (with no audio of its own) can hold the
  // description of all the books in it ("Info.txt" beside "Book 01", "Book 02"…).
  final parent = p.dirname(dir);
  if (description == null && parent != dir) {
    final above = folders.filesIn(parent);
    if (!above.any((f) => _isAudio(f.path))) {
      for (final f in above) {
        final stem = p.basenameWithoutExtension(f.path).toLowerCase();
        if (p.extension(f.path).toLowerCase() == '.txt' && _descriptionNames.contains(stem)) {
          description = f.path;
          used.add(f);
          break;
        }
      }
    }
  }

  // Mix the used files' names and modified times into one number. If any of them is added,
  // removed or edited, the number changes and the next scan re-reads this track.
  var stamp = 17;
  for (final f in used) {
    int modified;
    try {
      modified = f.statSync().modified.millisecondsSinceEpoch;
    } catch (_) {
      modified = 0;
    }
    stamp = Object.hash(stamp, p.basename(f.path), modified);
  }
  return Sidecars(
    metadataFile: metadata,
    metadataIsOwn: metadataIsOwn || (metadata != null && audioInFolder <= 1),  // one-file book
    image: image,
    imageIsOwn: image != null && imageRank == 0 && p.dirname(image) == dir,
    descriptionFile: description,
    companions: companions,
    stamp: used.isEmpty ? 0 : stamp,
  );
}

/// Same list as audioExtensions in local_scanner.dart.
bool _isAudio(String path) =>
    const {'.mp3', '.flac', '.m4a', '.m4b', '.mp4', '.aac', '.ogg', '.opus', '.wav'}.contains(p.extension(path).toLowerCase());

/// Reads a small text file (UTF-8, or Latin-1 if that fails). Null if it
/// can't be read, or is empty or too big to be a description.
String? readSmallText(String path, {int maxBytes = 200000}) {
  try {
    final f = File(path);
    if (f.lengthSync() > maxBytes) return null;
    final bytes = f.readAsBytesSync();
    String s;
    try {
      s = utf8.decode(bytes);
    } on FormatException {
      s = latin1.decode(bytes);
    }
    if (s.startsWith('﻿')) s = s.substring(1);
    s = s.replaceAll('\r\n', '\n').trim();
    return s.isEmpty ? null : s;
  } catch (_) {
    return null;
  }
}
