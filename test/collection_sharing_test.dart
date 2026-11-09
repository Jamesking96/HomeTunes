// Sharing film collections through Jellyfin (9 Nov 2026; docs/ai-context/
// 09_COLLECTION_SHARING_PLAN.md): two devices and one pretend server. Made on one device, it's
// on the other after a read; changes go both ways and the newest wins; deleting is shared; a
// collection renamed in Jellyfin is renamed in HomeTunes; a user who may not change collections
// is told what to turn on.
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_group.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/jellyfin_client.dart';
import 'package:hometunes/state/collection_sharing.dart';
import 'package:hometunes/state/video_groups.dart';

class FakeServer implements CollectionServer {
  bool admin = true, manage = true;
  final Map<String, JellyfinCollection> boxes = {};
  String? note;
  var _n = 0;
  final List<String> calls = [];

  @override
  Future<({bool admin, bool manage})> rights() async => (admin: admin, manage: manage);
  @override
  Future<List<JellyfinCollection>> collections() async => boxes.values.toList();
  @override
  Future<String> create(String name, List<String> items) async {
    final id = 'box${++_n}';
    boxes[id] = JellyfinCollection(id: id, name: name, items: [...items]);
    calls.add('create $name');
    return id;
  }

  void _set(String id, {String? name, String? overview, List<String>? items}) {
    final b = boxes[id]!;
    boxes[id] = JellyfinCollection(id: id, name: name ?? b.name, overview: overview ?? b.overview, items: items ?? b.items);
  }

  @override
  Future<void> add(String id, List<String> items) async {
    if (!manage) throw const JellyfinException('403', fromServer: true, status: 403);
    _set(id, items: [...boxes[id]!.items, ...items]);
    calls.add('add $id ${items.join(',')}');
  }

  @override
  Future<void> remove(String id, List<String> items) async {
    _set(id, items: [for (final i in boxes[id]!.items) if (!items.contains(i)) i]);
    calls.add('remove $id ${items.join(',')}');
  }

  @override
  Future<void> update(String id, {required String name, String? overview}) async {
    if (!admin) throw const JellyfinException('403', fromServer: true, status: 403);
    _set(id, name: name, overview: overview ?? '');
    calls.add('update $id $name');
  }

  @override
  Future<void> delete(String id) async {
    boxes.remove(id);
    calls.add('delete $id');
  }

  @override
  Future<String?> readNote() async => note;
  @override
  Future<void> writeNote(String text) async => note = text;
}

/// A film from server "den" (its id there is [item]).
VideoCollection film(String name, String item, {int? year}) => VideoCollection(
      name: name,
      year: year,
      videos: [VideoItem(id: 'jf:den:$item', path: 'jellyfin://$item.mkv', title: name, collection: name)],
    );

/// A film in this device's own folders.
VideoCollection local(String name) =>
    VideoCollection(name: name, videos: [VideoItem(id: 'video:/films/$name.mkv', path: '/films/$name.mkv', title: name, collection: name)]);

/// One device: its films and its collections.
class Device {
  Device(this.films);
  final List<VideoCollection> films;
  final groups = VideoGroups(changed: () {});
  VideoCollection? find(String key) => films.where((c) => c.key == key).firstOrNull;
  VideoCollection named(String n) => films.firstWhere((c) => c.name == n);
  VideoGroup? group(String name) => groups.all.where((g) => g.name == name).firstOrNull;

  Future<ShareOutcome> sync(FakeServer s) => shareCollections(
        serverKey: 'den',
        serverName: 'Den',
        userName: 'james',
        server: s,
        groups: groups,
        filmsByItem: {
          for (final c in films)
            if (c.main.single.id.startsWith('jf:den:')) c.main.single.id.substring(7): c,
        },
        find: find,
      );
}

