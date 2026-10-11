// Part of LibraryModel (refactor phase 10, 9 Oct 2026: library_model.dart was over 1,500 lines).
// Artist and series pictures, series descriptions, Edit series, and the pictures the user chose (copied
// into the art folder, tidied when no longer used).
part of '../library_model.dart';

extension LibraryPictures on LibraryModel {
  /// The track whose cover an artist shows: the album chosen with "Use an album cover", else
  /// their first album's (0.1.53).
  Track? artistAlbumArt(Artist a) {
    final pick = artistPictures[a.name];
    if (pick != null && pick.startsWith(LibraryModel.artistAlbumPrefix)) {
      final key = pick.substring(LibraryModel.artistAlbumPrefix.length);
      final album = a.albums.where((x) => x.key == key).firstOrNull;
      if (album != null) return album.artTrack;
    }
    return a.albums.isEmpty ? null : a.albums.first.artTrack;
  }

  /// The artist's own picture file (Choose an image file…), if one was chosen and it's still
  /// in HomeTunes' art folder; else null (0.1.53).
  String? artistPictureFile(Artist a) {
    final pick = artistPictures[a.name];
    if (pick == null || pick.startsWith(LibraryModel.artistAlbumPrefix)) return null;
    return isInsideAny(pick, [storage.artDir]) ? pick : null;
  }

  /// Where the picture to draw for an artist comes from: their own file, the chosen album cover,
  /// or the first album's cover (the screens use LibraryImages.artistImage).
  PictureSource? artistSource(Artist a, {int size = 512}) {
    final file = artistPictureFile(a);
    if (file != null) return (file: file, url: null);
    return coverSource(artistAlbumArt(a), size: size);
  }

  bool hasArtistPicture(Artist a) => artistPictures.containsKey(a.name);

  /// Sets an artist's picture (0.1.53): [file] (already copied in with [importCover] /
  /// [importCoverBytes]), or [album] (one of their albums), or neither to go back to automatic.
  Future<void> setArtistPicture(Artist a, {String? file, Album? album}) async {
    if (file != null) {
      artistPictures[a.name] = file;
    } else if (album != null) {
      artistPictures[a.name] = '${LibraryModel.artistAlbumPrefix}${album.key}';
    } else {
      artistPictures.remove(a.name);
    }
    picturesChanged();
    _changed();
    await _saveSettings();
    await _removeUnusedCustomArt();
  }

  // ---- audiobook series (0.1.76, Edit series) ----

  /// The series' own description, if one was written.
  String? seriesDescription(String name) => seriesInfo[name]?['description'];

  /// Whether a picture was chosen for the series.
  bool hasSeriesPicture(String name) => seriesInfo[name]?['picture'] != null;

  /// The series' own picture file (Choose an image file…), if it's still in HomeTunes' art
  /// folder; else null.
  String? seriesPictureFile(String name) {
    final pick = seriesInfo[name]?['picture'];
    if (pick == null || pick.startsWith(LibraryModel.seriesBookPrefix)) return null;
    return isInsideAny(pick, [storage.artDir]) ? pick : null;
  }

  /// The book whose cover the series shows: the one picked, else its first book with a cover.
  Book seriesCoverBook(BookSeries s) {
    final pick = seriesInfo[s.name]?['picture'];
    if (pick != null && pick.startsWith(LibraryModel.seriesBookPrefix)) {
      final id = pick.substring(LibraryModel.seriesBookPrefix.length);
      final b = s.books.where((b) => b.id == id).firstOrNull;
      if (b != null) return b;
    }
    return s.coverBook;
  }

  void _setSeriesField(String name, String key, String? value) {
    final m = {...?seriesInfo[name]};
    if (value == null || value.isEmpty) {
      m.remove(key);
    } else {
      m[key] = value;
    }
    if (m.isEmpty) {
      seriesInfo.remove(name);
    } else {
      seriesInfo[name] = m;
    }
  }

  /// Sets a series' picture: [file] (already copied in with [importCover]), or [book] (one of
  /// its books' covers), or neither to go back to the first book's cover.
  Future<void> setSeriesPicture(String name, {String? file, Book? book}) async {
    _setSeriesField(name, 'picture', file ?? (book == null ? null : '${LibraryModel.seriesBookPrefix}${book.id}'));
    picturesChanged();
    _changed();
    await _saveSettings();
    await _removeUnusedCustomArt();
  }

  /// Sets (or with null or "", removes) a series' description.
  Future<void> setSeriesDescription(String name, String? text) async {
    _setSeriesField(name, 'description', text?.trim());
    _changed();
    await _saveSettings();
  }

