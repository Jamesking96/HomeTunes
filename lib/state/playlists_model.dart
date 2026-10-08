// The user's playlists, their "Liked Songs" and their favourite albums and audiobooks, saved
// together in playlists.json.
//
// Favourite albums and books are stored as the ids of their songs/files rather than album keys
// or book ids, so they follow the same rules as playlists: they survive edits that regroup an
// album, files that move, and backups. An album or book is a favourite when any of its songs is
// in the set.
//
// Playlists store track ids only (not copies of the songs), so edits to a song show up
// everywhere. Because of that, LibraryModel keeps songs that are in a playlist even when their
// file disappears (`referencedIds`), and tells this model when files move (`remapIds`) or when
// the user forgets missing songs (`removeIds`). Every change is saved straight away.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/storage.dart';
import 'song_id_follower.dart';

/// User playlists plus the special "Liked Songs" list.
class PlaylistsModel extends ChangeNotifier implements SongIdFollower {
  final Storage storage;
  PlaylistsModel(this.storage);

  /// The user's playlists, in the order they were made.
  List<Playlist> playlists = [];

  /// Liked track ids, most recently liked first.
  List<String> liked = [];
  // The same ids as a set, so "is this song liked?" is a quick look-up while drawing lists.
  Set<String> _likedSet = {};

  // Song/file ids of favourite albums and favourite audiobooks.
  Set<String> _favAlbums = {};
  Set<String> _favBooks = {};

  /// Names of favourite audiobook series (0.1.75).
  Set<String> _favSeries = {};

  /// Reads playlists.json (at start-up and after a backup is restored).
  Future<void> load() async {
    playlists = [];
    liked = [];
    _favAlbums = {};
    _favBooks = {};
    _favSeries = {};
    // HomeTunes: read piece by piece, so one damaged playlist (or a wrong type anywhere) skips
    // just that piece instead of stopping the app from starting. If anything was skipped, a
    // copy of the file is kept before the next save replaces it.
    final j = await storage.read('playlists.json');
    var damaged = j != null && j is! Map;
    List<String> ids(Object? v) {
      if (v == null) return [];
      if (v is! List) {
        damaged = true;
        return [];
      }
      final out = [for (final x in v) if (x is String) x];
      if (out.length != v.length) damaged = true;
      return out;
    }

    if (j is Map) {
      final lists = j['playlists'];
      if (lists != null && lists is! List) damaged = true;
      for (final p in lists is List ? lists : const []) {
        try {
          playlists.add(Playlist.fromJson(p as Map<String, dynamic>));
        } catch (_) {
          damaged = true;
        }
      }
      liked = ids(j['liked']);
      _favAlbums = ids(j['favouriteAlbums']).toSet();
      _favBooks = ids(j['favouriteBooks']).toSet();
      _favSeries = ids(j['favouriteSeries']).toSet();
    }
    if (damaged) await storage.keepCopy('playlists.json');
    _likedSet = liked.toSet();
    notifyListeners();
  }

  Future<void> _save() => storage.write('playlists.json', {
        'playlists': [for (final p in playlists) p.toJson()],
        'liked': liked,
        'favouriteAlbums': _favAlbums.toList(),
        'favouriteBooks': _favBooks.toList(),
        'favouriteSeries': _favSeries.toList(),
      });

  /// Redraws listeners and saves. Called after every change. The save isn't awaited: the
  /// storage service writes files one at a time, so saves can't overlap.
  void _changed() {
    notifyListeners();
    _save();
  }

  bool isLiked(Track t) => _likedSet.contains(t.id);

  /// Likes the song (putting it at the top of Liked Songs) or unlikes it.
  void toggleLike(Track t) {
    if (_likedSet.remove(t.id)) {
      liked.remove(t.id);
    } else {
      _likedSet.add(t.id);
      liked.insert(0, t.id);
    }
    _changed();
  }

  // ---- favourite albums and books ----

  bool isFavouriteAlbum(Album a) => a.tracks.any((t) => _favAlbums.contains(t.id));
  bool isFavouriteBook(Book b) => b.parts.any((t) => _favBooks.contains(t.id));

  /// Makes [albums] favourites, or not.
  void setFavouriteAlbums(Iterable<Album> albums, bool favourite) {
    for (final a in albums) {
      for (final t in a.tracks) {
        favourite ? _favAlbums.add(t.id) : _favAlbums.remove(t.id);
      }
    }
    _changed();
  }

  /// Makes [books] favourites, or not.
  void setFavouriteBooks(Iterable<Book> books, bool favourite) {
    for (final b in books) {
      for (final t in b.parts) {
        favourite ? _favBooks.add(t.id) : _favBooks.remove(t.id);
      }
    }
    _changed();
  }

  // ---- favourite audiobook series (0.1.75), kept by series name ----

  bool isFavouriteSeries(String name) => _favSeries.contains(name);

  /// The favourite series' names.
  Set<String> get favouriteSeries => {..._favSeries};

  /// Makes the series [names] favourites, or not.
  void setFavouriteSeries(Iterable<String> names, bool favourite) {
    for (final n in names) {
      favourite ? _favSeries.add(n) : _favSeries.remove(n);
    }
    _changed();
  }

  /// A series was renamed (Edit series): its favourite follows it.
  void renameFavouriteSeries(String from, String to) {
    if (from == to || !_favSeries.remove(from)) return;
    _favSeries.add(to);
    _changed();
  }

