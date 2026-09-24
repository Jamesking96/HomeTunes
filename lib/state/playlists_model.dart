import 'package:flutter/foundation.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/storage.dart';

/// User playlists plus the special "Liked Songs" list.
class PlaylistsModel extends ChangeNotifier {
  final Storage storage;
  PlaylistsModel(this.storage);

  List<Playlist> playlists = [];

  /// Liked track ids, most recently liked first.
  List<String> liked = [];
  Set<String> _likedSet = {};

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

  void _changed() {
    notifyListeners();
    _save();
  }

  bool isLiked(Track t) => _likedSet.contains(t.id);

  void toggleLike(Track t) {
    if (_likedSet.remove(t.id)) {
      liked.remove(t.id);
    } else {
      _likedSet.add(t.id);
      liked.insert(0, t.id);
    }
    _changed();
  }

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

  Playlist? byId(String id) {
    for (final p in playlists) {
      if (p.id == id) return p;
    }
    return null;
  }
}
