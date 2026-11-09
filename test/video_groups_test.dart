// Film collections, step 1 (plan: docs/ai-context/07_FILM_COLLECTIONS_PLAN.md): the user's own
// groups of films. Films only (shows stay their own collections), kept in the shared
// videos.json, following a film's rename, in the group's order, with "what to watch next".
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_group.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/video_collection_screen.dart' show CollectionCard;
import 'package:hometunes/ui/screens/video_group_screen.dart';
import 'package:hometunes/ui/screens/videos_screen.dart';
import 'package:hometunes/ui/widgets/fold_heading.dart';
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

  testWidgets('headings fold up and open again (9 Nov: "Make all headers … colapsable")', (tester) async {
    FoldedHeadings.openAll();
    addTearDown(FoldedHeadings.openAll);
    await tester.runAsync(scan);
    videos.groups.create('Pokémon', [for (final c in videos.collections) if (c.name.startsWith('Pokemon')) c]);
    await show(tester, const VideosScreen());
    await tester.tap(find.byKey(const ValueKey('fold:videos.collections:Film collections')));
    await tester.pumpAndSettle();
    expect(find.byType(GroupCard), findsNothing);
    expect(find.text('  ·  1'), findsOneWidget); // how many, while folded
    expect(find.byType(CollectionCard), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('fold:videos.collections:Shows and films')));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionCard), findsNothing);
    await tester.tap(find.byKey(const ValueKey('fold:videos.collections:Film collections')));
    await tester.pumpAndSettle();
    expect(find.byType(GroupCard), findsOneWidget);
    // Every video: the sort's headings fold too.
    await tester.tap(find.text('Every video'));
    await tester.pumpAndSettle();
    bool shownCard() => tester.widgetList<VideoCard>(find.byType(VideoCard)).any((c) => c.video.collection == 'Pokemon 2000');
    expect(shownCard(), isTrue);
    await tester.tap(find.byKey(const ValueKey('fold:videos.every:Pokemon 2000')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fold:videos.every:Pokemon 2000')), findsOneWidget); // the heading stays
    expect(shownCard(), isFalse);
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

  // ---- step 3: making and changing them ----

  Future<void> rightClick(WidgetTester tester, Finder f) async {
    await tester.tap(f, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  testWidgets('a film\'s menu: Add to collection… › New collection…, then Remove from it', (tester) async {
    FoldedHeadings.openAll();
    await tester.runAsync(scan);
    await show(tester, const VideosScreen());
    await rightClick(tester, find.widgetWithText(CollectionCard, 'Snatch'));
    expect(find.text('Add to collection…'), findsOneWidget);
    await tester.tap(find.text('Add to collection…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New collection…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Guy Ritchie');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final g = videos.groups.all.single;
    expect(g.name, 'Guy Ritchie');
    expect(g.keys, ['snatch']);
    expect(find.widgetWithText(GroupCard, 'Guy Ritchie'), findsOneWidget);
    expect(find.widgetWithText(CollectionCard, 'Snatch'), findsNothing); // now inside the collection

    // A show's menu has no Add to collection (shows stay their own collections).
    await rightClick(tester, find.widgetWithText(CollectionCard, 'Silo'));
    expect(find.text('Add to collection…'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // All videos: the film's menu says Remove from "Guy Ritchie".
    await tester.tap(find.text('All videos'));
    await tester.pumpAndSettle();
    await rightClick(tester, find.widgetWithText(CollectionCard, 'Snatch'));
    await tester.tap(find.text('Remove from "Guy Ritchie"'));
    await tester.pumpAndSettle();
    expect(g.keys, isEmpty);
  });

  testWidgets('Select mode: several films into an existing collection', (tester) async {
    FoldedHeadings.openAll();
    await tester.runAsync(scan);
    final g = videos.groups.create('Pokémon');
    await show(tester, const VideosScreen());
    await tester.tap(find.text('All videos'));
    await tester.pumpAndSettle();
    await rightClick(tester, find.widgetWithText(CollectionCard, 'Pokemon 3'));
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CollectionCard, 'Pokemon 2000'));
    await tester.tap(find.widgetWithText(CollectionCard, 'Silo')); // a show: left out
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('select-add-to-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('group-pick:${g.id}')));
    await tester.pumpAndSettle();
    expect(g.keys, unorderedEquals(['pokemon 3', 'pokemon 2000']));
  });

  testWidgets('a collection\'s page: Edit (name, description, order) and Delete', (tester) async {
    await tester.runAsync(scan);
    final g = videos.groups.create('Pokemon', [for (final c in videos.collections) if (c.name.startsWith('Pokemon')) c]);
    await show(tester, VideoGroupScreen(groupId: g.id));
    await tester.tap(find.byKey(const ValueKey('group-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('group-name')), 'Pokémon films');
    await tester.enterText(find.byKey(const ValueKey('group-description')), 'Every one of them');
    await tester.tap(find.text('By name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((g.name, g.description, g.order), ('Pokémon films', 'Every one of them', VideoGroupOrder.name));
    expect(find.text('Every one of them'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('group-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-group-delete')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Delete'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(videos.groups.isEmpty, isTrue);
    expect(videos.collections.length, 5); // the films stay
  });

  test('a collection\'s own picture is kept with it, and goes back to the films\' posters', () async {
    await scan();
    final g = videos.groups.create('Pokémon', [for (final c in videos.collections) if (c.name.startsWith('Pokemon')) c]);
    expect(videos.groupPosterFile(g), isNull);
    await videos.setGroupPoster(g, [0xFF, 0xD8, 0xFF, 1, 2, 3]);
    final file = videos.groupPosterFile(g);
    expect(file, isNotNull);
    expect(File(file!).existsSync(), isTrue);
    final again = VideoLibraryModel(storage, lib);
    await again.load();
    expect(again.groupPosterFile(again.groups.byId(g.id)!), file);
    again.dispose();
    await videos.setGroupPoster(g, null);
    expect(videos.groupPosterFile(g), isNull);
    expect(File(file).existsSync(), isFalse); // tidied away
  });

  test('a damaged group in the file is skipped', () {
    expect(VideoGroup.fromJson({'id': 'g1'}), isNull);
    expect(VideoGroup.fromJson({'id': 'g1', 'name': ' ', 'keys': []}), isNull);
    final g = VideoGroup.fromJson({'id': 'g1', 'name': 'Bond', 'keys': ['a', 'a', 3, 'b'], 'order': 'nope'})!;
    expect(g.keys, ['a', 'b']);
    expect(g.order, VideoGroupOrder.year);
  });
}
