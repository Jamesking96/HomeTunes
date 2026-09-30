// Change picture… / Change poster… (ui/screens/video_pictures.dart): the choices offered, the
// online search dialog (against a fake service), and a picked picture being saved. The frame
// picker needs the real video engine, so it's only checked to be offered here.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/video_art_search.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/video_pictures.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late LibraryModel lib;
  late VideoLibraryModel model;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_pictures');
    final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
    model = VideoLibraryModel(storage, lib);
  });
  tearDown(() async {
    await model.settle();
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
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
        ChangeNotifierProvider.value(value: model),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: MaterialApp(
        home: Scaffold(body: Builder(builder: (context) => TextButton(onPressed: () => onTap(context), child: const Text('go')))),
      ),
    ));
  }

  testWidgets('the choices: file, frame, online (unless switched off), and back to automatic', (tester) async {
    await scan(tester);
    final v = model.videos.single;
    await pump(tester, (context) => showVideoPictureOptions(context, v));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an image file…'), findsOneWidget);
    expect(find.text('Pick a frame from the video…'), findsOneWidget);
    expect(find.text('Search online…'), findsOneWidget);
    expect(find.text('Use the automatic picture'), findsNothing); // none chosen yet
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // With a picture chosen and online lookups off.
    await tester.runAsync(() async {
      await model.setPicture(v, [0xFF, 0xD8, 0xFF, 0xE0, 1]);
      await lib.setOnlineVideoArt(false);
    });
    // Tapped in real time, so the saving after the choice (file work) runs too.
    await tester.runAsync(() async => tester.tap(find.text('go')));
    await tester.pumpAndSettle();
    expect(find.text('Switched off in Settings › Online lookups'), findsOneWidget);
    await tester.tap(find.text('Use the automatic picture'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await model.settle();
    });
    await tester.pumpAndSettle();
    expect(model.hasOwnPicture(v), isFalse);
    expect(find.text('Back to the automatic picture'), findsOneWidget);
  });

  testWidgets('search online: posters first for a collection, services that failed said, a pick is saved', (tester) async {
    await scan(tester);
    // A real (tiny) picture to "download".
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
      if (r.url.host == 'graphql.anilist.co') return http.Response('down', 503);
      return http.Response('{}', 200);
    }));
    final c = model.collections.single;
    List<int>? got;
    await pump(tester, (context) async {
      got = await showPictureSearch(context, query: c.name, forPoster: true, search: search);
      if (got != null) await model.setPoster(c, got);
    });
    // Tapped in real time, so the download, shrinking and saving after the pick run too.
    await tester.runAsync(() async {
      await tester.tap(find.text('go'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(asked, containsAll(['api.tvmaze.com', 'graphql.anilist.co', 'en.wikipedia.org']));
    expect(find.text('Couldn\'t reach AniList just now.'), findsOneWidget);
    // The poster comes before the background.
    final kinds = [for (final t in tester.widgetList<Text>(find.textContaining(' · TVmaze'))) t.data];
    expect(kinds, ['Poster · TVmaze', 'Background · TVmaze']);

    await tester.runAsync(() async {
      await tester.tap(find.text('Poster · TVmaze'));
      for (var i = 0; i < 40 && !model.hasOwnPoster(model.collections.single); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await model.settle();
    });
    await tester.pumpAndSettle();
    expect(got, isNotNull);
    expect(model.hasOwnPoster(model.collections.single), isTrue);
    expect(model.coverFile(model.collections.single), startsWith(model.customPictureDir));
  });
}
