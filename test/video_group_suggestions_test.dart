// Film collections, step 5 (9 Nov 2026): suggested collections, from the server's own
// collections, the films' .nfo `<set>` and similar names. Nothing is made without a yes.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_group_suggestions.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/video_group_screen.dart' show GroupCard;
import 'package:hometunes/ui/screens/videos_screen.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:hometunes/ui/tv/tv_videos.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;
  late VideoLibraryModel videos;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_group_suggest');
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

  void file(String rel, [String? text]) {
    final f = File(p.joinAll([dir.path, 'vids', ...rel.split('/')]))..parent.createSync(recursive: true);
    text == null ? f.writeAsBytesSync([1]) : f.writeAsStringSync(text);
  }

  String bond(String title) => '<movie><title>$title</title><set><name>James Bond Collection</name></set></movie>';

  Future<void> scan() async {
    file('Films/Pokemon 3 (2000)/Pokemon 3 (2000).mkv');
    file('Films/Pokemon The First Movie (1998)/Pokemon The First Movie (1998).mkv');
    file('Films/Pokemon 2000 (1999)/Pokemon 2000 (1999).mkv');
    file('Films/Monty Python and the Holy Grail (1975)/Monty Python and the Holy Grail (1975).mkv');
    file('Films/Monty Python\'s Life of Brian (1979)/Monty Python\'s Life of Brian (1979).mkv');
    file('Films/Goldfinger (1964)/Goldfinger (1964).mkv');
    file('Films/Goldfinger (1964)/Goldfinger (1964).nfo', bond('Goldfinger'));
    file('Films/Skyfall (2012)/Skyfall (2012).mkv');
    file('Films/Skyfall (2012)/Skyfall (2012).nfo', bond('Skyfall'));
    file('Films/Love Actually (2003)/Love Actually (2003).mkv');
    file('Films/Love Story (1970)/Love Story (1970).mkv');
    file('Films/Snatch (2000)/Snatch (2000).mkv');
    file('Films/Heat (1995)/Heat (1995).mkv');
    file('TV/Silo/Season 1/Silo S01E01.mkv');
    file('TV/Silo/Season 1/Silo S01E02.mkv');
    await lib.addVideoFolder(p.join(dir.path, 'vids'));
    await videos.scan();
  }

  List<String> names(Iterable<dynamic> cs) => [for (final c in cs) c.name as String]..sort();

  test('an .nfo <set> keeps each film its own, and is suggested as a collection', () async {
    await scan();
    // Before 9 Nov, a <set> made Goldfinger and Skyfall one show's "episodes".
    expect(videos.collectionNamed('Goldfinger'), isNotNull);
    expect(videos.collectionNamed('Skyfall'), isNotNull);
    expect(videos.collectionNamed('James Bond Collection'), isNull);
    expect(videos.collectionNamed('Goldfinger')!.main.single.setName, 'James Bond Collection');

    final s = videos.localSuggestions;
    final byName = {for (final x in s) x.name: x};
    expect(byName.keys.toSet(), {'James Bond', 'Pokemon', 'Monty Python'});
    expect(byName['James Bond']!.source, SuggestionSource.nfo);
    expect(names(byName['James Bond']!.films), ['Goldfinger', 'Skyfall']);
    expect(names(byName['Pokemon']!.films), ['Pokemon 2000', 'Pokemon 3', 'Pokemon The First Movie']);
    expect(names(byName['Monty Python']!.films), ['Monty Python and the Holy Grail', 'Monty Python\'s Life of Brian']);
    expect(byName['Pokemon']!.source, SuggestionSource.names);
    // Love Actually and Love Story share only a first word: not suggested. Nothing was made.
    expect(videos.groups.isEmpty, isTrue);
  });

  test('the server\'s own collections come first; yes makes it, no thanks is remembered', () async {
    await scan();
    String id(String name) => videos.collectionNamed(name)!.main.single.id;
    videos.serverFilmSets = () async => [
          (name: 'Heist Collection', server: 'Den', ids: [id('Snatch'), id('Heat'), 'jf:den:gone']),
        ];
    final all = await videos.groupSuggestions();
    expect(all.first.name, 'Heist');
    expect(all.first.why, 'From the server\'s own collections (Den)');
    expect(names(all.first.films), ['Heat', 'Snatch']);

    final g = videos.acceptSuggestion(all.first, all.first.films, name: 'Heists');
    expect(g.name, 'Heists');
    expect(videos.filmsIn(g).length, 2);
    // Films in a collection aren't suggested again.
    expect((await videos.groupSuggestions()).map((s) => s.name), isNot(contains('Heist')));

    final pokemon = (await videos.groupSuggestions()).firstWhere((s) => s.name == 'Pokemon');
    await videos.dismissSuggestion(pokemon);
    expect((await videos.groupSuggestions()).map((s) => s.name), isNot(contains('Pokemon')));
    await videos.settle();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final saved = jsonDecode(File(p.join(storage.root.path, VideoLibraryModel.fileName)).readAsStringSync()) as Map;
    expect(saved['groupsDismissed'], ['pokemon']);

    // Read again: still said no to; then offered again on request.
    final again = VideoLibraryModel(storage, lib);
    await again.load();
    expect(again.localSuggestions.map((s) => s.name), isNot(contains('Pokemon')));
    expect(again.hasDismissedSuggestions, isTrue);
    await again.undismissSuggestions();
    expect(again.localSuggestions.map((s) => s.name), contains('Pokemon'));
    await again.settle();
  });

  test('a suggestion named like one of your collections adds to it', () async {
    await scan();
    final first = videos.collectionNamed('Pokemon 3')!;
    final g = videos.groups.create('pokemon', [first]);
    final s = videos.localSuggestions.firstWhere((s) => s.name == 'Pokemon');
    expect(s.into?.id, g.id);
    expect(names(s.films), ['Pokemon 2000', 'Pokemon The First Movie']);
    expect(identical(videos.acceptSuggestion(s, s.films), g), isTrue);
    expect(videos.filmsIn(g).length, 3);
    expect(videos.groups.all.length, 1);
  });

  Future<void> show(WidgetTester tester, Widget home, {bool tvMode = false}) async {
    tester.view.physicalSize = tvMode ? const Size(1920, 1080) : const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ...libraryProviders(lib),
        ChangeNotifierProvider.value(value: videos),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: MaterialApp(
        theme: tvMode ? tvTheme(buildTheme(), AppColors.accent) : null,
        builder: tvMode ? (context, child) => TvFocus(enabled: true, sounds: false, child: child!) : null,
        home: tvMode ? const Scaffold(body: TvVideosScreen()) : home,
      ),
    ));
    await tester.pump();
  }

  testWidgets('Suggested collections: untick a film, Make collection; No thanks', (tester) async {
    await tester.runAsync(scan);
    await show(tester, const VideosScreen());
    await tester.tap(find.byKey(const ValueKey('suggest-open')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Suggested collections'), findsWidgets);
    expect(find.byKey(const ValueKey('suggest:pokemon')), findsOneWidget);
    expect(videos.groups.isEmpty, isTrue);

    await tester.tap(find.byKey(const ValueKey('suggest-film:pokemon 3')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('suggest-name:pokemon')), 'Pokémon');
    await tester.tap(find.byKey(const ValueKey('suggest-yes:pokemon')));
    await tester.pumpAndSettle();
    final g = videos.groups.all.single;
    expect(g.name, 'Pokémon');
    expect(g.keys.toSet(), {'pokemon 2000', 'pokemon the first movie'});
    expect(find.byKey(const ValueKey('suggest:pokemon')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('suggest-no:monty python')));
    await tester.tap(find.byKey(const ValueKey('suggest-no:monty python')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('suggest:monty python')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('suggest-close')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(GroupCard, 'Pokémon'), findsOneWidget);
    await tester.runAsync(videos.settle);
  });

  testWidgets('TV: Suggested › a suggestion › Make the collection', (tester) async {
    await tester.runAsync(scan);
    await show(tester, const SizedBox(), tvMode: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tv-suggest')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('James Bond'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make the collection'));
    await tester.pumpAndSettle();
    final g = videos.groups.all.single;
    expect(g.name, 'James Bond');
    expect(g.keys.toSet(), {'goldfinger', 'skyfall'});
    expect(find.byKey(ValueKey('tv-group:${g.id}')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(videos.settle);
  });
}
