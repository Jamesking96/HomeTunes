// Recently played music (0.1.45), for Home's "Jump back in" row: the albums, playlists, Liked
// Songs and artists you played from, newest first, at most [PlayHistory.max], saved in
// history.json (and in backups).
//
// It follows the player: each time a new song starts playing, the place it was played from is
// worked out from the queue's label ("Playlist · Road trip", "Artist · Muse", "Liked Songs";
// anything else, such as an album, All songs or a search, counts as the song's album) and moved
// to the front. Audiobooks aren't recorded here (ListeningModel keeps their places).
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/track.dart';
import '../services/storage.dart';
import 'player_model.dart';

enum PlayedKind { album, playlist, liked, artist }

/// One place music was played from.
class PlayedItem {
  final PlayedKind kind;

  /// The album key, the playlist's name, the artist's name, or '' for Liked Songs.
  final String key;

  /// What to show: the album's or playlist's title, or the artist's name.
  final String title;

  /// When it was last played (ms since 1970).
  final int atMs;

  const PlayedItem(this.kind, this.key, this.title, this.atMs);

  bool sameAs(PlayedItem o) => o.kind == kind && o.key == key;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'key': key, 'title': title, 'at': atMs};

  static PlayedItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = PlayedKind.values.asNameMap()[j['kind']];
    final key = j['key'], title = j['title'], at = j['at'];
    if (kind == null || key is! String || title is! String || at is! int) return null;
    return PlayedItem(kind, key, title, at);
  }
}

/// Where [t] was played from, given the queue's [label]. Null for an audiobook.
PlayedItem? playedFrom(String? label, Track t, int atMs) {
  const sep = ' · ';
  final l = label ?? '';
  if (l.startsWith('Book$sep')) return null;
  if (l.startsWith('Playlist$sep')) {
    final name = l.substring('Playlist$sep'.length);
    return PlayedItem(PlayedKind.playlist, name, name, atMs);
  }
  if (l.startsWith('Artist$sep')) {
    final name = l.substring('Artist$sep'.length);
    return PlayedItem(PlayedKind.artist, name, name, atMs);
  }
  if (l == 'Liked Songs') return PlayedItem(PlayedKind.liked, '', 'Liked Songs', atMs);
  return PlayedItem(PlayedKind.album, t.albumKey, t.album, atMs);
}

class PlayHistory extends ChangeNotifier {
  PlayHistory(this.storage);

  final Storage storage;
  static const file = 'history.json';
  static const max = 50;

  /// For tests: the clock.
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  List<PlayedItem> _items = [];

  /// Newest first.
  List<PlayedItem> get items => List.unmodifiable(_items);

  PlayerModel? _player;
  String? _lastTrackId;
  Timer? _saveTimer;

  Future<void> load() async {
    final j = await storage.read(file);
    final list = j is Map ? j['played'] : null;
    _items = [for (final x in (list is List ? list : const [])) ?PlayedItem.fromJson(x)];
    notifyListeners();
  }

  /// Follows [player]: each new song that starts playing is recorded.
  void attach(PlayerModel player) {
    _player?.removeListener(_onPlayer);
    _player = player..addListener(_onPlayer);
  }

  void _onPlayer() {
    final p = _player;
    final t = p?.current;
    if (p == null || t == null || !p.playing || p.inBook) return;
    if (t.id == _lastTrackId) return;
    _lastTrackId = t.id;
    final item = playedFrom(p.queue.contextLabel, t, now());
    if (item != null) record(item);
  }

  /// Puts [item] first (once).
  void record(PlayedItem item) {
    _items = [
      item,
      for (final x in _items)
        if (!x.sameAs(item)) x,
    ];
    if (_items.length > max) _items = _items.sublist(0, max);
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), save);
  }

  /// Forgets everything played (Settings › Playback).
  Future<void> clear() async {
    _items = [];
    notifyListeners();
    await save();
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    await storage.write(file, {
      'played': [for (final x in _items) x.toJson()],
    });
  }

  @override
  void dispose() {
    _player?.removeListener(_onPlayer);
    _saveTimer?.cancel();
    super.dispose();
  }
}
