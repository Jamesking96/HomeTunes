// The user's playlists and their "Liked Songs", saved together in playlists.json.
//
// Playlists store track ids only (not copies of the songs), so edits to a song show up
// everywhere. Because of that, LibraryModel keeps songs that are in a playlist even when their
// file disappears (`referencedIds`), and tells this model when files move (`remapIds`) or when
// the user forgets missing songs (`removeIds`). Every change is saved straight away.
import 'package:flutter/foundation.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/storage.dart';

/// User playlists plus the special "Liked Songs" list.
class PlaylistsModel extends ChangeNotifier {
  final Storage storage;
  PlaylistsModel(this.storage);

  /// The user's playlists, in the order they were made.
  List<Playlist> playlists = [];

  /// Liked track ids, most recently liked first.
  List<String> liked = [];
  // The same ids as a set, so "is this song liked?" is a quick look-up while drawing lists.
  Set<String> _likedSet = {};

  /// Reads playlists.json (at start-up and after a backup is restored).
  Future<void> load() async {
    playlists = [];
    liked = [];
    final j = await storage.read('playlists.json') as Map<String, dynamic>?;
    if (j != null) {
      playlists = [
        for (final p in (j['playlists'] as List? ?? const [])) Playlist.fromJson(p as Map<String, dynamic>),
      ];
      liked = (j['liked'] as List? ?? const []).cast<String>().toList();
    }
    _likedSet = liked.toSet();
    notifyListeners();
  }

  Future<void> _save() => storage.write('playlists.json', {
        'playlists': [for (final p in playlists) p.toJson()],
        'liked': liked,
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

  /// Every track id used by a playlist or Liked Songs.
  Set<String> get referencedIds => {..._likedSet, for (final p in playlists) ...p.trackIds};

  /// Songs that moved (old id → new id) keep their places in playlists and likes.
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
    if (changed) _changed();
  }

  /// Removes songs from every playlist and from Liked Songs.
  void removeIds(Set<String> ids) {
    if (ids.isEmpty) return;
    for (final p in playlists) {
      p.trackIds.removeWhere(ids.contains);
    }
    liked.removeWhere(ids.contains);
    _likedSet = liked.toSet();
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
