// Special seasons (0.1.66): a season marked special gets its own title and a badge, is listed
// after the normal seasons, and Up next / playing on don't run into it. The titles come from a
// list in Settings › Videos.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/screens/special_seasons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

VideoItem _v(String name, int? season, int? episode) =>
    VideoItem(id: 'video:$name', path: '/v/$name.mkv', title: name, collection: 'Show', season: season, episode: episode);

void main() {
  test('order and headings: a special season goes after the normal ones, under its title', () {
    final sorted = sortForCollection([
      _v('s2e1', 2, 1).withSpecial('OVA'),
      _v('s3e1', 3, 1),
      _v('s0e1', 0, 1),
      _v('s1e1', 1, 1),
      _v('extra', null, null),
    ]);
    expect([for (final v in sorted) v.title], ['s1e1', 's3e1', 'extra', 's0e1', 's2e1']);
    final c = VideoCollection(name: 'Show', videos: sorted);
    expect([for (final (h, _) in c.groups) h], ['Season 1', 'Season 3', 'Episodes', 'Specials', 'OVA']);
    expect(VideoLibraryModel.isSpecialGroup(c.groups.last.$2), isTrue);
    expect(VideoLibraryModel.isSpecialGroup(c.groups.first.$2), isFalse);
    // Not saved with the video itself.
    expect(VideoItem.fromJson(_v('a', 2, 1).withSpecial('OVA').toJson()).specialTitle, isNull);
  });

  group('with a library', () {
    late Directory dir;
    late Storage storage;
    late LibraryModel lib;
    late VideoLibraryModel videos;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_special_seasons');
      storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      lib = LibraryModel(storage);
      videos = VideoLibraryModel(storage, lib);
    });
    tearDown(() async {
      await videos.settle();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        try {
          dir.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          // a write still finishing
        }
      }
    });

    Future<VideoCollection> scanShow() async {
      for (final s in [1, 2, 3]) {
        final d = Directory(p.join(dir.path, 'vids', 'TV', 'Show', 'Season $s'))..createSync(recursive: true);
        for (var e = 1; e <= 2; e++) {
          File(p.join(d.path, 'Show S0${s}E0$e.mkv')).writeAsBytesSync([1]);
        }
      }
      await lib.addVideoFolder(p.join(dir.path, 'vids'));
      await videos.scan();
      return videos.collectionNamed('Show')!;
    }

    String heads(VideoCollection c) => [for (final (h, l) in c.groups) '$h:${l.length}'].join(', ');
    VideoItem ep(VideoCollection c, int s, int e) => c.videos.firstWhere((v) => v.season == s && v.episode == e);

    test('mark, play on, Up next, kept in videos.json, and back to normal', () async {
      var c = await scanShow();
      expect(heads(c), 'Season 1:2, Season 2:2, Season 3:2');

      await videos.setSpecialSeason(c, 2, 'OVA');
      c = videos.collectionNamed('Show')!;
      expect(heads(c), 'Season 1:2, Season 3:2, OVA:2');
      expect(videos.specialTitleOf(c, 2), 'OVA');
      expect(videos.groupLabel(c, 'OVA', c.groups.last.$2), 'OVA');

      // Playing on: Season 1 runs into Season 3, and the last normal episode stops.
      expect(videos.after(ep(c, 1, 2))!.season, 3);
      expect(videos.after(ep(c, 3, 2)), isNull);
      // Within the specials it plays on.
      expect(videos.after(ep(c, 2, 1))!.episode, 2);

      // Up next skips it.
      await videos.setWatched([for (final v in c.videos) if (v.season == 1) v.id], true);
      expect(videos.nextUp(c)!.season, 3);
      await videos.setWatched([for (final v in c.videos) if (v.season == 3) v.id], true);
      expect(videos.nextUp(c)!.season, isNot(2));

      // Kept.
      await videos.settle();
      final again = VideoLibraryModel(storage, lib);
      await again.load();
      expect(heads(again.collectionNamed('Show')!), 'Season 1:2, Season 3:2, OVA:2');

      await videos.setSpecialSeason(c, 2, null);
      expect(heads(videos.collectionNamed('Show')!), 'Season 1:2, Season 2:2, Season 3:2');
    });

    test('the list of titles: no blanks or repeats, kept in settings.json', () async {
      expect(lib.specialSeasonTitles, LibraryModel.defaultSpecialSeasonTitles);
      await lib.setSpecialSeasonTitles(['OVA', ' ', 'ova', 'Films']);
      expect(lib.specialSeasonTitles, ['OVA', 'Films']);
      await lib.addSpecialSeasonTitle('Recaps');
      final again = LibraryModel(storage);
      await again.load();
      expect(again.specialSeasonTitles, ['OVA', 'Films', 'Recaps']);
    });

    testWidgets('Mark as special…: pick a title, or type a new one (added to the list)', (tester) async {
      late VideoCollection c;
      await tester.runAsync(() async => c = await scanShow());
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: videos),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(children: [
                TextButton(onPressed: () => showSpecialSeasonDialog(context, c, 2), child: const Text('two')),
                TextButton(onPressed: () => showSpecialSeasonDialog(context, c, 3), child: const Text('three')),
              ]),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('two'));
      await tester.pumpAndSettle();
      expect(find.text('Mark season 2 as special'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('special-title:OVA')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('special-title-save')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(videos.specialTitleOf(c, 2), 'OVA');

      await tester.tap(find.text('three'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('special-title-field')), 'Recap');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('special-title-save')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(videos.specialTitleOf(c, 3), 'Recap');
      expect(lib.specialSeasonTitles, contains('Recap'));
    });

    testWidgets('Settings: remove a title, then reset the list', (tester) async {
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: lib,
        child: const MaterialApp(home: Scaffold(body: SpecialSeasonTitlesSection())),
      ));
      expect(find.text('OVA'), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('special-title-chip:OVA')), matching: find.byTooltip('Delete')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(lib.specialSeasonTitles, isNot(contains('OVA')));
      await tester.tap(find.text('Reset'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(lib.specialSeasonTitles, LibraryModel.defaultSpecialSeasonTitles);
    });
  });
}
