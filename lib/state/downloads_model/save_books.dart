// Saving audiobooks into your own folders (5 Nov 2026). Part of downloads_model.dart.
//
// The user: "Give me the ability to download the audiobooks to save them locally." A download
// stays in HomeTunes' own data folder and follows the server; Make it mine copied one file into a
// music-style Artist / Album folder, so a book of several files couldn't be saved whole. Here a
// whole book (an Audiobookshelf one, or one from the music server) is saved:
//  * Its files not downloaded yet are downloaded first (the original files), and the book is
//    remembered as waiting ("saveBooks" in downloads.json, so it carries on after a restart);
//    once the last one arrives it's saved by itself.
//  * The copy goes in <folder>/<Author>/<Series>/<n - Title>/ (or <Author>/<Title>/), the way
//    Audiobookshelf lays books out: the parts as "01 - Part.mp3" (a one-file book is named after
//    the book), the cover as cover.jpg, and an Audiobookshelf metadata.json (title, authors,
//    narrators, series and number, year, genres, description, and a one-file book's chapters),
//    which book_sidecar.dart reads back, so your edits to the book come with it.
//  * The folder is rescanned and the place you'd got to moves to the saved book (file, position,
//    finished, speed). The downloads go (the files are yours now), keeping it offline stops, and
//    the server still has it.
part of '../downloads_model.dart';

extension SaveBooks on DownloadsModel {
  /// The folders a book can be saved into: the audiobook folders first, then the music folders
  /// (a music folder's books are found by the usual rules, and metadata.json marks it a book).
  List<String> get bookFolders => {...library.audiobookFolders, ...library.folders}.toList();

  /// Whether book [bookId] is waiting for its files, to be saved into a folder.
  bool isSavingBook(String bookId) => _saveBooks.containsKey(bookId);

  /// The folder book [bookId] is waiting to be saved into, or null.
  String? savingBookTo(String bookId) => _saveBooks[bookId];

  /// The parts of [b] that come from a server (only those can be saved).
  static List<Track> serverParts(Book b) =>
      [for (final t in b.parts) if (isRemoteBookId(t.id) || t.id.startsWith('server:')) t];

  /// Saves book [b] into [root] (one of [bookFolders]). When all its files are here it's copied
  /// now and the new folder's path is returned; otherwise the missing ones are downloaded and it's
  /// saved once they're all here (null is returned). Throws a [FileSystemException] when it can't
  /// be copied there.
  Future<String?> saveBook(Book b, String root) async {
    final parts = serverParts(b);
    if (parts.isEmpty) throw const FileSystemException('This book is already one of your own files.');
    final missing = [for (final t in parts) if (!isDownloaded(t.id)) t];
    if (missing.isEmpty) {
      _saveBooks.remove(b.id);
      return _copyBook(b, root);
    }
    _saveBooks[b.id] = root;
    download([for (final t in missing) DownloadItem.track(t, book: true)], const DownloadQuality.original());
    notifyListeners();
    await _save();
    return null;
  }

  /// Stops waiting to save book [bookId] (its downloads carry on; Stop downloading stops them).
  Future<void> cancelSaveBook(String bookId) async {
    if (_saveBooks.remove(bookId) == null) return;
    notifyListeners();
    await _save();
  }

  /// Saves the waiting books whose files are all here now (after each download, and at start).
  Future<void> _saveReadyBooks() async {
    if (_savingBooks || _saveBooks.isEmpty) return;
    _savingBooks = true;
    try {
      for (final e in _saveBooks.entries.toList()) {
        final b = library.bookById(e.key);
        // Not in the library (yet): the server hasn't been read since starting. Left waiting.
        if (b == null) continue;
        final parts = serverParts(b);
        if (parts.isEmpty) {
          _saveBooks.remove(e.key);
          continue;
        }
        if (!parts.every((t) => isDownloaded(t.id))) continue;
        _saveBooks.remove(e.key);
        try {
          final to = await _copyBook(b, e.value);
          onNotice?.call('"${b.title}" is saved in $to');
        } catch (x) {
          onNotice?.call('Couldn\'t save "${b.title}" into ${e.value}: ${x is FileSystemException ? x.message : x}. '
              'Its downloads are kept; try Save to my audiobooks again.');
        }
      }
      await _save();
    } finally {
      _savingBooks = false;
    }
  }

  /// The folders [b] goes in, under the one chosen: Author, Series (if any), "n - Title".
  static List<String> bookFolderNames(Book b) {
    String number(double n) => n == n.roundToDouble() ? '${n.round()}' : '$n';
    final title = DownloadsModel._name(b.title);
    final series = b.series?.trim() ?? '';
    return [
      DownloadsModel._name(b.author.trim().isEmpty ? 'Unknown author' : b.author),
      if (series.isNotEmpty) DownloadsModel._name(series),
      b.seriesIndex != null && series.isNotEmpty ? '${number(b.seriesIndex!)} - $title' : title,
    ];
  }

  /// The folder [b] goes in under [root].
  static String bookFolderFor(Book b, String root) => p.joinAll([root, ...bookFolderNames(b)]);

