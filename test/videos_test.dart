// Tests for the Videos tab (0.1.32): finding videos in the video folders (every format), titles
// and years from file names, the user's edits (one video or several), watched places and
// carrying on, the tab's search / chips / filters / sorts, an .mp4 in a video folder being a video rather
// than a song, backups, and the Videos tab and its editor on screen. The "videos" here are small
// made-up files: nothing is played (there's no video engine in tests).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/video_scanner.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/music_filters.dart';
import 'package:hometunes/state/video_filters.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/videos_screen.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'music_video_test.dart' show fakeMp4;

VideoItem _v(String name, {String collection = 'Films', int? year, int? addedMs, Duration duration = Duration.zero}) =>
    VideoItem(
      id: VideoItem.idFor('/v/$name'),
      path: '/v/$name',
      title: name,
      collection: collection,
      year: year,
      addedMs: addedMs,
      duration: duration,
    );

void main() {
  group('names and years from file names', () {
    test('dots and underscores become spaces, and a year is taken out', () {
      expect(videoNameFromFile('My.Film.2019.1080p.BluRay'), (title: 'My Film', year: 2019));
      expect(videoNameFromFile('Home_Movie_(2004)'), (title: 'Home Movie', year: 2004));
      expect(videoNameFromFile('Holiday day 1'), (title: 'Holiday day 1', year: null));
      expect(videoNameFromFile('2019'), (title: '2019', year: null)); // just a number: kept as the title
    });
  });

  group('scanning', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_videos_scan'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('every video format in every subfolder, grouped by folder name; other files ignored', () async {
      final season = Directory(p.join(dir.path, 'Season 1'))..createSync();
      for (final name in ['01 Pilot.mkv', '02 Second.avi', 'clip.WEBM']) {
        File(p.join(season.path, name)).writeAsBytesSync([0, 1, 2]);
      }
      File(p.join(dir.path, 'Film.2012.mp4')).writeAsBytesSync(fakeMp4());
      File(p.join(dir.path, 'notes.txt')).writeAsStringSync('not a video');
      File(p.join(dir.path, 'song.mp3')).writeAsBytesSync([0]);

      final videos = await VideoScanner().scan([dir.path], now: 1000);
      expect([for (final v in videos) p.basename(v.path)], ['Film.2012.mp4', '01 Pilot.mkv', '02 Second.avi', 'clip.WEBM']);
      final byName = {for (final v in videos) p.basename(v.path): v};
      expect(byName['01 Pilot.mkv']!.collection, 'Season 1');
      expect(byName['Film.2012.mp4']!.collection, p.basename(dir.path));
      expect(byName['Film.2012.mp4']!.title, 'Film');
      expect(byName['Film.2012.mp4']!.year, 2012);
      expect(byName['clip.WEBM']!.format, 'WEBM');
      expect(videos.every((v) => v.addedMs == 1000), isTrue);
    });

    test('an unchanged file is reused as it was (thumbnail, length and "added" kept)', () async {
      final f = File(p.join(dir.path, 'a.mkv'))..writeAsBytesSync([1]);
      final first = await VideoScanner().scan([dir.path], now: 1000);
      final known = first.single.copyWith(thumb: '/art/video/x.jpg', duration: const Duration(minutes: 3));
      final again = await VideoScanner().scan([dir.path], previous: {known.id: known}, now: 2000);
      expect(again.single.thumb, '/art/video/x.jpg');
      expect(again.single.duration, const Duration(minutes: 3));
      expect(again.single.addedMs, 1000);
      // Changed file: read again (no thumbnail yet), but still "added" when first found.
      f.writeAsBytesSync([1, 2, 3]);
      f.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
      final changed = await VideoScanner().scan([dir.path], previous: {known.id: known}, now: 3000);
      expect(changed.single.thumb, isNull);
      expect(changed.single.addedMs, 1000);
    });
  });

  group('edits', () {
    const film = VideoItem(id: 'video:/v/f.mkv', path: '/v/f.mkv', title: 'f', collection: 'v', year: 2001, genre: 'Drama');

    test('only what differs from the file is kept; emptied details are remembered', () {
      final e = VideoEdit.fromForm(film, title: 'The Film', collection: 'v', year: null, genre: '', description: 'Lovely');
      expect(e.title, 'The Film');
      expect(e.collection, isNull); // same as the file
      expect(e.cleared, {'year', 'genre'});
      final shown = e.applyTo(film);
      expect(shown.title, 'The Film');
      expect(shown.year, isNull);
      expect(shown.genre, isNull);
      expect(shown.description, 'Lovely');
      expect(VideoEdit.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>).applyTo(film).title, 'The Film');
      expect(VideoEdit.fromForm(film, title: 'f', collection: 'v', year: 2001, genre: 'Drama', description: '').isEmpty, isTrue);
    });
  });

  group('the tab\'s lists', () {
    test('search needs every word, in title, collection, genre or year', () {
      final list = [_v('Alien', collection: 'Sci-fi', year: 1979), _v('Aliens', collection: 'Sci-fi', year: 1986), _v('Up')];
      expect(searchVideos(list, 'alien 1986').map((v) => v.title), ['Aliens']);
      expect(searchVideos(list, 'sci').length, 2);
      expect(searchVideos(list, '  ').length, 3);
    });

    test('by collection: groups A–Z, titles in order (numbered episodes line up)', () {
      final list = [_v('02 B', collection: 'Show'), _v('01 A', collection: 'Show'), _v('Z', collection: 'Films')];
      final groups = sortVideos(list, VideoSort.collection);
      expect([for (final (h, _) in groups) h], ['Films', 'Show']);
      expect(groups.last.$2.map((v) => v.title), ['01 A', '02 B']);
    });

    test('by year: newest first, unknown years last', () {
      final groups = sortVideos([_v('a', year: 1999), _v('b'), _v('c', year: 2020)], VideoSort.year);
      expect([for (final (h, _) in groups) h], ['2020', '1999', 'Year not known']);
    });

    test('recently added, recently watched and longest', () {
      final a = _v('a', addedMs: 1, duration: const Duration(minutes: 90));
      final b = _v('b', addedMs: 2, duration: const Duration(minutes: 5));
      expect(sortVideos([a, b], VideoSort.recentlyAdded).single.$2.first, b);
      expect(sortVideos([b, a], VideoSort.longest).single.$2.first, a);
      final places = {a.id: const VideoPlace(position: Duration(minutes: 1), updatedMs: 50)};
      expect(sortVideos([b, a], VideoSort.recentlyWatched, places: places).single.$2.first, a);
    });

    test('chips, carrying on and "watched" near the end', () {
      const started = VideoPlace(position: Duration(minutes: 10), updatedMs: 1);
      const done = VideoPlace(position: Duration(minutes: 10), watched: true, updatedMs: 1);
      expect(videoShown(VideoShow.continueWatching, started), isTrue);
      expect(videoShown(VideoShow.continueWatching, done), isFalse);
      expect(videoShown(VideoShow.unwatched, null), isTrue);
      expect(videoShown(VideoShow.watched, done), isTrue);
      const hour = Duration(hours: 1);
      expect(resumeAt(started, hour), const Duration(minutes: 10));
      expect(resumeAt(const VideoPlace(position: Duration(seconds: 2), updatedMs: 1), hour), Duration.zero);
      expect(resumeAt(const VideoPlace(position: Duration(minutes: 59, seconds: 50), updatedMs: 1), hour), Duration.zero);
      expect(isNearEnd(const Duration(minutes: 58), hour), isTrue); // last 5 %
      expect(isNearEnd(const Duration(minutes: 30), hour), isFalse);
      expect(isNearEnd(const Duration(seconds: 50), const Duration(minutes: 1)), isTrue); // last 20 s
    });
  });

  group('filters', () {
    VideoItem sized(String name, {int? w, int? h, Duration d = Duration.zero, String? genre, int? year}) => VideoItem(
          id: VideoItem.idFor('/v/$name'),
          path: '/v/$name',
          title: name,
          collection: name.startsWith('ep') ? 'Show' : 'Films',
          width: w,
          height: h,
          duration: d,
          genre: genre,
          year: year,
        );

    test('length and picture groups', () {
      expect(videoLengthGroup(Duration.zero), isNull);
      expect(videoLengthGroup(const Duration(minutes: 4)), 'Under 10 minutes');
      expect(videoLengthGroup(const Duration(minutes: 45)), '30–60 minutes');
      expect(videoLengthGroup(const Duration(minutes: 95)), '1–2 hours');
      expect(videoLengthGroup(const Duration(hours: 3)), 'Over 2 hours');
      expect(videoQuality(sized('a', w: 3840, h: 2160)), '4K');
      expect(videoQuality(sized('b', w: 3840, h: 1406)), '4K'); // a wide film
      expect(videoQuality(sized('c', w: 1920, h: 1080)), '1080p');
      expect(videoQuality(sized('d', w: 1080, h: 1920)), '1080p'); // a phone video held upright
      expect(videoQuality(sized('e', w: 1280, h: 720)), '720p');
      expect(videoQuality(sized('f', w: 640, h: 480)), 'SD');
      expect(videoQuality(sized('g')), isNull);
    });

    test('choices come with counts, lengths shortest first, each narrowed by the other picks', () {
      final list = [
        sized('ep1.mkv', d: const Duration(minutes: 40), w: 1920, h: 1080, genre: 'Comedy', year: 1999),
        sized('ep2.mkv', d: const Duration(minutes: 40), w: 1280, h: 720, genre: 'Comedy', year: 2001),
        sized('film.mp4', d: const Duration(hours: 2, minutes: 10), w: 3840, h: 2160, genre: 'Drama', year: 2019),
        sized('clip.webm', d: const Duration(minutes: 3)),
      ];
      FilterField<VideoItem> field(String label) => videoFilterFields.firstWhere((f) => f.label == label);
      expect(MusicFilters.none.choices(list, videoFilterFields, field('Length')).keys,
          ['Under 10 minutes', '30–60 minutes', 'Over 2 hours']);
      expect(MusicFilters.none.choices(list, videoFilterFields, field('Picture')), {'4K': 1, '1080p': 1, '720p': 1});
      expect(MusicFilters.none.choices(list, videoFilterFields, field('Decade')).keys, ['1990s', '2000s', '2010s']);
      expect(MusicFilters.none.choices(list, videoFilterFields, field('File type')).keys.toSet(), {'MKV', 'MP4', 'WEBM'});

      final comedy = const MusicFilters().withValue('Genre', 'Comedy');
      expect(filterVideos(list, comedy).map((v) => v.title), ['ep1.mkv', 'ep2.mkv']);
      expect(comedy.choices(list, videoFilterFields, field('Collection')), {'Show': 2});
      final both = comedy.withValue('Picture', '720p');
      expect(filterVideos(list, both).single.title, 'ep2.mkv');
      expect(filterVideos(list, MusicFilters.none), hasLength(4));
    });
  });

  group('VideoLibraryModel', () {
    late Directory dir, videosDir;
    late Storage storage;
    late LibraryModel lib;
    late VideoLibraryModel model;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('hometunes_videos_model');
      videosDir = Directory(p.join(dir.path, 'videos'))..createSync();
      File(p.join(videosDir.path, 'Beach.mkv')).writeAsBytesSync([1]);
      File(p.join(videosDir.path, 'Party.mp4')).writeAsBytesSync(fakeMp4());
      storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      lib = LibraryModel(storage);
      model = VideoLibraryModel(storage, lib);
    });
    tearDown(() async {
      await model.settle();
      model.dispose();
      dir.deleteSync(recursive: true);
    });

    test('adding a video folder scans it; edits and places are saved and come back', () async {
      await lib.addVideoFolder(videosDir.path);
      await model.scan();
      expect(model.videos.map((v) => v.title), ['Beach', 'Party']);
      final beach = model.videos.first;

      await model.setEdit(beach.id, const VideoEdit(title: 'Beach day', collection: 'Holiday 2024'));
      model.savePlace(beach.id, const Duration(minutes: 2), const Duration(minutes: 10));
      await model.flushPendingSaves();
      expect(model.byId(beach.id)!.title, 'Beach day');
      expect(model.continueWatching.single.id, beach.id);
      expect(model.byId(beach.id)!.duration, const Duration(minutes: 10)); // learned while playing

      final lib2 = LibraryModel(storage);
      await lib2.load();
      expect(lib2.videoFolders, [videosDir.path]);
      final again = VideoLibraryModel(storage, lib2);
      addTearDown(again.dispose);
      await again.load();
      expect(again.byId(beach.id)!.collection, 'Holiday 2024');
      expect(again.placeOf(beach.id)!.position, const Duration(minutes: 2));
      expect(again.rawById(beach.id)!.title, 'Beach'); // the file's own details are kept apart
    });

    test('watched near the end; marking not watched starts again', () async {
      await lib.addVideoFolder(videosDir.path);
      await model.scan();
      final id = model.videos.first.id;
      model.savePlace(id, const Duration(minutes: 9, seconds: 50), const Duration(minutes: 10));
      expect(model.placeOf(id)!.watched, isTrue);
      await model.setWatched([id], false);
      expect(model.placeOf(id)!.watched, isFalse);
      expect(model.placeOf(id)!.position, Duration.zero);
    });

    test('several at once: only typed details change, each keeps its own title', () async {
      await lib.addVideoFolder(videosDir.path);
      await model.scan();
      final [a, b] = model.videos;
      await model.setEdit(a.id, const VideoEdit(title: 'Own title'));
      await model.setEdits({
        a.id: VideoEdit(title: model.editOf(a.id)?.title, genre: 'Family'),
        b.id: const VideoEdit(genre: 'Family'),
      });
      expect(model.byId(a.id)!.title, 'Own title');
      expect(model.videos.every((v) => v.genre == 'Family'), isTrue);
    });

    test('removing the folder drops its videos at once; a folder that can\'t be reached keeps them', () async {
      await lib.addVideoFolder(videosDir.path);
      await model.scan();
      expect(model.videos, hasLength(2));
      model.folderReachable = (_) async => false;
      await model.scan();
      expect(model.videos, hasLength(2));
      expect(model.offlineFolders, [videosDir.path]);
      await lib.removeVideoFolder(videosDir.path);
      expect(model.videos, isEmpty);
    });

    test('an .mp4 in a video folder is a video, not a song', () async {
      final music = Directory(p.join(dir.path, 'music'))..createSync();
      File(p.join(music.path, 'Song.mp4')).writeAsBytesSync(fakeMp4());
      File(p.join(videosDir.path, 'Song2.mp4')).writeAsBytesSync(fakeMp4());
      await lib.addFolder(music.path);
      await lib.addFolder(videosDir.path); // the same folder as music and video
      expect(lib.tracks.map((t) => p.basename(t.path!)).toSet(), {'Song.mp4', 'Party.mp4', 'Song2.mp4'});
      await lib.addVideoFolder(videosDir.path);
      expect(lib.tracks.map((t) => p.basename(t.path!)).toSet(), {'Song.mp4'});
    });

    test('only files inside a video folder are played', () async {
      await lib.addVideoFolder(videosDir.path);
      await model.scan();
      expect(model.playableFile(model.videos.first), isNotNull);
      const outside = VideoItem(id: 'video:/etc/x.mp4', path: '/etc/x.mp4', title: 'x', collection: 'etc');
      expect(model.playableFile(outside), isNull);
    });

    test('backups: video folders, edits and the latest places come back; stray thumbnails are dropped', () async {
      await lib.addVideoFolder(videosDir.path);
      await model.scan();
      final id = model.videos.first.id;
      await model.setEdit(id, const VideoEdit(title: 'Backed up'));
      model.savePlace(id, const Duration(minutes: 3), const Duration(minutes: 10));
      await model.flushPendingSaves();
      expect(AppBackup.dataFiles, contains('videos.json'));
      final bytes = await AppBackup.create(storage);

      // A fresh device with the same folder, restored by replacing.
      final other = Storage.at(Directory(p.join(dir.path, 'other'))..createSync());
      await AppBackup.restore(other, AppBackup.read(bytes), merge: false);
      final lib2 = LibraryModel(other);
      await lib2.load();
      expect(lib2.videoFolders, [videosDir.path]);
      final m2 = VideoLibraryModel(other, lib2);
      addTearDown(m2.dispose);
      await m2.load();
      expect(m2.byId(id)!.title, 'Backed up');
      expect(m2.placeOf(id)!.position, const Duration(minutes: 3));

      // Merging keeps the newer place and drops a thumbnail outside the art folder.
      final contents = AppBackup.read(bytes);
      final vj = contents.files['videos.json'] as Map;
      (vj['videos'] as List).first['thumb'] = '/somewhere/else.jpg';
      final kept = AppBackup.sanitize('videos.json', Map<String, dynamic>.from(vj), other.root.path);
      expect((kept['videos'] as List).first.containsKey('thumb'), isFalse);
    });
  });

  group('on screen', () {
    late Directory dir;
    late LibraryModel lib;
    late VideoLibraryModel model;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_videos_ui');
      final storage = Storage.at(dir);
      lib = LibraryModel(storage);
      model = VideoLibraryModel(storage, lib);
    });
    tearDown(() async {
      await model.settle();
      dir.deleteSync(recursive: true);
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: model),
          ChangeNotifierProvider(create: (_) => AppNav()),
        ],
        child: const MaterialApp(home: VideosScreen()),
      ));
      await tester.pump();
    }

    testWidgets('no video folders: says so, with a way to add one', (tester) async {
      await pump(tester);
      expect(find.text('No videos yet'), findsOneWidget);
      expect(find.text('Add a video folder'), findsOneWidget);
    });

    testWidgets('videos in a grid by collection, with chips; editing from the menu', (tester) async {
      final vids = Directory(p.join(dir.path, 'vids'))..createSync();
      final show = Directory(p.join(vids.path, 'Show'))..createSync();
      File(p.join(show.path, '01 Start.mkv')).writeAsBytesSync([1]);
      File(p.join(vids.path, 'Film.avi')).writeAsBytesSync([1]);
      await tester.runAsync(() async {
        await lib.addVideoFolder(vids.path);
        await model.scan();
      });
      await pump(tester);
      expect(find.text('01 Start'), findsOneWidget);
      expect(find.text('Film'), findsOneWidget);
      expect(find.text('Show'), findsWidgets); // a group heading
      expect(find.text('All (2)'), findsOneWidget);
      expect(find.text('Continue watching (0)'), findsOneWidget);

      // ⋮ → Edit details… → change the title.
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit details…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('video-title')), 'The very first one');
      // Saving writes videos.json, which needs real time to finish.
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await model.settle();
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.widgetWithText(VideoCard, 'The very first one'), findsOneWidget);

      // Filter: only the "Show" collection; then remove the filter with its ×.
      await tester.tap(find.byTooltip('Filter by collection, genre, decade, length, picture or file type'));
      await tester.pumpAndSettle();
      expect(find.text('Show only'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('filter-Collection')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show  (1)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show videos'));
      await tester.pumpAndSettle();
      expect(find.byType(VideoCard), findsOneWidget);
      expect(find.text('Collection: Show'), findsOneWidget);
      expect(find.text('All (1)'), findsOneWidget);
      tester.widget<InputChip>(find.byKey(const ValueKey('video-filter:Collection'))).onDeleted!();
      await tester.pumpAndSettle();
      expect(find.byType(VideoCard), findsNWidgets(2));
    });
  });
}
