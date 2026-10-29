// Change poster / Change picture on the TV (ui/tv/tv_pictures.dart, 0.2.5): the name searched
// for, the choices offered, and the search page (against a fake service) saving a pick.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/video_art_search.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/tv/tv_pictures.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  test('the name searched for leaves out release tags, dots and episode ranges', () {
    expect(tvSearchName('[Judas] Steins;Gate'), 'Steins;Gate');
    expect(tvSearchName('[Z-Z] Claymore 1-26 DVD Dual Audio'), 'Claymore');
    expect(tvSearchName('Chainsaw.Man.The.Movie'), 'Chainsaw Man The Movie');
    expect(tvSearchName('Death Note (TV Series)'), 'Death Note');
    expect(tvSearchName('Berserk (1997-10-07)'), 'Berserk');
    expect(tvSearchName('Silo'), 'Silo');
    expect(tvSearchName('[only a tag]'), '[only a tag]'); // nothing left: the name as it is
  });

  late Directory dir;
  late LibraryModel lib;
  late VideoLibraryModel model;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_tv_pictures');
    final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
    model = VideoLibraryModel(storage, lib);
  });
  tearDown(() async {
    await model.settle();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    dir.deleteSync(recursive: true);
  });

  Future<void> scan(WidgetTester tester) async {
    final show = Directory(p.join(dir.path, 'vids', 'TV', 'Silo', 'Season 1'))..createSync(recursive: true);
    File(p.join(show.path, 'Silo S01E02.mkv')).writeAsBytesSync([1]);
    await tester.runAsync(() async {
      await lib.addVideoFolder(p.join(dir.path, 'vids'));
      await model.scan();
    });
  }

  Future<void> pump(WidgetTester tester, void Function(BuildContext) onTap) async {
    tester.view.physicalSize = const Size(960, 540); // the TV's layout size
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ...libraryProviders(lib),
        ChangeNotifierProvider.value(value: model),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: MaterialApp(
        home: Scaffold(body: Builder(builder: (context) => TextButton(onPressed: () => onTap(context), child: const Text('go')))),
      ),
    ));
  }

  testWidgets('Change poster offers Search online and a picture file; automatic once one is chosen', (tester) async {
    await scan(tester);
    final c = model.collections.single;
    await pump(tester, (context) => tvChangePosterOption(context, c).onSelected());
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Poster for "Silo"'), findsOneWidget);
    expect(find.text('Search online'), findsOneWidget);
    expect(find.text('Choose a picture file'), findsOneWidget);
    expect(find.text('Use the automatic poster'), findsNothing);
    Navigator.of(tester.element(find.text('Search online'))).pop();
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await model.setPoster(c, [0xFF, 0xD8, 0xFF, 0xE0, 1]);
      await lib.setOnlineVideoArt(false);
    });
    await pump(tester, (context) => tvChangePosterOption(context, model.collections.single).onSelected());
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Search online is off'), findsOneWidget);
    expect(find.text('Use the automatic poster'), findsOneWidget);
  });

  testWidgets('the search page: posters first, a pick is downloaded and kept as the poster', (tester) async {
    await scan(tester);
    final png = img.encodePng(img.Image(width: 40, height: 60));
    final asked = <String>[];
    final search = VideoArtSearch(client: MockClient((r) async {
      asked.add(r.url.host);
      if (r.url.host == 'api.tvmaze.com' && r.url.path == '/search/shows') {
        return http.Response(jsonEncode([{'score': 0.9, 'show': {'id': 7, 'name': 'Silo', 'premiered': '2023-05-05'}}]), 200);
      }
      if (r.url.path == '/shows/7/images') {
        return http.Response(jsonEncode([
          {'type': 'background', 'resolutions': {'original': {'url': 'https://tv/bg.jpg', 'width': 1920, 'height': 1080}}},
          {'type': 'poster', 'resolutions': {'original': {'url': 'https://tv/p.png', 'width': 400, 'height': 600}}},
        ]), 200);
      }
      if (r.url.host == 'tv' && r.url.path == '/p.png') return http.Response.bytes(png, 200);
      return http.Response('{}', 200);
    }));
    final c = model.collections.single;
    await pump(tester, (context) async {
      final got = await showTvPictureSearch(context, query: c.name, forPoster: true, search: search);
      if (got != null) await model.setPoster(c, got);
    });
    await tester.runAsync(() async {
      await tester.tap(find.text('go'));
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (['api.tvmaze.com', 'graphql.anilist.co', 'en.wikipedia.org'].every(asked.contains)) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Choose a poster'), findsOneWidget);
    expect(find.text('Search for another name'), findsOneWidget);
    final kinds = [for (final t in tester.widgetList<Text>(find.textContaining(' · TVmaze'))) t.data];
    expect(kinds, ['Poster · TVmaze', 'Background · TVmaze']);

    await tester.runAsync(() async {
      await tester.tap(find.text('Poster · TVmaze'));
      for (var i = 0; i < 200 && !model.hasOwnPoster(model.collections.single); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await model.settle();
    });
    await tester.pumpAndSettle();
    expect(find.text('Choose a poster'), findsNothing); // the page closed
    expect(model.hasOwnPoster(model.collections.single), isTrue);
  });
}
