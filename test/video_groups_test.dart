// Film collections, step 1 (plan: docs/ai-context/07_FILM_COLLECTIONS_PLAN.md): the user's own
// groups of films. Films only (shows stay their own collections), kept in the shared
// videos.json, following a film's rename, in the group's order, with "what to watch next".
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_group.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/video_collection_screen.dart' show CollectionCard;
import 'package:hometunes/ui/screens/video_group_screen.dart';
import 'package:hometunes/ui/screens/videos_screen.dart';
import 'package:provider/provider.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_groups.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;
  late VideoLibraryModel videos;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_video_groups');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
    videos = VideoLibraryModel(storage, lib);
  });
  tearDown(() async {
    await videos.settle();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Three Pokémon films, a stand-alone film and a show.
  Future<void> scan() async {
    void file(String rel) => File(p.joinAll([dir.path, 'vids', ...rel.split('/')]))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1]);
    file('Films/Pokemon 3 (2000)/Pokemon 3 (2000).mkv');
    file('Films/Pokemon The First Movie (1998)/Pokemon The First Movie (1998).mkv');
    file('Films/Pokemon 2000 (1999)/Pokemon 2000 (1999).mkv');
    file('Films/Snatch (2000)/Snatch (2000).mkv');
    file('TV/Silo/Season 1/Silo S01E01.mkv');
    file('TV/Silo/Season 1/Silo S01E02.mkv');
    await lib.addVideoFolder(p.join(dir.path, 'vids'));
    await videos.scan();
  }

  List<String> names(Iterable<dynamic> cs) => [for (final c in cs) c.name as String];

  test('a group holds films only, in year order, and the rest stay on their own', () async {
    await scan();
    expect(videos.collections.length, 5);
    final pokemon = [for (final c in videos.collections) if (c.name.startsWith('Pokemon')) c];
    final silo = videos.collectionNamed('Silo')!;
    expect(isFilm(silo), isFalse);
    expect(pokemon.every(isFilm), isTrue);

    final g = videos.groups.create('Pokémon', [...pokemon, silo]);
    expect(g.keys.length, 3); // the show was left out
    expect(names(videos.filmsIn(g)), ['Pokemon The First Movie', 'Pokemon 2000', 'Pokemon 3']);
    // The Collections tab: the group, then what isn't in one (each thing once).
    expect(names(videos.ungrouped), ['Silo', 'Snatch']);
    expect(videos.groups.of(pokemon.first.key).single.name, 'Pokémon');

    videos.groups.setOrder(g, VideoGroupOrder.name);
    expect(names(videos.filmsIn(g)), ['Pokemon 2000', 'Pokemon 3', 'Pokemon The First Movie']);
    videos.groups.reorder(g, ['pokemon 3', 'pokemon the first movie']);
    expect(g.order, VideoGroupOrder.own);
    expect(names(videos.filmsIn(g)), ['Pokemon 3', 'Pokemon The First Movie', 'Pokemon 2000']);

    // Adding again does nothing; removing takes it out of the group only.
    expect(videos.groups.add(g, pokemon), 0);
    videos.groups.remove(g, ['pokemon 3']);
    expect(videos.filmsIn(g).length, 2);
    expect(names(videos.ungrouped), ['Pokemon 3', 'Silo', 'Snatch']);
    expect(videos.collectionNamed('Pokemon 3'), isNotNull);
  });

  test('groups are saved in the shared videos.json and come back', () async {
    await scan();
    final g = videos.groups.create('Pokémon', [for (final c in videos.collections) if (c.name.startsWith('Pokemon')) c]);
    videos.groups.describe(g, '  Gotta watch them all  ');
    videos.groups.create('Heist films', [videos.collectionNamed('Snatch')!]);
    await videos.settle();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final saved = jsonDecode(File(p.join(storage.root.path, VideoLibraryModel.fileName)).readAsStringSync()) as Map;
    expect((saved['groups'] as List).length, 2);
    // Not in the person's own files (shared by every profile).
    final edits = File(p.join(storage.root.path, VideoLibraryModel.editsFileName));
    if (edits.existsSync()) expect(edits.readAsStringSync(), isNot(contains('groups')));

    final again = VideoLibraryModel(storage, lib);
    await again.load();
    expect([for (final x in again.groups.all) x.name], ['Heist films', 'Pokémon']);
    final back = again.groups.byId(g.id)!;
    expect(back.description, 'Gotta watch them all');
    expect(again.filmsIn(back).length, 3);
    again.dispose();
  });

  test('renaming a film keeps its place in groups; deleting a group keeps the films', () async {
    await scan();
    final snatch = videos.collectionNamed('Snatch')!;
    final g = videos.groups.create('Guy Ritchie', [snatch]);
    await videos.editCollection(snatch, name: 'Snatch (2000 film)');
    expect(g.keys, ['snatch (2000 film)']);
    expect(names(videos.filmsIn(g)), ['Snatch (2000 film)']);
    videos.groups.delete(g);
    expect(videos.groups.isEmpty, isTrue);
    expect(videos.collectionNamed('Snatch (2000 film)'), isNotNull);
    expect(videos.ungrouped.length, 5);
  });

  test('what to watch next in a group, and how many are watched', () async {
    await scan();
    final g = videos.groups.create('Pokémon', [for (final c in videos.collections) if (c.name.startsWith('Pokemon')) c]);
    final first = videos.filmsIn(g).first;
    expect(videos.nextInGroup(g)?.name, first.name);
    await videos.setWatched([first.main.single.id], true);
    expect(videos.watchedInGroup(g), 1);
    expect(videos.nextInGroup(g)?.name, 'Pokemon 2000');
  });

  // ---- step 2: on screen ----

  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ...libraryProviders(lib),
        ChangeNotifierProvider.value(value: videos),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: MaterialApp(home: home),
    ));
    await tester.pump();
  }

  testWidgets('Collections: the groups, then what isn\'t in one; All videos: every show and film', (tester) async {
    await tester.runAsync(scan);
    videos.groups.create('Pokémon', [for (final c in videos.collections) if (c.name.startsWith('Pokemon')) c]);
    await show(tester, const VideosScreen());
    expect(find.text('Film collections'), findsOneWidget);
    expect(find.widgetWithText(GroupCard, 'Pokémon'), findsOneWidget);
    expect(find.textContaining('3 films · 1998–2000'), findsOneWidget);
    expect(find.byType(CollectionCard), findsNWidgets(2)); // Silo and Snatch, not the Pokémon films
    expect(find.widgetWithText(CollectionCard, 'Pokemon 3'), findsNothing);

    await tester.tap(find.text('All videos'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionCard), findsNWidgets(5));
    expect(find.byType(GroupCard), findsNothing);

    await tester.tap(find.text('Every video'));
    await tester.pumpAndSettle();
    expect(find.byType(VideoCard), findsWidgets);
    expect(find.text('Favourites'), findsOneWidget);
  });

  testWidgets('a group\'s page: its films and what to watch next', (tester) async {
    await tester.runAsync(scan);
    final g = videos.groups.create('Pokémon', [for (final c in videos.collections) if (c.name.startsWith('Pokemon')) c]);
    await show(tester, VideoGroupScreen(groupId: g.id));
    expect(find.text('Pokémon'), findsOneWidget);
    expect(find.text('COLLECTION'), findsOneWidget);
    expect(find.byType(CollectionCard), findsNWidgets(3));
    expect(find.text('Play: Pokemon The First Movie'), findsOneWidget);
    await show(tester, const VideoGroupScreen(groupId: 'gone'));
    expect(find.text('This collection has been deleted'), findsOneWidget);
  });

  test('a damaged group in the file is skipped', () {
    expect(VideoGroup.fromJson({'id': 'g1'}), isNull);
    expect(VideoGroup.fromJson({'id': 'g1', 'name': ' ', 'keys': []}), isNull);
    final g = VideoGroup.fromJson({'id': 'g1', 'name': 'Bond', 'keys': ['a', 'a', 3, 'b'], 'order': 'nope'})!;
    expect(g.keys, ['a', 'b']);
    expect(g.order, VideoGroupOrder.year);
  });
}
