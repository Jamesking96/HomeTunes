// 0.1.32: the video player's look (Settings › Appearance › Video player), season titles
// ("Season 1 – Offline News"), sorting All videos by season, and ticking videos in a collection.
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/models/video_player_look.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/video_names.dart';
import 'package:hometunes/services/video_nfo.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_filters.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/settings/video_player_look_settings.dart';
import 'package:hometunes/ui/screens/video_collection_screen.dart';
import 'package:hometunes/ui/screens/videos_screen.dart';
import 'package:hometunes/ui/widgets/video_controls_look.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

VideoItem _v(String name, {String collection = 'Silo', int? season, int? episode, String? seasonTitle}) => VideoItem(
  id: 'video:$name',
  path: '/v/$name.mkv',
  title: name,
  collection: collection,
  season: season,
  episode: episode,
  seasonTitle: seasonTitle,
);

void main() {
  group('video player look', () {
    test('colours resolve, and the backing is the opposite shade to the buttons', () {
      const accent = Color(0xFFFF7A59);
      expect(resolveLookColour('white', accent), Colors.white);
      expect(resolveLookColour('accent', accent), accent);
      expect(resolveLookColour('#112233', accent), const Color(0xFF112233));
      expect(resolveLookColour('nonsense', accent), Colors.white);
      const light = VideoPlayerLook();
      expect(light.backingColour(accent).computeLuminance(), lessThan(0.1)); // dark behind white
      final dark = light.copyWith(buttonColour: 'black');
      expect(dark.backingColour(accent).computeLuminance(), greaterThan(0.5)); // light behind black
    });

    test('saved and read back; bad values fall back', () {
      const look = VideoPlayerLook(
        buttonColour: '#00FF00',
        size: VideoButtonSize.large,
        backing: VideoButtonBacking.circle,
        backingStrength: 0.7,
        seekColour: 'red',
      );
      expect(VideoPlayerLook.fromJson(look.toJson()), look);
      final bad = VideoPlayerLook.fromJson({'buttonColour': 'url(x)', 'size': 'huge', 'backingStrength': 9});
      expect(bad.buttonColour, 'white');
      expect(bad.size, VideoButtonSize.normal);
      expect(bad.backingStrength, 0.9);
      expect(VideoPlayerLook.fromJson('nope'), VideoPlayerLook.standard);
    });

    test('the theme data carries the look (normal and full screen use the same)', () {
      const look = VideoPlayerLook(buttonColour: 'black', size: VideoButtonSize.large, seekColour: 'white');
      final t = desktopControlsTheme(look, Colors.orange, bar: [const Icon(Icons.abc), const Spacer()]);
      expect(t.buttonBarButtonColor, Colors.black);
      expect(t.buttonBarButtonSize, 36);
      expect(t.seekBarPositionColor, Colors.white);
      expect(t.bottomButtonBar.first, isA<ButtonBacking>());
      expect(t.bottomButtonBar.last, isA<Spacer>()); // left bare for the Row
    });
  });

  group('season titles from folders', () {
    test('the title after the season number', () {
      expect(seasonTitleOfFolder('Season 1 - Offline News'), 'Offline News');
      expect(seasonTitleOfFolder('Book Two - Earth'), 'Earth');
      expect(seasonTitleOfFolder('S02 - The Return'), 'The Return');
      expect(seasonTitleOfFolder('Season 01'), isNull);
      expect(seasonTitleOfFolder('1c. Season 2 (2009)'), isNull);
      expect(seasonTitleOfFolder('Ghosts.2021.S01.1080p.WEB'), isNull);
      expect(seasonTitleOfFolder('Season 3 Episodes 1-10'), isNull);
    });

    test('a video in such a folder gets it; the season number still comes through', () {
      final info = describeVideoPath(r'/v', '/v/TV/Silo/Season 1 - Offline News/Silo S01E02.mkv');
      expect(info.collection, 'Silo');
      expect(info.season, 1);
      expect(info.seasonTitle, 'Offline News');
      // The video folder is the show itself.
      final own = describeVideoPath('/v/Silo', '/v/Silo/Season 2 - Outside/Silo S02E01.mkv');
      expect(own.collection, 'Silo');
      expect(own.seasonTitle, 'Outside');
    });

    test('tvshow.nfo <namedseason>: read, and one season replaced without touching the others', () {
      const xml =
          '<tvshow>\n  <title>Silo</title>\n  <namedseason number="1">Offline</namedseason>\n'
          '  <namedseason number="2">Outside</namedseason>\n</tvshow>\n';
      expect(parseNfo(xml).namedSeasons, {1: 'Offline', 2: 'Outside'});
      final updated = updateNfo(xml, 'tvshow', {namedSeasonKey(1): 'Offline News'});
      expect(parseNfo(updated).namedSeasons, {1: 'Offline News', 2: 'Outside'});
      final removed = updateNfo(updated, 'tvshow', {namedSeasonKey(2): null});
      expect(parseNfo(removed).namedSeasons, {1: 'Offline News'});
      final added = updateNfo(removed, 'tvshow', {namedSeasonKey(3): 'Rising'});
      expect(parseNfo(added).namedSeasons[3], 'Rising');
      expect(parseNfo(added).title, 'Silo');
    });
  });

  test('All videos › Season: each collection split by season, titles in the headings', () {
    final groups = sortVideos([
      _v('b2', season: 2, episode: 1),
      _v('b1', season: 1, episode: 2, seasonTitle: 'Offline News'),
      _v('a1', season: 1, episode: 1, seasonTitle: 'Offline News'),
      _v('Film', collection: 'Arrival'),
    ], VideoSort.season);
    expect([for (final (h, _) in groups) h], ['Arrival', 'Silo · Season 1 – Offline News', 'Silo · Season 2']);
    expect([for (final v in groups[1].$2) v.title], ['a1', 'b1']);
    final own = sortVideos(
      [_v('a1', season: 1, episode: 1), _v('b2', season: 2, episode: 1)],
      VideoSort.season,
      groupLabel: (c, h, l) => '$h!',
    );
    expect(own.first.$1, 'Silo · Season 1!');
  });

  group('with a library', () {
    late Directory dir;
    late Storage storage;
    late LibraryModel lib;
    late VideoLibraryModel videos;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_look_seasons');
      storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      lib = LibraryModel(storage);
      videos = VideoLibraryModel(storage, lib);
    });
    tearDown(() async {
      await videos.settle();
      // A write started inside a widget test can still hold a file for a moment on Windows.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        try {
          dir.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          // try again
        }
      }
    });

    Future<void> scanSilo() async {
      for (final (s, name) in [(1, 'Season 1 - Offline News'), (2, 'Season 2')]) {
        final season = Directory(p.join(dir.path, 'vids', 'TV', 'Silo', name))..createSync(recursive: true);
        for (var e = 1; e <= 3; e++) {
          File(p.join(season.path, 'Silo S0${s}E0$e.mkv')).writeAsBytesSync([1]);
        }
      }
      await lib.addVideoFolder(p.join(dir.path, 'vids'));
      await videos.scan();
    }

    Widget app(Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
        ChangeNotifierProvider.value(value: videos),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: MaterialApp(home: home),
    );

    test('the look is saved in settings.json', () async {
      await lib.setVideoPlayerLook(const VideoPlayerLook(backing: VideoButtonBacking.circle, buttonColour: 'accent'));
      final again = LibraryModel(storage);
      await again.load();
      expect(again.videoPlayerLook.backing, VideoButtonBacking.circle);
      expect(again.videoPlayerLook.buttonColour, 'accent');
    });

    test('season titles: from the folder, the user\'s own wins and is kept, and tvshow.nfo gets it', () async {
      await scanSilo();
      final c = videos.collectionNamed('Silo')!;
      expect(videos.seasonTitleOf(c, 1), 'Offline News');
      expect(videos.seasonTitleOf(c, 2), isNull);
      expect(videos.groupLabel(c, 'Season 1', c.groups.first.$2), 'Season 1 – Offline News');

      final errors = await videos.setSeasonTitle(c, 2, 'Outside', writeNfo: true);
      expect(errors, isEmpty);
      await videos.setSeasonTitle(c, 1, ''); // no title, on purpose
      expect(videos.seasonTitleOf(c, 2), 'Outside');
      expect(videos.seasonTitleOf(c, 1), isNull);
      expect(videos.folderSeasonTitle(c, 1), 'Offline News');
      final nfo = readNfo(p.join(dir.path, 'vids', 'TV', 'Silo', showNfoName))!;
      expect(nfo.namedSeasons, {2: 'Outside'});

      await videos.settle();
      final again = VideoLibraryModel(storage, lib);
      await again.load();
      final c2 = again.collectionNamed('Silo')!;
      expect(again.seasonTitleOf(c2, 2), 'Outside');
      expect(again.seasonTitleOf(c2, 1), isNull);
      // A rescan reads the .nfo's title.
      await again.scan();
      expect(again.collectionNamed('Silo')!.videos.firstWhere((v) => v.season == 2).seasonTitle, 'Outside');
    });

    testWidgets('collection page: titled headings, renaming a season, and right-click › Select to edit several', (
      tester,
    ) async {
      await tester.runAsync(scanSilo);
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const VideoCollectionScreen(name: 'Silo')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Season 1 – Offline News'), findsWidgets); // heading and contents chip

      // Name season 2.
      await tester.tap(find.byKey(const ValueKey('season-title:Season 2')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('season-title-field')), 'Outside');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('season-title-save')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Season 2 – Outside'), findsWidgets);

      // Right-click an episode › Select: select mode, with a bar.
      final c = videos.collectionNamed('Silo')!;
      final first = c.videos.first, second = c.videos[1];
      await tester.tap(find.byKey(ValueKey('episode-row:${first.id}')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('video-selection-bar')), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      // A tap now ticks rather than plays.
      await tester.tap(find.byKey(ValueKey('episode-row:${second.id}')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      // The season's box ticks the rest of it; again unticks it all.
      await tester.tap(find.byKey(const ValueKey('season-tick:Season 1')));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('season-tick:Season 1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('video-selection-bar')), findsNothing);

      // Tick two and edit them together.
      await tester.tap(find.byKey(ValueKey('episode-row:${first.id}')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('episode-row:${second.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('selection-edit')));
      await tester.pumpAndSettle();
      expect(find.text('Edit 2 videos'), findsOneWidget);
    });

    testWidgets('collection page: right-click (or hold) a season heading › Select all in it', (tester) async {
      await tester.runAsync(scanSilo);
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const VideoCollectionScreen(name: 'Silo')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('heading-Season 2')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('group-rename')), findsOneWidget);
      expect(find.byKey(const ValueKey('group-fold')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group-select-all')));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byKey(const ValueKey('season-tick:Season 2'))).value, isTrue);

      // Press and hold works too, and adds the other season.
      await tester.longPress(find.byKey(const ValueKey('heading-Season 1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('group-select-all')));
      await tester.pumpAndSettle();
      expect(find.text('6 selected'), findsOneWidget);

      // A fully ticked season offers Unselect instead.
      await tester.tap(find.byKey(const ValueKey('heading-Season 2')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('group-select-all')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('group-unselect')));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);

      // Mark a season watched from its menu.
      await tester.tap(find.byKey(const ValueKey('heading-Season 2')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('group-watched')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await videos.settle();
      });
      await tester.pumpAndSettle();
      final c = videos.collectionNamed('Silo')!;
      expect(c.videos.where((v) => v.season == 2).every((v) => videos.placeOf(v.id)?.watched ?? false), isTrue);
    });

    testWidgets('All videos › Season: right-click a heading › Select all in the season', (tester) async {
      await tester.runAsync(scanSilo);
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const VideosScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All videos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Season').last, warnIfMissed: false); // the menu is still animating in
      await tester.pumpAndSettle();

      bool isSeason2Heading(Widget w) {
        final k = w.key;
        return k is ValueKey<String> && k.value.startsWith('group-heading:') && k.value.contains('Season 2');
      }

      final heading = find.byWidgetPredicate(isSeason2Heading);
      expect(heading, findsOneWidget);
      await tester.tap(heading, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('group-select-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('video-selection-bar')), findsOneWidget);
      expect(find.text('3 selected'), findsOneWidget);
    });

    testWidgets('Settings › Appearance › Video player: choices change the look and the preview', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const Scaffold(body: SingleChildScrollView(child: VideoPlayerLookSettings()))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('video-look-preview')), findsOneWidget);

      await tester.tap(find.text('Circles'));
      await tester.pumpAndSettle();
      expect(lib.videoPlayerLook.backing, VideoButtonBacking.circle);
      expect(find.byKey(const ValueKey('backing-strength')), findsOneWidget);
      await tester.tap(find.text('Large'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('button-colour-black')));
      await tester.pumpAndSettle();
      expect((lib.videoPlayerLook.size, lib.videoPlayerLook.buttonColour), (VideoButtonSize.large, 'black'));
      // The preview's backing is light behind black buttons.
      final backing = tester.widget<ButtonBacking>(find.byType(ButtonBacking).first);
      expect(backing.look.backingColour(Colors.orange).computeLuminance(), greaterThan(0.5));
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('backing-strength')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('video-look-reset')));
      await tester.pumpAndSettle();
      expect(lib.videoPlayerLook, VideoPlayerLook.standard);
      // Let the settings.json writes finish before the folder is removed.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    });
  });
}