void main() {
  var clock = 1000;
  setUp(() {
    clock = 1000;
    VideoGroups.clock = () => clock += 10;
  });

  List<VideoCollection> catalogue() => [
        film('Dr. No', 'i1', year: 1962),
        film('Goldfinger', 'i2', year: 1964),
        film('Skyfall', 'i3', year: 2012),
        film('Snatch', 'i4', year: 2000),
      ];

  test('made on the PC: on the server, then on the TV after a read', () async {
    final server = FakeServer();
    final pc = Device([...catalogue(), local('Home movie')]), tv = Device(catalogue());
    final g = pc.groups.create('James Bond', [pc.named('Dr. No'), pc.named('Goldfinger'), pc.named('Home movie')]);
    pc.groups.describe(g, 'Shaken, not stirred');

    final out = await pc.sync(server);
    expect(out.shared, 1);
    expect(out.problem, isNull);
    final box = server.boxes.values.single;
    expect(box.name, 'James Bond');
    expect(box.items, ['i1', 'i2']); // the PC's own film isn't on the server
    expect(box.overview, 'Shaken, not stirred');
    expect(g.links, {'den': box.id});

    await tv.sync(server);
    final t = tv.group('James Bond')!;
    expect(t.keys, ['dr. no', 'goldfinger']);
    expect(t.description, 'Shaken, not stirred');
    expect(t.links, {'den': box.id});
    expect(server.calls.where((c) => c.startsWith('create')).length, 1);

    // A second read changes nothing.
    server.calls.clear();
    await pc.sync(server);
    await tv.sync(server);
    expect(server.calls, isEmpty);
    expect(pc.group('James Bond')!.keys, ['dr. no', 'goldfinger', 'home movie']);
  });

  test('changes go both ways and the newest wins; the order is shared', () async {
    final server = FakeServer();
    final pc = Device(catalogue()), tv = Device(catalogue());
    pc.groups.create('Bond', [pc.named('Dr. No'), pc.named('Goldfinger')]);
    await pc.sync(server);
    await tv.sync(server);

    // On the TV: renamed, Skyfall added, its own order.
    final t = tv.group('Bond')!;
    tv.groups.rename(t, 'James Bond');
    tv.groups.add(t, [tv.named('Skyfall')]);
    tv.groups.reorder(t, ['skyfall', 'dr. no', 'goldfinger']);
    await tv.sync(server);
    expect(server.boxes.values.single.name, 'James Bond');
    expect(server.boxes.values.single.items.toSet(), {'i1', 'i2', 'i3'});

    await pc.sync(server);
    final p = pc.group('James Bond')!;
    expect(p.keys, ['skyfall', 'dr. no', 'goldfinger']);
    expect(p.order, VideoGroupOrder.own);

    // Then on the PC: Goldfinger out. The TV follows.
    pc.groups.remove(p, ['goldfinger']);
    await pc.sync(server);
    expect(server.boxes.values.single.items.toSet(), {'i1', 'i3'});
    await tv.sync(server);
    expect(tv.group('James Bond')!.keys, ['skyfall', 'dr. no']);
  });

  test('deleting is shared; the films stay', () async {
    final server = FakeServer();
    final pc = Device(catalogue()), tv = Device(catalogue());
    pc.groups.create('Bond', [pc.named('Dr. No'), pc.named('Goldfinger')]);
    await pc.sync(server);
    await tv.sync(server);
    tv.groups.delete(tv.group('Bond')!);
    expect(tv.groups.removed, hasLength(1));
    await tv.sync(server);
    expect(server.boxes, isEmpty);
    expect(tv.groups.removed, isEmpty);
    await pc.sync(server);
    expect(pc.groups.isEmpty, isTrue);
    expect(pc.films, hasLength(4));
  });

  test('deleted or renamed in Jellyfin itself: HomeTunes follows', () async {
    final server = FakeServer();
    final pc = Device(catalogue());
    pc.groups.create('Bond', [pc.named('Dr. No'), pc.named('Goldfinger')]);
    pc.groups.create('Heists', [pc.named('Snatch'), pc.named('Skyfall')]);
    await pc.sync(server);
    final bond = server.boxes.values.firstWhere((b) => b.name == 'Bond');
    final heists = server.boxes.values.firstWhere((b) => b.name == 'Heists');
    server.boxes[bond.id] = JellyfinCollection(id: bond.id, name: '007', items: [...bond.items, 'i3']);
    server.boxes.remove(heists.id);
    await pc.sync(server);
    expect([for (final g in pc.groups.all) g.name], ['007']);
    expect(pc.group('007')!.keys.toSet(), {'dr. no', 'goldfinger', 'skyfall'});
  });

  test('other Jellyfin collections stay suggestions; two devices making the same name share one', () async {
    final server = FakeServer();
    server.boxes['tmdb'] = const JellyfinCollection(id: 'tmdb', name: 'James Bond Collection', items: ['i1', 'i2']);
    final pc = Device(catalogue()), tv = Device(catalogue());
    await pc.sync(server);
    expect(pc.groups.isEmpty, isTrue);

    pc.groups.create('Heists', [pc.named('Snatch')]);
    await pc.sync(server);
    tv.groups.create('heists', [tv.named('Skyfall')]);
    await tv.sync(server);
    expect(server.boxes.values.where((b) => b.name.toLowerCase() == 'heists'), hasLength(1));
    await pc.sync(server);
    expect(pc.group('heists')!.keys.toSet(), {'snatch', 'skyfall'});
  });

  test('a user who may not change collections is told what to turn on', () async {
    final server = FakeServer()
      ..admin = false
      ..manage = false;
    final pc = Device(catalogue());
    pc.groups.create('Bond', [pc.named('Dr. No')]);
    final out = await pc.sync(server);
    expect(out.shared, 0);
    expect(out.problem, contains('Allow this user to manage collections'));
    expect(server.boxes, isEmpty);
  });

  test('not an administrator: films are shared, the name is kept in HomeTunes\' note', () async {
    final server = FakeServer()..admin = false;
    final pc = Device(catalogue()), tv = Device(catalogue());
    final g = pc.groups.create('Bond', [pc.named('Dr. No')]);
    await pc.sync(server);
    pc.groups.rename(g, 'James Bond');
    await pc.sync(server);
    expect(server.boxes.values.single.name, 'Bond'); // Jellyfin's own name can't change
    await tv.sync(server);
    expect(tv.group('James Bond'), isNotNull);
  });

  test('the note survives reading back, and damage starts it afresh', () {
    final n = SharedNote()
      ..sets['b1'] = SharedEntry(name: 'Bond', own: ['i2', 'i1'], order: VideoGroupOrder.own, changedMs: 5, seen: 'Bond')
      ..gone['b2'] = 7;
    final back = SharedNote.parse(n.encode());
    expect(back.sets['b1']!.own, ['i2', 'i1']);
    expect(back.sets['b1']!.order, VideoGroupOrder.own);
    expect(back.gone, {'b2': 7});
    expect(SharedNote.parse('{not json').sets, isEmpty);
    expect(SharedNote.parse(null).sets, isEmpty);
  });

  test('links and when it changed are saved with the collection', () {
    final g = VideoGroup(id: 'g1', name: 'Bond', createdMs: 10, changedMs: 20, links: {'den': 'b1'});
    final back = VideoGroup.fromJson(g.toJson())!;
    expect(back.changedMs, 20);
    expect(back.links, {'den': 'b1'});
    expect(VideoGroup.fromJson({'id': 'g', 'name': 'x', 'createdMs': 5})!.changedMs, 5);
  });
}
