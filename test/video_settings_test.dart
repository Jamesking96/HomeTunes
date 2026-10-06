// Settings › Videos (0.1.40): skip amounts, speed, rewinding, a separate equaliser for videos,
// and picture shapes (the usual ones, and each video's / collection's own).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/equalizer_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/edit_video.dart';
import 'package:hometunes/ui/screens/settings/video_settings.dart';
import 'package:hometunes/ui/screens/video_collection_screen.dart';
import 'package:hometunes/ui/screens/videos_screen.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;
  late VideoLibraryModel videos;
  late EqualizerModel eq;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_video_settings');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
    videos = VideoLibraryModel(storage, lib);
    eq = EqualizerModel(storage);
  });
  tearDown(() async {
    await videos.settle();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    dir.deleteSync(recursive: true);
  });

  Future<void> scan() async {
    final show = Directory(p.join(dir.path, 'vids', 'TV', 'Silo', 'Season 1'))..createSync(recursive: true);
    for (final n in ['Silo S01E01.mkv', 'Silo S01E02.mkv']) {
      File(p.join(show.path, n)).writeAsBytesSync([1]);
    }
    await lib.addVideoFolder(p.join(dir.path, 'vids'));
    await videos.scan();
  }

  test('the settings are saved and come back', () async {
    expect((lib.videoSkipBackSeconds, lib.videoSkipForwardSeconds, lib.defaultVideoSpeed, lib.videoRewindOnResume),
        (10, 10, 1.0, true));
    await lib.updateVideoSettings(
        skipBackSeconds: 5, skipForwardSeconds: 30, defaultSpeed: 1.25, rewindOnResume: false, videoShape: PictureShape.tall);
    final again = LibraryModel(storage);
    await again.load();
    expect((again.videoSkipBackSeconds, again.videoSkipForwardSeconds, again.defaultVideoSpeed, again.videoRewindOnResume),
        (5, 30, 1.25, false));
    expect((again.videoPictureShape, again.collectionPictureShape), (PictureShape.tall, PictureShape.wide));
  });

  test('videos can have their own equaliser preset', () async {
    await eq.load();
    expect((eq.separateVideos, eq.presetForTarget(EqTarget.videos).id), (true, 'flat'));
    await eq.chooseFor(EqTarget.videos, 'bass');
    expect((eq.videoPresetId, eq.musicPresetId, eq.enabled), ('bass', 'flat', true));
    expect(eq.activeForVideos!.id, 'bass');
    // Switched off: videos use (and change) the music preset.
    await eq.setSeparateVideos(false);
    expect(eq.presetForTarget(EqTarget.videos).id, 'flat');
    await eq.chooseFor(EqTarget.videos, 'rock');
    expect((eq.musicPresetId, eq.videoPresetId), ('rock', 'bass'));
    await eq.setSeparateVideos(true);
    final id = await eq.addCustom('Mine');
    await eq.chooseFor(EqTarget.videos, id);
    final again = EqualizerModel(storage);
    await again.load();
    expect((again.separateVideos, again.videoPresetId), (true, id));
    await again.delete(id);
    expect(again.videoPresetId, 'flat');
    // Off: nothing for videos.
    await again.setEnabled(false);
    expect(again.activeForVideos, isNull);
  });

  test('picture shapes and speeds: the usual ones, each video\'s and collection\'s own, kept on rename', () async {
    await scan();
    final c = videos.collections.single;
    final v = c.videos.first;
    expect((videos.shapeOf(v), videos.collectionShapeOf(c), videos.speedFor(c.name)), (PictureShape.wide, PictureShape.wide, 1.0));
    await lib.updateVideoSettings(videoShape: PictureShape.square, defaultSpeed: 1.5);
    expect((videos.shapeOf(v), videos.speedFor(c.name)), (PictureShape.square, 1.5));
    await videos.setShapes([v.id], PictureShape.tall);
    await videos.setCollectionShape(c, PictureShape.tall);
    videos.rememberSpeed('silo', 1.25);
    expect((videos.shapeOf(v), videos.shapeOf(c.videos.last), videos.collectionShapeOf(c)),
        (PictureShape.tall, PictureShape.square, PictureShape.tall));
    await videos.editCollection(c, name: 'Silo (TV)');
    final renamed = videos.collectionNamed('Silo (TV)')!;
    expect((videos.collectionShapeOf(renamed), videos.speedFor('Silo (TV)')), (PictureShape.tall, 1.25));
    await videos.settle();
    final again = VideoLibraryModel(storage, lib);
    addTearDown(again.dispose);
    await again.load();
    expect((again.ownShapeOf(v), again.collectionShapeOf(again.collectionNamed('Silo (TV)')!), again.speedFor('Silo (TV)')),
        (PictureShape.tall, PictureShape.tall, 1.25));
    await videos.setShapes([v.id], null);
    expect(videos.ownShapeOf(v), isNull);
    // Card heights follow the shape.
    expect(videoCardHeight(250, PictureShape.tall), greaterThan(videoCardHeight(250, PictureShape.square)));
    expect(collectionCardHeight(250), lessThan(collectionCardHeight(250, PictureShape.square)));
  });

  Future<void> pump(WidgetTester tester, Widget home, {double height = 1000}) async {
    tester.view.physicalSize = Size(1200, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
        ChangeNotifierProvider.value(value: videos),
        ChangeNotifierProvider.value(value: eq),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: MaterialApp(home: Scaffold(body: home)),
    ));
    await tester.pump();
  }

  testWidgets('Settings › Videos: everything is there, and the Look changes the Videos tab', (tester) async {
    await tester.runAsync(scan);
    // Tall enough for the whole page (it grew with Special season titles, 0.1.66).
    await pump(tester, const VideoSettings(), height: 2000);
    for (final t in ['Skip back', 'Skip forward', 'Speed', 'Rewind a little when carrying on',
      'Separate equaliser for videos', 'Special season titles', 'Video picture shape', 'Collection poster shape']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await tester.runAsync(() async {
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('video-shape-choice')), matching: find.text('Tall')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(lib.videoPictureShape, PictureShape.tall);
    expect(videos.shapeOf(videos.videos.first), PictureShape.tall);
  });

  testWidgets('Edit details: a video\'s own picture shape', (tester) async {
    await tester.runAsync(scan);
    final v = videos.videos.first;
    await pump(tester, Builder(builder: (context) => TextButton(onPressed: () => showEditVideos(context, [v]), child: const Text('go'))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Usual (wide)'), findsOneWidget);
    final square = find.descendant(of: find.byKey(const ValueKey('picture-shape')), matching: find.text('Square'));
    await tester.ensureVisible(square);
    await tester.pumpAndSettle();
    await tester.tap(square);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await videos.settle();
    });
    await tester.pumpAndSettle();
    expect(videos.ownShapeOf(v), PictureShape.square);
  });
}
