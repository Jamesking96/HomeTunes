// A collection's page: each season folds up from its heading, and the contents chips (pinned at
// the top) jump straight to a season, opening it if it was folded.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/video_collection_screen.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late LibraryModel lib;
  late VideoLibraryModel videos;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_collection_page');
    final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
    videos = VideoLibraryModel(storage, lib);
  });
  tearDown(() async {
    await videos.settle();
    dir.deleteSync(recursive: true);
  });

  testWidgets('seasons fold up, and the contents chips jump to one', (tester) async {
    final show = p.join(dir.path, 'vids', 'TV', 'Silo');
    for (var s = 1; s <= 3; s++) {
      final season = Directory(p.join(show, 'Season $s'))..createSync(recursive: true);
      for (var e = 1; e <= 8; e++) {
        File(p.join(season.path, 'Silo S0${s}E${e.toString().padLeft(2, '0')}.mkv')).writeAsBytesSync([1]);
      }
    }
    File(p.join((Directory(p.join(show, 'Extras'))..createSync()).path, 'Behind the scenes.mkv')).writeAsBytesSync([1]);
    await tester.runAsync(() async {
      await lib.addVideoFolder(p.join(dir.path, 'vids'));
      await videos.scan();
    });
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
        ChangeNotifierProvider.value(value: videos),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: const MaterialApp(home: VideoCollectionScreen(name: 'Silo')),
    ));
    await tester.pumpAndSettle();

    // A chip for each season and the extras.
    for (final h in ['Season 1', 'Season 2', 'Season 3', 'Extras']) {
      expect(find.byKey(ValueKey('contents-$h')), findsOneWidget, reason: h);
    }
    expect(find.textContaining('S1 E1'), findsOneWidget);

    // Fold Season 1: its episodes go.
    await tester.tap(find.byKey(const ValueKey('heading-Season 1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('S1 E1', findRichText: true), findsNothing);

    // Jump to Season 3: it's brought up under the contents bar.
    await tester.tap(find.byKey(const ValueKey('contents-Season 3')));
    await tester.pumpAndSettle();
    final heading = tester.getTopLeft(find.byKey(const ValueKey('heading-Season 3')));
    final bar = tester.getBottomLeft(find.byKey(const ValueKey('contents-Season 3')));
    expect(heading.dy, closeTo(bar.dy + 10, 12)); // just under the bar
    expect(find.textContaining('S3 E1', findRichText: true), findsOneWidget);

    // A folded season opens when its chip is tapped.
    await tester.tap(find.byKey(const ValueKey('contents-Season 1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('S1 E1', findRichText: true), findsOneWidget);

    // Fold all / Open all.
    await tester.tap(find.byKey(const ValueKey('fold-all')));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'S\d E\d'), findRichText: true), findsNothing);
    expect(find.text('Open all'), findsOneWidget);
  });
}
