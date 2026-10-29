// Video types, filters and sorts for the TV's Videos tab (state/video_types.dart, 0.2.5), and the
// tab's type buttons (ui/tv/tv_videos.dart).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/source_filter.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/state/video_types.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:hometunes/ui/tv/tv_videos.dart';
import 'package:provider/provider.dart';

VideoItem _v(String id, String collection, String? category, {String? genre, int? episode}) => VideoItem(
      id: 'jf:s1:$id',
      path: 'jellyfin://s1/$id.mkv',
      title: '$collection $id',
      collection: collection,
      category: category,
      genre: genre,
      season: episode == null ? null : 1,
      episode: episode,
    );

void main() {
  test('a category\'s type: Film(s) and Movies are Films, TV and Shows are TV, anything anime is Anime', () {
    expect(videoType('Films'), 'Films');
    expect(videoType('Film'), 'Films');
    expect(videoType('Movies'), 'Films');
    expect(videoType('TV'), 'TV');
    expect(videoType('Shows'), 'TV');
    expect(videoType('TV Shows'), 'TV');
    expect(videoType('Anime'), 'Anime');
    expect(videoType('Anime Movies'), 'Anime');
    expect(videoType('Documentaries'), 'Documentaries'); // any other kind keeps its name
    expect(videoType(null), isNull);
    expect(videoType('  '), isNull);
    expect(orderTypes(['Films', 'Documentaries', null, 'TV', 'Anime', 'TV', 'Concerts']),
        ['Anime', 'TV', 'Films', 'Concerts', 'Documentaries']);
  });

  test('a collection\'s type and genre are what most of its videos have', () {
    final c = VideoCollection(name: 'Silo', videos: [
      _v('1', 'Silo', 'TV', genre: 'Drama', episode: 1),
      _v('2', 'Silo', 'Shows', genre: 'Drama', episode: 2),
      _v('3', 'Silo', 'Films', genre: 'Sci-Fi', episode: 3),
    ]);
    expect(collectionType(c), 'TV');
    expect(collectionGenre(c), 'Drama');
  });

  test('watched states, and the filters together', () {
    expect(collectionWatchState(watchedCount: 0, main: 5, started: false), WatchState.notStarted);
    expect(collectionWatchState(watchedCount: 0, main: 5, started: true), WatchState.inProgress);
    expect(collectionWatchState(watchedCount: 2, main: 5, started: false), WatchState.inProgress);
    expect(collectionWatchState(watchedCount: 5, main: 5, started: false), WatchState.watched);

    final aot = VideoCollection(name: 'Attack on Titan', videos: [_v('a1', 'Attack on Titan', 'Anime', genre: 'Action', episode: 1)]);
    final daria = VideoCollection(name: 'Daria', videos: [_v('d1', 'Daria', 'TV', genre: 'Animation', episode: 1)]);
    final dune = VideoCollection(name: 'Dune', videos: [_v('m1', 'Dune', 'Films', genre: 'Sci-Fi')]);
    final all = [aot, daria, dune];
    final states = {aot: WatchState.inProgress, daria: WatchState.notStarted, dune: WatchState.watched};
    List<String> names(VideoChoice c) => [for (final x in chooseCollections(all, c, stateOf: (x) => states[x]!)) x.name];

    expect(names(const VideoChoice()), ['Attack on Titan', 'Daria', 'Dune']);
    expect(names(const VideoChoice(type: 'Anime')), ['Attack on Titan']);
    expect(names(const VideoChoice(type: 'TV')), ['Daria']);
    expect(names(const VideoChoice(watch: WatchState.notStarted)), ['Daria']);
    expect(names(const VideoChoice(genre: 'Sci-Fi')), ['Dune']);
    expect(names(const VideoChoice(type: 'Anime', genre: 'Sci-Fi')), isEmpty);
    // All of these stream (no downloads in this test).
    expect(names(const VideoChoice(source: SourceChoice.streamed)), hasLength(3));
    expect(names(const VideoChoice(source: SourceChoice.downloaded)), isEmpty);
    expect(genresOf(collections: all), ['Action', 'Animation', 'Sci-Fi']);
    expect(const VideoChoice(type: 'TV', genre: 'Drama', watch: WatchState.watched).filters, 2);
    expect(const VideoChoice(type: 'TV', genre: 'Drama').withoutFilters.type, 'TV');
    expect(MediaSource.temporary.label, 'Downloaded');
    expect(SourceChoice.downloaded.matches(MediaSource.temporary), isTrue);
  });

  test('Most episodes and Not watched first', () {
    final big = VideoCollection(name: 'Big', videos: [for (var i = 1; i <= 5; i++) _v('b$i', 'Big', 'TV', episode: i)]);
    final small = VideoCollection(name: 'Small', videos: [_v('s1', 'Small', 'TV', episode: 1)]);
    final mid = VideoCollection(name: 'Mid', videos: [_v('m1', 'Mid', 'TV', episode: 1), _v('m2', 'Mid', 'TV', episode: 2)]);
    expect([for (final c in byMostEpisodes([small, big, mid])) c.name], ['Big', 'Mid', 'Small']);
    final states = {big: WatchState.watched, small: WatchState.inProgress, mid: WatchState.notStarted};
    expect([for (final c in byNotWatchedFirst<VideoCollection>([big, small, mid], (c) => states[c]!, (c) => c.name)) c.name],
        ['Mid', 'Small', 'Big']);
  });

  group('the TV\'s Videos tab', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_video_types'));
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('type buttons All · Anime · TV · Films under the tabs; choosing one shows just that type', (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      final storage = Storage.at(dir);
      Directory(storage.artDir).createSync(recursive: true);
      final lib = LibraryModel(storage);
      final videos = VideoLibraryModel(storage, lib)
        ..setServerVideos('s1', [
          _v('a1', 'Attack on Titan', 'Anime', episode: 1),
          _v('a2', 'Black Lagoon', 'Anime', episode: 1),
          _v('t1', 'Daria', 'TV', episode: 1),
          _v('f1', 'Dune', 'Films'),
        ]);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ...libraryProviders(lib),
          ChangeNotifierProvider.value(value: videos),
          ChangeNotifierProvider(create: (_) => AppNav()),
        ],
        child: MaterialApp(
          theme: tvTheme(buildTheme(), AppColors.accent),
          builder: (context, child) => TvFocus(enabled: true, child: child!),
          home: const Scaffold(body: TvVideosScreen()),
        ),
      ));
      await tester.pumpAndSettle();
      for (final t in ['All', 'Anime', 'TV', 'Films']) {
        expect(find.byKey(ValueKey('tv-tab-$t')), findsOneWidget, reason: t);
      }
      expect(find.text('Filter'), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-collection:Daria')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tv-tab-Anime')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tv-collection:Attack on Titan')), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-collection:Black Lagoon')), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-collection:Daria')), findsNothing);
      expect(find.byKey(const ValueKey('tv-collection:Dune')), findsNothing);

      // The same type carries into All videos.
      await tester.tap(find.byKey(const ValueKey('tv-tab-All videos')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tv-video:jf:s1:a1')), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-video:jf:s1:t1')), findsNothing);

      // Sort: Most episodes isn't offered for videos one by one; Reverse is.
      await tester.tap(find.byKey(const ValueKey('tv-sort')));
      await tester.pumpAndSettle();
      expect(find.text('Most episodes'), findsNothing);
      expect(find.text('Not watched first'), findsOneWidget);
      await tester.tap(find.text('Reverse the order: off'));
      await tester.pumpAndSettle();
      expect(find.text('Sort: Z–A'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // The type buttons' "rest to show" delay, started by the taps, runs out.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
