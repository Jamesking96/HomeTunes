// Season sub numbers (30 Sep): "Season 1.2" folders, S1.2 E3 labels, their place in a
// collection, Edit details' "1.2", and a sub season's own title.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/video_names.dart';
import 'package:hometunes/services/video_nfo.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_filters.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/edit_video.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

VideoItem _v(String name, int? season, int? episode, [int? sub]) => VideoItem(
      id: 'video:$name',
      path: '/v/$name.mkv',
      title: name,
      collection: 'Show',
      season: season,
      episode: episode,
      subSeason: sub,
    );

void main() {
  test('folders: the sub number, the season and the title', () {
    expect(subSeasonOfFolder('Season 1.2'), 2);
    expect(subSeasonOfFolder('S01.1'), 1);
    expect(subSeasonOfFolder('Series 3.10 - Finale'), 10);
    expect(subSeasonOfFolder('Season 1'), isNull);
    expect(subSeasonOfFolder('Ghosts.2021.S01.1080p.WEB'), isNull);
    expect(subSeasonOfFolder('Show.S01.2160p'), isNull);
    expect(seasonOfFolder('Season 1.2'), 1);
    expect(seasonTitleOfFolder('Season 1.2 - Outside'), 'Outside');
    expect(seasonTitleOfFolder('Season 1.2'), isNull);

    final info = describeVideoPath('/v', '/v/TV/Show/Season 1.2 - Outside/Show S01E03.mkv');
    expect((info.collection, info.season, info.subSeason, info.episode, info.seasonTitle), ('Show', 1, 2, 3, 'Outside'));
    // The video folder is the show itself.
    final own = describeVideoPath('/v/Show', '/v/Show/Season 1.1/Show S01E01.mkv');
    expect((own.collection, own.season, own.subSeason), ('Show', 1, 1));
    // An episode numbered for another season doesn't take the folder's sub number.
    expect(describeVideoPath('/v', '/v/TV/Show/Season 1.2/Show S02E01.mkv').subSeason, isNull);
  });

  test('labels, order and headings: Season 1, 1.1, 1.2, then 2', () {
    expect(_v('a', 1, 3, 2).episodeLabel, 'S1.2 E3');
    expect(_v('a', 1, 3).episodeLabel, 'S1 E3');
    final sorted = sortForCollection([
      _v('two', 2, 1),
      _v('onePointTwo', 1, 1, 2),
      _v('one', 1, 2),
      _v('onePointOne', 1, 1, 1),
    ]);
    expect([for (final v in sorted) v.title], ['one', 'onePointOne', 'onePointTwo', 'two']);
    final c = VideoCollection(name: 'Show', videos: sorted);
    expect([for (final (h, _) in c.groups) h], ['Season 1', 'Season 1.1', 'Season 1.2', 'Season 2']);
    final all = sortVideos(sorted, VideoSort.season);
    expect([for (final (h, _) in all) h], ['Show · Season 1', 'Show · Season 1.1', 'Show · Season 1.2', 'Show · Season 2']);
  });

  test('editing: "1.2" sets the sub number, "1" takes it away, and it survives saving', () {
    final plain = _v('a', 1, 3);
    final toSub = VideoEdit.fromForm(plain,
        title: 'a', collection: 'Show', year: null, genre: '', description: '', season: 1, subSeason: 2, episode: 3,
        seasonKnown: true);
    expect(toSub.subSeason, 2);
    expect(toSub.season, isNull); // the season number itself didn't change
    expect(toSub.applyTo(plain).seasonLabel, '1.2');
    expect(VideoEdit.fromJson(toSub.toJson()).subSeason, 2);

    final sub = _v('b', 1, 3, 2);
    final back = VideoEdit.fromForm(sub,
        title: 'b', collection: 'Show', year: null, genre: '', description: '', season: 1, episode: 3, seasonKnown: true);
    expect(back.cleared, contains('subSeason'));
    expect(back.applyTo(sub).seasonLabel, '1');
    // Emptying the season takes the sub number with it.
    final none = VideoEdit.fromForm(sub,
        title: 'b', collection: 'Show', year: null, genre: '', description: '', seasonKnown: true);
    expect(none.applyTo(sub).subSeason, isNull);
    // Several videos: "2" given to a 1.2 one drops its sub number.
    final several = const VideoEdit().merge(season: 2, clear: {'subSeason'});
    expect(several.applyTo(sub).seasonLabel, '2');
    expect(VideoItem.fromJson(sub.toJson()).subSeason, 2);
  });

  group('with a library', () {
    late Directory dir;
    late Storage storage;
    late LibraryModel lib;
    late VideoLibraryModel videos;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_sub_seasons');
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

    Future<void> scanShow() async {
      for (final (folder, s) in [('Season 1', 1), ('Season 1.1 - Part Two', 1), ('Season 2', 2)]) {
        final d = Directory(p.join(dir.path, 'vids', 'TV', 'Show', folder))..createSync(recursive: true);
        for (var e = 1; e <= 2; e++) {
          File(p.join(d.path, 'Show S0${s}E0$e.mkv')).writeAsBytesSync([1]);
        }
      }
      await lib.addVideoFolder(p.join(dir.path, 'vids'));
      await videos.scan();
    }

    test('scanned into Season 1, 1.1 and 2; a sub season has its own title, kept apart from .nfo', () async {
      await scanShow();
      final c = videos.collectionNamed('Show')!;
      expect([for (final (h, l) in c.groups) '$h:${l.length}'], ['Season 1:2', 'Season 1.1:2', 'Season 2:2']);
      final part = c.groups[1].$2;
      expect(videos.groupLabel(c, 'Season 1.1', part), 'Season 1.1 – Part Two');
      expect(videos.seasonTitleOf(c, 1), isNull); // season 1 itself has no title

      final errors = await videos.setSeasonTitle(c, 1, 'The Return', sub: 1, writeNfo: true);
      expect(errors, isEmpty);
      expect(videos.seasonTitleOf(c, 1, 1), 'The Return');
      expect(videos.seasonTitleOf(c, 1), isNull);
      expect(videos.folderSeasonTitle(c, 1, 1), 'Part Two');
      // .nfo files can't hold sub seasons, so nothing was written.
      expect(File(p.join(dir.path, 'vids', 'TV', 'Show', showNfoName)).existsSync(), isFalse);

      await videos.settle();
      final again = VideoLibraryModel(storage, lib);
      await again.load();
      expect(again.seasonTitleOf(again.collectionNamed('Show')!, 1, 1), 'The Return');
      await again.settle();
    });

    testWidgets('Edit details takes "1.2" and rejects "1.x"', (tester) async {
      await tester.runAsync(scanShow);
      final v = videos.collectionNamed('Show')!.videos.first;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: videos),
          ChangeNotifierProvider(create: (_) => AppNav()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) => TextButton(onPressed: () => showEditVideos(context, [v]), child: const Text('go'))),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('video-season')), '1.x');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('A number, like 2 or 1.2'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('video-season')), '1.3');
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(videos.byId(v.id)!.seasonLabel, '1.3');
      expect(videos.collectionNamed('Show')!.groups.map((g) => g.$1), contains('Season 1.3'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    });
  });
}
