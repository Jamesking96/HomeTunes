// Sharing film collections through Jellyfin (9 Nov 2026; plan: docs/ai-context/
// 09_COLLECTION_SHARING_PLAN.md). The user: "Is there a way we can share collections made on one
// device to others?"; the plan's choices: automatic, changes both ways (the newest wins), and
// deleting is shared too.
//
// Each collection that has films on a Jellyfin server is a collection (box set) there too, so
// every device, and Jellyfin's own apps, see the same films in it. Jellyfin only lets
// administrators rename collections or change their description, but any user may keep display
// settings, so HomeTunes keeps its own note there ("hometunes-collections"): for each shared
// collection its name, description, order and when it last changed, plus the ones deleted. A
// collection in that note comes onto every device by itself; any other Jellyfin collection is
// still only a suggestion (the user, 8 Nov: nothing made without a yes).
import 'dart:convert';

import '../models/video_group.dart';
import '../models/video_item.dart';
import '../services/jellyfin_client.dart';
import 'remote_videos.dart';
import 'video_groups.dart';

/// What sharing needs from a server (JellyfinClient on a real one; tests use their own).
abstract class CollectionServer {
  Future<({bool admin, bool manage})> rights();
  Future<List<JellyfinCollection>> collections();
  Future<String> create(String name, List<String> items);
  Future<void> add(String id, List<String> items);
  Future<void> remove(String id, List<String> items);
  Future<void> update(String id, {required String name, String? overview});
  Future<void> delete(String id);

  /// HomeTunes' note, as text (null: none yet).
  Future<String?> readNote();
  Future<void> writeNote(String text);
}

/// A signed-in Jellyfin server.
class JellyfinCollectionServer implements CollectionServer {
  JellyfinCollectionServer(this.c);
  final JellyfinClient c;
  static const noteName = 'hometunes-collections';
  Map<String, dynamic>? _record;

  @override
  Future<({bool admin, bool manage})> rights() => c.collectionRights();
  @override
  Future<List<JellyfinCollection>> collections() => c.collections();
  @override
  Future<String> create(String name, List<String> items) => c.createCollection(name, items);
  @override
  Future<void> add(String id, List<String> items) => c.addToCollection(id, items);
  @override
  Future<void> remove(String id, List<String> items) => c.removeFromCollection(id, items);
  @override
  Future<void> update(String id, {required String name, String? overview}) => c.updateCollection(id, name: name, overview: overview);
  @override
  Future<void> delete(String id) => c.deleteItem(id);

  @override
  Future<String?> readNote() async {
    final r = _record = await c.readNote(noteName);
    final prefs = r['CustomPrefs'];
    return prefs is Map && prefs['collections'] is String ? prefs['collections'] as String : null;
  }

  @override
  Future<void> writeNote(String text) async {
    final r = _record ?? await c.readNote(noteName);
    final prefs = r['CustomPrefs'] is Map ? Map<String, dynamic>.from(r['CustomPrefs'] as Map) : <String, dynamic>{};
    prefs['collections'] = text;
    await c.writeNote(noteName, {...r, 'CustomPrefs': prefs});
  }
}

/// One shared collection in the note.
class SharedEntry {
  SharedEntry({required this.name, this.description, this.order = VideoGroupOrder.year, this.own = const [], required this.changedMs, required this.seen});

  String name;
  String? description;
  VideoGroupOrder order;

  /// Its films' ids in the user's own order.
  List<String> own;
  int changedMs;

  /// The collection's name on the server when HomeTunes last looked: different now means it was
  /// renamed in Jellyfin.
  String seen;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (order != VideoGroupOrder.year) 'order': order.name,
        if (own.isNotEmpty) 'own': own,
        'changedMs': changedMs,
        'seen': seen,
      };

  static SharedEntry? fromJson(Object? j) {
    if (j is! Map || j['name'] is! String || j['changedMs'] is! int) return null;
    return SharedEntry(
      name: j['name'] as String,
      description: j['description'] is String ? j['description'] as String : null,
      order: VideoGroupOrder.values.where((o) => o.name == j['order']).firstOrNull ?? VideoGroupOrder.year,
      own: [if (j['own'] is List) for (final i in j['own'] as List) if (i is String) i],
      changedMs: j['changedMs'] as int,
      seen: j['seen'] is String ? j['seen'] as String : j['name'] as String,
    );
  }
}

/// The note: the shared collections by their id on the server, and the ones deleted (id → when).
class SharedNote {
  final Map<String, SharedEntry> sets = {};
  final Map<String, int> gone = {};

