// Draws the Videos tab (0.1.32) off-screen and saves pictures to C:\Temp\ht\preview (nothing is
// shown on screen): the grid with Continue watching and collections, a video's menu, the Edit
// details dialog for several videos, the filter sheet, and Settings › Folders & scanning with the video folders.
// The "videos" are empty files with made-up names; their thumbnails are plain generated
// pictures. Uses Windows' Segoe UI so the text is readable. The player page and the music video
// buttons need the real video engine, so they aren't drawn here.
//   flutter test tool/videos_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/equalizer_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/update_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/settings/settings_screen.dart';
import 'package:hometunes/ui/screens/video_collection_screen.dart';
import 'package:hometunes/ui/screens/videos_screen.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:image/image.dart' as img;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: r'C:\Temp\ht\preview');

  testWidgets('0.1.32 Videos previews', (tester) async {
    await tester.runAsync(() async {
      for (final f in [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\segoeuib.ttf']) {
        final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
        await loader.load();
      }
    });
    // ignore: invalid_use_of_visible_for_testing_member
    PackageInfo.setMockInitialValues(
        appName: 'HomeTunes', packageName: 'x', version: '0.1.32', buildNumber: '32', buildSignature: '');
    Directory(out).createSync(recursive: true);
    final dir = Directory.systemTemp.createTempSync('hometunes_videos_preview');
    final vids = Directory(p.join(dir.path, 'Videos'))..createSync();
    final data = Directory(p.join(dir.path, 'data'))..createSync();
    final names = {
      'TV/Harbour Days/Season 1': ['Harbour.Days.S01E01.Arrival.mkv', 'Harbour.Days.S01E02.The.Storm.mkv'],
      'TV/Harbour Days/Season 2': ['Harbour.Days.S02E01.Lanterns.mkv', 'Harbour.Days.S02E02.Home.Again.mkv'],
      'TV/Harbour Days/Extras': ['Behind the scenes.mp4'],
      'Holiday 2024': ['Beach morning.mp4', 'Mountain.Walk.2024.webm', 'Night market.mov'],
      'Films': ['Paper.Boats.1998.avi', 'The_Long_Road_(2011).mkv'],
    };
    for (final e in names.entries) {
      final d = Directory(p.join(vids.path, e.key))..createSync(recursive: true);
      for (final n in e.value) {
        File(p.join(d.path, n)).writeAsBytesSync([0]);
      }
    }

    // Made in real time (not the test's pretend clock), or their queued work would never run.
    late final Storage storage;
    late final LibraryModel lib;
    late final VideoLibraryModel videos;
    await tester.runAsync(() async {
      storage = Storage.at(data);
      lib = LibraryModel(storage);
      videos = VideoLibraryModel(storage, lib);
      await lib.addVideoFolder(vids.path);
      await videos.scan();
      // Plain generated pictures as thumbnails, and a few watched places.
      final thumbs = Directory(p.join(storage.artDir, 'video'))..createSync(recursive: true);
      var i = 0;
      for (final v in videos.videos) {
        final pic = img.Image(width: 480, height: 270);
        final hue = (i * 47) % 360;
        img.fillRect(pic, x1: 0, y1: 0, x2: 479, y2: 269, color: _hsv(hue, 0.45, 0.55));
        img.fillCircle(pic, x: 360, y: 90, radius: 50, color: _hsv(hue + 40, 0.3, 0.9));
        img.fillRect(pic, x1: 0, y1: 190, x2: 479, y2: 269, color: _hsv(hue + 180, 0.4, 0.35));
        final f = File(p.join(thumbs.path, 'preview$i.jpg'))..writeAsBytesSync(img.encodeJpg(pic));
        i++;
        // ignore: invalid_use_of_visible_for_testing_member
        videos.debugSetThumb(v.id, f.path, Duration(minutes: 20 + i * 7));
      }
      final list = videos.videos;
      videos.savePlace(list[0].id, const Duration(minutes: 12), const Duration(minutes: 27));
      videos.savePlace(list[5].id, const Duration(minutes: 40), const Duration(minutes: 62));
      await videos.setWatched([list[1].id, list[2].id], true);
      await videos.setFavourite(videos.collectionNamed('Harbour Days')!, true);
      // A tall poster chosen for Harbour Days (shown whole over a blurred copy).
      final poster = img.Image(width: 400, height: 600);
      img.fillRect(poster, x1: 0, y1: 0, x2: 399, y2: 599, color: _hsv(20, 0.6, 0.5));
      img.fillRect(poster, x1: 40, y1: 60, x2: 360, y2: 160, color: _hsv(50, 0.2, 0.95));
      img.fillCircle(poster, x: 200, y: 400, radius: 120, color: _hsv(200, 0.5, 0.8));
      await videos.setPoster(videos.collectionNamed('Harbour Days')!, img.encodeJpg(poster));
      await videos.settle();
    });

    final nav = AppNav();
    tester.view.physicalSize = const Size(1280, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();

    Future<void> show(Widget home) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: videos),
          ChangeNotifierProvider.value(value: nav),
          ChangeNotifierProvider(create: (_) => EqualizerModel(storage)),
          ChangeNotifierProvider(create: (_) => UpdateModel(storage, readVersion: () async => '0.1.32')),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: home),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300))); // pictures load
      await tester.pumpAndSettle();
    }

    Future<void> shoot(String name) => tester.runAsync(() async {
          final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final png = await (await b.toImage()).toByteData(format: ui.ImageByteFormat.png);
          File('$out\\$name.png').writeAsBytesSync(png!.buffer.asUint8List());
        });

    // 0. Collections, a collection's page, and Edit collection.
    await show(const VideosScreen());
    await shoot('videos-collections');
    await show(const VideoCollectionScreen(name: 'Harbour Days'));
    await shoot('videos-collection-page');
    await tester.tap(find.text('Edit collection'));
    await tester.pumpAndSettle();
    await shoot('videos-edit-collection');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change poster'));
    await tester.pumpAndSettle();
    await shoot('videos-poster-options');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // 1. The grid.
    await show(const VideosScreen());
    await tester.tap(find.text('All videos'));
    await tester.pumpAndSettle();
    await shoot('videos-grid');

    // 2. A video's menu.
    await tester.tap(find.byTooltip('More').at(3));
    await tester.pumpAndSettle();
    await shoot('videos-menu');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // 3. Select two, then Edit details for both.
    await tester.longPress(find.byType(VideoCard).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(VideoCard).at(3));
    await tester.pumpAndSettle();
    await shoot('videos-selected');
    await tester.tap(find.byTooltip('Edit details'));
    await tester.pumpAndSettle();
    await shoot('videos-edit-several');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // 5. The filter sheet, then the grid with a filter on.
    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-Collection')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Harbour Days  (5)').last);
    await tester.pumpAndSettle();
    await shoot('videos-filter-sheet');
    await tester.tap(find.text('Show videos'));
    await tester.pumpAndSettle();
    await shoot('videos-filtered');
    // 4. Settings › Folders & scanning.
    await show(const SettingsScreen());
    nav.openSettings('library', setting: 'library-video-folders');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await shoot('videos-settings');

    await tester.runAsync(() async {
      await videos.settle();
      dir.deleteSync(recursive: true);
    });
  });
}

img.Color _hsv(int hue, double s, double v) {
  final c = HSVColor.fromAHSV(1, (hue % 360).toDouble(), s, v).toColor();
  return img.ColorRgb8((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());
}
