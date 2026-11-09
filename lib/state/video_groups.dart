// Film collections, step 1 (plan: docs/ai-context/07_FILM_COLLECTIONS_PLAN.md): the list of the
// user's groups of films and what can be done with them. VideoLibraryModel owns one, reads and
// saves it in the shared videos.json ("groups"), and tells it when a film is renamed.
import '../models/video_group.dart';
import '../models/video_item.dart';

/// A film rather than a show: one main video, without an episode number. TV shows (and anything
/// with episodes) stay their own collections and are never put in a group (the user, 8 Nov).
bool isFilm(VideoCollection c) {
  final main = c.main;
  return main.length == 1 && main.single.episode == null && main.single.season == null;
}

class VideoGroups {
  VideoGroups({required this.changed});

  /// Called after every change (VideoLibraryModel rebuilds what's shown and saves).
  final void Function() changed;

  List<VideoGroup> _groups = [];

  /// The time now (tests set their own).
  static int Function() clock = () => DateTime.now().millisecondsSinceEpoch;

  /// Shared collections deleted here that the server hasn't been told about yet (sharing, 9 Nov
  /// 2026): `<server>:<its collection id>` → when.
  Map<String, int> removed = {};

  /// A change made here: it's the newest, so sharing sends it.
  void _touch(VideoGroup g) => g.changedMs = clock();

  /// Every group, A–Z by name.
  List<VideoGroup> get all => [..._groups]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  bool get isEmpty => _groups.isEmpty;

  VideoGroup? byId(String id) => _groups.where((g) => g.id == id).firstOrNull;

  /// The groups a film is in (a film can be in several, like a song in playlists).
  List<VideoGroup> of(String collectionKey) => [for (final g in all) if (g.keys.contains(collectionKey)) g];

  /// Whether a film is in any group (it's then shown inside them, not on its own, on the
  /// Collections tab).
  bool contains(String collectionKey) => _groups.any((g) => g.keys.contains(collectionKey));

  // ---- reading and saving ----

  void load(Object? json, [Object? removedJson]) {
    _groups = [
      if (json is List)
        for (final j in json) ?VideoGroup.fromJson(j),
    ];
    removed = {
      if (removedJson is Map)
        for (final e in removedJson.entries)
          if (e.key is String && e.value is int) e.key as String: e.value as int,
    };
  }

  List<Map<String, dynamic>> toJson() => [for (final g in _groups) g.toJson()];

  // ---- changes ----

  String _newId() {
    var n = DateTime.now().microsecondsSinceEpoch;
    while (byId('g$n') != null) {
      n++;
    }
    return 'g$n';
  }

  /// Makes a group called [name] with [films] in it (shows are left out). Returns it.
  VideoGroup create(String name, [Iterable<VideoCollection> films = const []]) {
    final g = VideoGroup(id: _newId(), name: _clean(name), createdMs: clock());
    _groups.add(g);
    add(g, films, quiet: true);
    changed();
    return g;
  }

  /// Puts [films] in [g] (at the end; ones already in it and shows are skipped). Returns how many
  /// went in.
  int add(VideoGroup g, Iterable<VideoCollection> films, {bool quiet = false}) {
    var n = 0;
    for (final c in films) {
      if (!isFilm(c) || g.keys.contains(c.key)) continue;
      g.keys.add(c.key);
      n++;
    }
    if (n > 0) _touch(g);
    if (n > 0 && !quiet) changed();
    return n;
  }

  /// Takes [films] out of [g] (the films themselves stay).
  void remove(VideoGroup g, Iterable<String> collectionKeys) {
    final before = g.keys.length;
    g.keys.removeWhere(collectionKeys.toSet().contains);
    if (g.keys.length != before) {
      _touch(g);
      changed();
    }
  }

  void rename(VideoGroup g, String name) {
    final n = _clean(name);
    if (n == g.name) return;
    g.name = n;
    _touch(g);
    changed();
  }