  static SharedNote parse(String? text) {
    final n = SharedNote();
    if (text == null || text.isEmpty) return n;
    try {
      final j = jsonDecode(text);
      if (j is! Map) return n;
      if (j['sets'] is Map) {
        for (final e in (j['sets'] as Map).entries) {
          if (e.key is String) {
            final s = SharedEntry.fromJson(e.value);
            if (s != null) n.sets[e.key as String] = s;
          }
        }
      }
      if (j['gone'] is Map) {
        for (final e in (j['gone'] as Map).entries) {
          if (e.key is String && e.value is int) n.gone[e.key as String] = e.value as int;
        }
      }
    } catch (_) {
      // Unreadable: started again (the collections themselves are still on the server).
    }
    return n;
  }

  String encode() => jsonEncode({
        'v': 1,
        'sets': {for (final e in sets.entries) e.key: e.value.toJson()},
        if (gone.isNotEmpty) 'gone': gone,
      });
}

/// How sharing with one server went.
class ShareOutcome {
  ShareOutcome({this.shared = 0, this.problem});

  /// How many collections are shared through it.
  int shared;

  /// Why something couldn't be shared (in plain words), or null.
  String? problem;
}

/// Deleted collections are remembered this long (so a device that's been off for a while still
/// hears about them).
const goneKept = Duration(days: 120);