  /// Audiobookshelf's metadata.json for [b] (what book_sidecar.dart reads back).
  static Map<String, dynamic> bookMetadata(Book b) {
    List<String> names(String? s) => [
          for (final x in (s ?? '').split(RegExp(r'\s*[,;]\s*'))) if (x.trim().isNotEmpty) x.trim(),
        ];
    String number(double n) => n == n.roundToDouble() ? '${n.round()}' : '$n';
    final genres = <String>{for (final t in b.parts) if (t.genre != null && t.genre!.trim().isNotEmpty) t.genre!.trim()};
    // One file: its chapters (seconds from the start). Several: each file has its own (or is one).
    final chapters = b.parts.length == 1 ? b.parts.single.chapters : const <Chapter>[];
    final length = b.parts.length == 1 ? b.parts.single.duration : Duration.zero;
    return {
      'title': b.title,
      'authors': names(b.author),
      'narrators': names(b.narrator),
      'series': [if (b.series != null && b.series!.trim().isNotEmpty) '${b.series!.trim()}${b.seriesIndex == null ? '' : ' #${number(b.seriesIndex!)}'}'],
      if (b.year != null) 'publishedYear': '${b.year}',
      'genres': genres.toList(),
      if (b.description != null && b.description!.trim().isNotEmpty) 'description': b.description!.trim(),
      'chapters': [
        for (final (i, c) in chapters.indexed)
          {
            'id': i,
            'start': c.start.inMilliseconds / 1000,
            'end': (i + 1 < chapters.length ? chapters[i + 1].start : length).inMilliseconds / 1000,
            'title': c.title,
          },
      ],
    };
  }

  /// Copies [b]'s downloaded files, cover and metadata.json into [root], rescans it and moves the
  /// place across. Returns the book's new folder.
  Future<String> _copyBook(Book b, String root) async {
    final parts = serverParts(b);
    final files = <Track, String>{};
    for (final t in parts) {
      final f = _entries[t.id]?.file;
      if (f == null || !File(f).existsSync()) {
        throw FileSystemException('A file of "${b.title}" isn\'t on this device any more.');
      }
      files[t] = f;
    }
    // A folder of its own: one that's already there (the same book saved before, or another
    // book of the same name) gets " (2)" and so on.
    final base = bookFolderFor(b, root);
    var dir = base;
    for (var i = 2; Directory(dir).existsSync() && Directory(dir).listSync().isNotEmpty; i++) {
      dir = '$base ($i)';
    }
    await Directory(dir).create(recursive: true);
    final copied = <String, String>{}; // server file id → new path
    final digits = parts.length >= 100 ? 3 : 2;
    for (final (i, t) in parts.indexed) {
      final from = files[t]!;
      final name = parts.length == 1
          ? DownloadsModel._name(b.title)
          : '${(i + 1).toString().padLeft(digits, '0')} - ${DownloadsModel._name(t.title)}';
      final to = p.join(dir, '$name${p.extension(from)}');
      await File(from).copy(to);
      copied[t.id] = to;
    }
    // The cover: the server's (downloaded with the book list) or the one you chose.
    final art = parts.map((t) => t.art).whereType<String>().where((a) => a.isNotEmpty && File(a).existsSync()).firstOrNull;
    if (art != null) {
      try {
        final ext = p.extension(art).toLowerCase();
        await File(art).copy(p.join(dir, 'cover${imageExtension(ext) ? ext : '.jpg'}'));
      } catch (_) {}
    }
    await File(p.join(dir, 'metadata.json')).writeAsString(const JsonEncoder.withIndent('  ').convert(bookMetadata(b)), flush: true);

    // The place you'd got to, before the downloads go.
    final place = listening?.progressFor(b);
    // It's yours now: the downloads go, and keeping it offline stops (it would come back).
    if (isKept(KeepKind.book, b.id)) await setKept(KeepKind.book, b.id, b.title, false);
    for (final t in parts) {
      final e = _entries.remove(t.id);
      if (e != null) DownloadsModel._deleteFiles(e.file, e.subtitles);
    }
    notifyListeners();
    await _save();
    await library.scanFolder(root);

    // The place, on the saved book.
    final listen = listening;
    if (place != null && listen != null) {
      Book? mine;
      for (final x in library.books) {
        if (x.parts.any((t) => t.path != null && p.isWithin(dir, t.path!))) {
          mine = x;
          break;
        }
      }
      if (mine != null) {
        final partPath = copied[place.partId];
        final part = partPath == null ? null : mine.parts.where((t) => t.path != null && p.equals(t.path!, partPath)).firstOrNull;
        await listen.record(mine, (part ?? mine.parts.first).id, part == null ? Duration.zero : place.position,
            finished: place.finished);
        if (place.speed != null) await listen.setSpeed(mine, place.speed!);
      }
    }
    return dir;
  }

  /// Whether [ext] (".jpg") is a picture type the cover finder reads.
  static bool imageExtension(String ext) => const {'.jpg', '.jpeg', '.png', '.webp'}.contains(ext);
}
