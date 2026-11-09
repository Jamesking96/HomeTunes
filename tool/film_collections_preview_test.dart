// Draws film collections (step 2, 9 Nov 2026) off-screen and saves pictures to C:\Temp\ht\preview
// (nothing is shown on screen): the Collections tab with a group of films first, All videos, and
// a group's page. The films are empty files with made-up names and generated pictures.
//   flutter test tool/film_collections_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/video_group_screen.dart';
import 'package:hometunes/ui/screens/videos_screen.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: r'C:\Temp\ht\preview');

  testWidgets('film collections previews', (tester) async {
    await tester.runAsync(() async {
      for (final f in [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\segoeuib.ttf']) {
        final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
        await loader.load();
      }
    });
    Directory(out).createSync(recursive: true);
    final dir = Directory.systemTemp.createTempSync('hometunes_groups_preview');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final vids = Directory(p.join(dir.path, 'Videos'))..createSync();
    for (final rel in [
      'Films/Pocket Critters The First Movie (1998)/a.mkv',
      'Films/Pocket Critters 2000 (1999)/a.mkv',
      'Films/Pocket Critters 3 (2000)/a.mkv',
      'Films/Pocket Critters 4Ever (2001)/a.mkv',
      'Films/Paper Boats (1998)/a.mkv',
      'Films/The Long Road (2011)/a.mkv',
      'TV/Harbour Days/Season 1/Harbour.Days.S01E01.mkv',
    ]) {
      File(p.joinAll([vids.path, ...rel.split('/')]))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([0]);
    }
    late final LibraryModel lib;
    late final VideoLibraryModel videos;
    await tester.runAsync(() async {
      final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      lib = LibraryModel(storage);
      videos = VideoLibraryModel(storage, lib);
      await lib.addVideoFolder(vids.path);
      await videos.scan();
      final thumbs = Directory(p.join(storage.artDir, 'video'))..createSync(recursive: true);
      var i = 0;
      for (final v in videos.videos) {
        final pic = img.Image(width: 480, height: 270);
        final hue = (i * 53) % 360;
        img.fillRect(pic, x1: 0, y1: 0, x2: 479, y2: 269, color: img.ColorRgb8(60 + hue % 150, 90, 160 - hue % 100));
        img.fillCircle(pic, x: 340, y: 100, radius: 60, color: img.ColorRgb8(240, 200 - hue % 90, 120));
        final f = File(p.join(thumbs.path, 'g$i.jpg'))..writeAsBytesSync(img.encodeJpg(pic));
        i++;
        // ignore: invalid_use_of_visible_for_testing_member
        videos.debugSetThumb(v.id, f.path, const Duration(minutes: 90));
      }
      final films = [for (final c in videos.collections) if (c.name.startsWith('Pocket')) c];
      videos.groups.create('Pocket Critters', films);
      await videos.setWatched([films.first.main.single.id], true);
      await videos.settle();
    });

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    Future<void> shot(String name, Widget home, {Future<void> Function()? then}) async {
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MultiProvider(
          providers: [
            ...libraryProviders(lib),
            ChangeNotifierProvider.value(value: videos),
            ChangeNotifierProvider(create: (_) => AppNav()),
          ],
          child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: home),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      if (then != null) {
        await then();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final png = await (await b.toImage()).toByteData(format: ui.ImageByteFormat.png);
        File('$out\\$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    await shot('film-collections-tab', const VideosScreen());
    await shot('film-collections-all-videos', const VideosScreen(), then: () => tester.tap(find.text('All videos')));
    await shot('film-collections-page', VideoGroupScreen(groupId: videos.groups.all.single.id));
  });
}