/// Shares [groups] with one server ([serverKey], called [serverName]): sends what changed here,
/// takes in what changed elsewhere, deletes what was deleted. [filmsByItem]: the films this device
/// has from that server, by their id there. [find]: a film by its key.
Future<ShareOutcome> shareCollections({
  required String serverKey,
  required String serverName,
  required String userName,
  required CollectionServer server,
  required VideoGroups groups,
  required Map<String, VideoCollection> filmsByItem,
  required VideoCollection? Function(String key) find,
}) async {
  final out = ShareOutcome();
  final now = VideoGroups.clock();
  final rights = await server.rights();
  final boxes = {for (final c in await server.collections()) c.id: c};
  final note = SharedNote.parse(await server.readNote());
  var noteChanged = false;
  String cant() => 'Collections can\'t be shared through $serverName: the Jellyfin user "$userName" isn\'t allowed to change '
      'collections. In Jellyfin: Dashboard › Users › $userName, turn on "Allow this user to manage collections".';

  /// [g]'s films that are on this server, as their ids there, in its own order.
  List<String> itemsOf(VideoGroup g) => [
        for (final k in g.keys)
          if (find(k) case final c? when isFilm(c) && remoteServerOf(c.main.single.id) == serverKey)
            ?remoteItemOf(c.main.single.id),
      ];

  SharedEntry entryFor(VideoGroup g, String seen) => SharedEntry(
      name: g.name, description: g.description, order: g.order, own: itemsOf(g), changedMs: g.changedMs, seen: seen);

  // 1. Deleted here: deleted there.
  for (final e in groups.removed.entries.toList()) {
    if (!e.key.startsWith('$serverKey:')) continue;
    final id = e.key.substring(serverKey.length + 1);
    if (boxes.containsKey(id)) {
      try {
        await server.delete(id);
      } on JellyfinException {
        // Not allowed to delete it: still gone from every HomeTunes (the note says so).
      }
    }
    note.sets.remove(id);
    note.gone[id] = e.value;
    groups.removed.remove(e.key);
    noteChanged = true;
  }

  /// Sends [g] (newer here), or takes in the server's (newer there).
  Future<void> syncLinked(VideoGroup g, String id) async {
    final box = boxes[id]!;
    final entry = note.sets[id];
    if (entry == null || g.changedMs > entry.changedMs) {
      // Newer here: the server's films follow. Films this device doesn't have are left alone.
      final want = itemsOf(g).toSet(), have = box.items.toSet();
      final add = [for (final i in want) if (!have.contains(i)) i];
      final take = [for (final i in have) if (!want.contains(i) && filmsByItem.containsKey(i)) i];
      if (add.isNotEmpty || take.isNotEmpty) {
        if (!rights.manage) {
          out.problem = cant();
        } else {
          if (add.isNotEmpty) await server.add(id, add);
          if (take.isNotEmpty) await server.remove(id, take);
        }
      }
      var seen = box.name;
      if (rights.admin && (box.name != g.name || (box.overview ?? '') != (g.description ?? ''))) {
        await server.update(id, name: g.name, overview: g.description);
        seen = g.name;
      }
      note.sets[id] = entryFor(g, seen);
      noteChanged = true;
      return;
    }
    // Newer elsewhere (or changed in Jellyfin): this one follows.
    final renamed = box.name != entry.seen;
    if (renamed) {
      entry
        ..name = box.name
        ..seen = box.name
        ..changedMs = now;
      noteChanged = true;
    }
    final mine = <String>[
      for (final i in entry.own) if (box.items.contains(i)) ?filmsByItem[i]?.key,
      for (final i in box.items) if (!entry.own.contains(i)) ?filmsByItem[i]?.key,
    ];
    // Films not from this server (this device's own, another server's) stay.
    final others = [
      for (final k in g.keys)
        if (find(k) case final c when c == null || remoteServerOf(c.main.single.id) != serverKey) k,
    ];
    groups.applyShared(g,
        name: entry.name, description: entry.description, order: entry.order, keys: [...mine, ...others], changedMs: entry.changedMs);
  }

  // 2. Shared ones: gone elsewhere → gone here; else the newest wins.
  for (final g in groups.all) {
    final id = g.links[serverKey];
    if (id == null) continue;
    final gone = note.gone[id];
    if (!boxes.containsKey(id) || (gone != null && gone >= g.changedMs)) {
      groups.drop(g);
      continue;
    }
    await syncLinked(g, id);
  }

  // 3. Not shared yet but with films on this server: shared now (joined to one of the same name
  // that another device made, or made on the server).
  for (final g in groups.all) {
    if (g.links.containsKey(serverKey)) continue;
    final items = itemsOf(g);
    if (items.isEmpty) continue;
    final want = g.name.trim().toLowerCase();
    final sameId = note.sets.entries
            .where((e) => e.value.name.toLowerCase() == want && boxes.containsKey(e.key) && groups.linkedTo(serverKey, e.key) == null)
            .firstOrNull
            ?.key ??
        // Jellyfin's own collection of that name ("Star Wars" or "Star Wars Collection"), not
        // one HomeTunes shares yet (9 Nov 2026): joined, not made a second time.
        boxes.values
            .where((b) {
              final n = b.name.trim().toLowerCase();
              return (n == want || n == '$want collection' || '$n collection' == want) &&
                  !note.sets.containsKey(b.id) &&
                  groups.linkedTo(serverKey, b.id) == null;
            })
            .firstOrNull
            ?.id;
    if (sameId != null) {
      // Both sides' films, then shared as one.
      groups.link(g, serverKey, sameId);
      groups.add(g, [for (final i in boxes[sameId]!.items) ?filmsByItem[i]]);
      g.changedMs = VideoGroups.clock();
      await syncLinked(g, sameId);
      continue;
    }
    if (!rights.manage) {
      out.problem = cant();
      continue;
    }
    final id = await server.create(g.name, items);
    boxes[id] = JellyfinCollection(id: id, name: g.name, items: items);
    groups.link(g, serverKey, id);
    if (rights.admin && g.description != null) await server.update(id, name: g.name, overview: g.description);
    note.sets[id] = entryFor(g, g.name);
    noteChanged = true;
  }

  // 4. Shared from another device and not here yet: comes in (once any of its films is here).
  for (final e in note.sets.entries.toList()) {
    if (groups.linkedTo(serverKey, e.key) != null) continue;
    final box = boxes[e.key];
    if (box == null) {
      note.sets.remove(e.key);
      noteChanged = true;
      continue;
    }
    final entry = e.value;
    final keys = <String>[
      for (final i in entry.own) if (box.items.contains(i)) ?filmsByItem[i]?.key,
      for (final i in box.items) if (!entry.own.contains(i)) ?filmsByItem[i]?.key,
    ];
    if (keys.isEmpty) continue;
    final renamed = box.name != entry.seen;
    groups.adopt(VideoGroup(
      id: groups.newId(),
      name: renamed ? box.name : entry.name,
      keys: keys,
      description: entry.description,
      order: entry.order,
      createdMs: entry.changedMs,
      changedMs: renamed ? now : entry.changedMs,
      links: {serverKey: e.key},
    ));
    if (renamed) {
      entry
        ..name = box.name
        ..seen = box.name
        ..changedMs = now;
      noteChanged = true;
    }
  }

  // Deleted long ago: forgotten.
  final before = note.gone.length;
  note.gone.removeWhere((_, ms) => now - ms > goneKept.inMilliseconds);
  if (note.gone.length != before) noteChanged = true;

  if (noteChanged) await server.writeNote(note.encode());
  out.shared = [for (final g in groups.all) if (g.links.containsKey(serverKey)) g].length;
  return out;
}