  void describe(VideoGroup g, String? description) {
    final d = description?.trim();
    final to = d == null || d.isEmpty ? null : d;
    if (to == g.description) return;
    g.description = to;
    _touch(g);
    changed();
  }

  void setOrder(VideoGroup g, VideoGroupOrder order) {
    if (g.order == order) return;
    g.order = order;
    _touch(g);
    changed();
  }

  /// The user's own order (setting [VideoGroupOrder.own]): [keys] first, in that order, then any
  /// others it holds.
  void reorder(VideoGroup g, List<String> keys) {
    final wanted = <String>{for (final k in keys) if (g.keys.contains(k)) k}.toList();
    final rest = [for (final k in g.keys) if (!wanted.contains(k)) k];
    g.keys
      ..clear()
      ..addAll(wanted)
      ..addAll(rest);
    g.order = VideoGroupOrder.own;
    _touch(g);
    changed();
  }

  /// Deletes the group; its films stay as they are. A shared one is deleted on its servers too,
  /// the next time each is reached.
  void delete(VideoGroup g) {
    if (!_groups.remove(g)) return;
    for (final e in g.links.entries) {
      removed['${e.key}:${e.value}'] = clock();
    }
    changed();
  }

  // ---- sharing (9 Nov 2026): changes from another device, which aren't new changes here ----

  /// A shared collection that came from another device.
  void adopt(VideoGroup g) {
    _groups.add(g);
    changed();
  }

  /// Gone from the server (deleted on another device or in Jellyfin): gone here too.
  void drop(VideoGroup g) {
    if (_groups.remove(g)) changed();
  }

  /// Now shared as [server]'s collection [boxId].
  void link(VideoGroup g, String server, String boxId) {
    if (g.links[server] == boxId) return;
    g.links[server] = boxId;
    changed();
  }

  /// Takes in what another device (or Jellyfin) has for [g]. Returns whether anything changed.
  bool applyShared(VideoGroup g,
      {required String name, String? description, required VideoGroupOrder order, required List<String> keys, required int changedMs}) {
    final k = <String>{...keys}.toList();
    final n = _clean(name);
    final same = g.name == n &&
        g.description == description &&
        g.order == order &&
        g.keys.length == k.length &&
        [for (var i = 0; i < k.length; i++) g.keys[i] == k[i]].every((x) => x);
    g.changedMs = changedMs;
    if (same) return false;
    g
      ..name = n
      ..description = description
      ..order = order;
    g.keys
      ..clear()
      ..addAll(k);
    changed();
    return true;
  }

  /// A new group id.
  String newId() => _newId();

  /// The group linked to [server]'s collection [boxId], if any.
  VideoGroup? linkedTo(String server, String boxId) =>
      _groups.where((g) => g.links[server] == boxId).firstOrNull;

  /// A film was renamed (Edit collection): its place in groups follows. Two films joined into
  /// one leave one entry.
  void renameKey(String from, String to) {
    if (from == to) return;
    for (final g in _groups) {
      final i = g.keys.indexOf(from);
      if (i < 0) continue;
      if (g.keys.contains(to)) {
        g.keys.removeAt(i);
      } else {
        g.keys[i] = to;
      }
    }
  }

  // ---- what's shown ----

  /// [g]'s films that are here now, in its order.
  List<VideoCollection> films(VideoGroup g, VideoCollection? Function(String key) find) {
    final list = [for (final k in g.keys) ?find(k)];
    switch (g.order) {
      case VideoGroupOrder.own:
        break;
      case VideoGroupOrder.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case VideoGroupOrder.year:
        list.sort((a, b) {
          final ya = a.year ?? 99999, yb = b.year ?? 99999;
          return ya != yb ? ya.compareTo(yb) : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    }
    return list;
  }

  static String _clean(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Collection';
    return n.length > 80 ? n.substring(0, 80) : n;
  }
}