  /// Changes a whole series at once, saved as edits on its books' files (the files themselves
  /// aren't changed, like Edit book / Edit collection):
  ///  * [name]: renames the series on every book; its description, picture and sidebar link
  ///    follow (its favourite is PlaylistsModel.renameFavouriteSeries);
  ///  * [author]: the author of every book;
  ///  * [order]: the books in a new order, numbered 1, 2, 3…;
  ///  * [add]: books to put in the series, numbered after the last one;
  ///  * [remove]: books to take out (no series and no number).
  Future<void> editSeries(
    BookSeries s, {
    String? name,
    String? author,
    List<Book>? order,
    List<Book> add = const [],
    List<Book> remove = const [],
  }) async {
    final to = (name == null || name.trim().isEmpty) ? s.name : name.trim();
    final who = (author == null || author.trim().isEmpty) ? null : author.trim();
    final out = {for (final b in remove) b.id};
    final kept = [for (final b in order ?? s.books) if (!out.contains(b.id)) b];
    final keptIds = {for (final b in kept) b.id};
    final adding = [for (final b in add) if (!out.contains(b.id) && keptIds.add(b.id)) b];

    // 1. Each book's new series, number and author (only what changes).
    final changes = <String, TrackEdit>{};
    void change(Book b, {double? number}) {
      final e = TrackEdit(
        series: b.series != to ? to : null,
        seriesIndex: number != null && number != b.seriesIndex ? number : null,
        artist: who != null && who != b.author ? who : null,
        albumArtist: who != null && who != b.author ? who : null,
      );
      if (e.isEmpty) return;
      for (final t in b.parts) {
        changes[t.id] = e;
      }
    }

    for (final (i, b) in kept.indexed) {
      change(b, number: order == null ? null : (i + 1).toDouble());
    }
    var last = order != null
        ? kept.length.toDouble()
        : kept.fold<double>(0, (m, b) => (b.seriesIndex ?? 0) > m ? b.seriesIndex! : m);
    for (final b in adding) {
      change(b, number: ++last);
    }
    for (final b in remove) {
      for (final t in b.parts) {
        changes[t.id] = const TrackEdit(series: '', cleared: {'seriesIndex'});
      }
    }

    // 2. A new name: the series' details and its sidebar link come along.
    if (to != s.name) {
      final info = seriesInfo.remove(s.name);
      if (info != null) seriesInfo[to] = {...?seriesInfo[to], ...info};
      final had = isQuickLink(QuickLinkKind.series, s.name);
      final layout = settings.layout;
      layout.quickLinks = [
        for (final l in layout.quickLinks)
          if (!l.sameAs(QuickLinkKind.series, s.name) && !(had && l.sameAs(QuickLinkKind.series, to))) l
          else if (l.sameAs(QuickLinkKind.series, s.name)) QuickLink(QuickLinkKind.series, to, to)
      ];
      // The sidebar watches the layout settings (refactor phase 9).
      layout.changed();
      await _saveSettings();
    }
    if (changes.isNotEmpty) {
      await editTracks(changes);
    } else {
      _changed();
    }
  }

  /// Copies an image the user picked into the app's data folder (so moving or
  /// deleting the original doesn't break the cover) and returns the copy's path.
  Future<String> importCover(String sourcePath) async =>
      importCoverBytes(await File(sourcePath).readAsBytes(), p.extension(sourcePath).toLowerCase());

  /// Saves cover image bytes (e.g. downloaded from online) and returns the file path.
  Future<String> importCoverBytes(List<int> bytes, [String ext = '']) async {
    // No file extension given: work it out from the image data itself.
    if (ext.isEmpty) {
      final mime = imageMimeType(bytes);
      ext = mime == 'image/png' ? '.png' : (mime == 'image/jpeg' ? '.jpg' : '.img');
    }
    // Named after a fingerprint (md5) of its contents, so the same picture is stored once. Not
    // used by any edit yet (the editor saves it later), so it's kept from the tidy-up for a while.
    final path = await _customArt.store(bytes, ext);
    // Make sure images show the new picture even if an old one was cached.
    picturesChanged();
    return path;
  }

  // Covers imported but not yet used by any edit are kept from the tidy-up for a while
  // (HomeTunes 0.1.16; CustomArtStore.protectNew).
  /// Deletes custom covers that no edit points at any more.
  Future<void> _removeUnusedCustomArt() => _customArt.removeUnused({
        for (final e in _edits.values) if (e.art != null) e.art!,
        // Artists' own pictures live here too (0.1.53), and series' (0.1.76).
        for (final v in artistPictures.values) if (!v.startsWith(LibraryModel.artistAlbumPrefix)) v,
        for (final i in seriesInfo.values)
          if (i['picture'] case final v? when !v.startsWith(LibraryModel.seriesBookPrefix)) v,
      });
  // ---- backup & restore ----
}