  /// Makes a new empty playlist. Its id is the current time in microseconds, which is unique
  /// enough for playlists made by hand.
  Playlist create(String name) {
    final p = Playlist(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name.trim());
    playlists.add(p);
    _changed();
    return p;
  }

  void rename(Playlist p, String name) {
    p.name = name.trim();
    _changed();
  }

  void delete(Playlist p) {
    playlists.remove(p);
    _changed();
    _tidyPictures();
  }

  // ---- playlist icons (0.1.67) ----

  /// Where pictures chosen for playlists are kept: inside art/custom (so backups carry them, as
  /// they can't be made again) but in their own folder, which the music covers' tidy-up
  /// (LibraryModel) doesn't look into.
  String get pictureDir => p.join(storage.artDir, 'custom', 'playlists');

  /// The picture file of [pl], or null when it has none (or the file has gone).
  String? pictureFile(Playlist pl) {
    final name = pl.iconImage;
    if (name == null) return null;
    final path = p.join(pictureDir, name);
    return File(path).existsSync() ? path : null;
  }

  /// Gives [pl] a built-in icon ([name], see widgets/playlist_art.dart) on [colour] (null = the
  /// accent), in place of any picture.
  void setIcon(Playlist pl, String name, int? colour) {
    pl.iconName = name;
    pl.iconColour = colour;
    pl.iconImage = null;
    _changed();
    _tidyPictures();
  }

  /// Gives [pl] a picture: a copy of [source] goes into [pictureDir] (named by its contents, so
  /// the same picture is kept once), so moving or deleting the original doesn't matter.
  Future<void> setPicture(Playlist pl, String source) async {
    final bytes = await File(source).readAsBytes();
    var ext = p.extension(source).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext)) ext = '.img';
    final dir = Directory(pictureDir);
    await dir.create(recursive: true);
    final name = '${md5.convert(bytes)}$ext';
    final dest = File(p.join(dir.path, name));
    if (!await dest.exists()) await dest.writeAsBytes(bytes, flush: true);
    pl.iconImage = name;
    pl.iconName = null;
    pl.iconColour = null;
    // Show the new picture even if an old one with the same path was cached.
    PaintingBinding.instance.imageCache.clear();
    _changed();
    await _tidyPictures();
  }

  /// Back to the first song's cover.
  void clearIcon(Playlist pl) {
    pl.iconName = null;
    pl.iconColour = null;
    pl.iconImage = null;
    _changed();
    _tidyPictures();
  }

  /// Deletes playlist pictures no playlist uses any more.
  Future<void> _tidyPictures() async {
    final dir = Directory(pictureDir);
    if (!await dir.exists()) return;
    final used = {for (final pl in playlists) ?pl.iconImage};
    await for (final f in dir.list()) {
      if (f is File && !used.contains(p.basename(f.path))) {
        // In use right now (e.g. being drawn on Windows): left for next time.
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Adds tracks, skipping ones already in the playlist. Returns how many were added.
  int addTracks(Playlist p, Iterable<Track> tracks) {
    var added = 0;
    for (final t in tracks) {
      if (!p.trackIds.contains(t.id)) {
        p.trackIds.add(t.id);
        added++;
      }
    }
    if (added > 0) _changed();
    return added;
  }

  /// Removes the song at position [index] in the playlist.
  void removeAt(Playlist p, int index) {
    p.trackIds.removeAt(index);
    _changed();
  }

  /// Replaces the order of a playlist's songs.
  void setOrder(Playlist p, List<String> ids) {
    p.trackIds
      ..clear()
      ..addAll(ids);
    _changed();
  }

  /// Every track id used by a playlist, Liked Songs or a favourite album or book.
  @override
  Set<String> get referencedIds =>
      {..._likedSet, ..._favAlbums, ..._favBooks, for (final p in playlists) ...p.trackIds};

  /// Songs that moved (old id → new id) keep their places in playlists and likes.
  @override
  void remapIds(Map<String, String> moved) {
    if (moved.isEmpty) return;
    var changed = false;
    // Swaps old ids for new ones, keeping the order. If a moved song's new id is already in the
    // list (say the file was copied rather than moved), the duplicate is dropped.
    List<String> remap(List<String> ids) {
      final out = <String>[];
      final seen = <String>{};
      for (final id in ids) {
        final n = moved[id] ?? id;
        if (n != id) changed = true;
        if (seen.add(n)) out.add(n);
      }
      return out;
    }

    for (final p in playlists) {
      final ids = remap(p.trackIds);
      p.trackIds
        ..clear()
        ..addAll(ids);
    }
    liked = remap(liked);
    _likedSet = liked.toSet();
    _favAlbums = remap(_favAlbums.toList()).toSet();
    _favBooks = remap(_favBooks.toList()).toSet();
    if (changed) _changed();
  }

  /// Removes songs from every playlist and from Liked Songs.
  @override
  void removeIds(Set<String> ids) {
    if (ids.isEmpty) return;
    for (final p in playlists) {
      p.trackIds.removeWhere(ids.contains);
    }
    liked.removeWhere(ids.contains);
    _likedSet = liked.toSet();
    _favAlbums.removeAll(ids);
    _favBooks.removeAll(ids);
    _changed();
  }

  /// Finds a playlist by its id, or null if it has been deleted.
  Playlist? byId(String id) {
    for (final p in playlists) {
      if (p.id == id) return p;
    }
    return null;
  }
}
