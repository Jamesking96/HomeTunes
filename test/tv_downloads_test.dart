// 0.2.3: downloads on the TV. In TV mode the options panel (hold OK, or a page's More button)
// offers Download, Keep offline, Stop downloading and Remove download for things from a server,
// a second panel asks which copy, a collection's page offers the season showing on its own, and
// the TV Downloads page lists what's downloading and downloaded. Nothing is offered for your own
// files.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/book.dart';
import 'package:hometunes/models/download.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/bookmarks_model.dart';
import 'package:hometunes/state/downloads_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/play_history.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:hometunes/ui/tv/tv_collection_page.dart';
import 'package:hometunes/ui/tv/tv_downloads.dart';
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:hometunes/ui/tv/tv_menus.dart';
import 'package:hometunes/ui/tv/tv_shell.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'fake_download_engine.dart';

/// Nothing is playing; what was asked to play is noted.
class _Player extends ChangeNotifier implements PlayerModel {
  final played = <String>[];
  @override
  Track? get current => null;
  @override
  Book? get book => null;
  @override
  bool get inBook => false;
  @override
  bool get playing => false;
  @override
  Future<void> playTracks(List<Track> tracks, {int start = 0, bool? shuffle, String? label}) async =>
      played.add('${tracks[start].title} from $label');
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

VideoItem _episode(String id, int s, int e) => VideoItem(
      id: 'jf:den:$id',
      path: 'jellyfin://den/$id.mkv',
      title: 'Episode $e',
      collection: 'Silo',
      category: 'TV',
      season: s,
      episode: e,
      duration: const Duration(minutes: 50),
      sizeBytes: 1500000000,
    );

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;
  late VideoLibraryModel videos;
  late AppNav nav;
  late FakeEngine engine;
  late DownloadsModel dl;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_tv_downloads');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    Directory(storage.artDir).createSync(recursive: true);
  });
  tearDown(() async {
    dl.dispose();
    engine.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    lib = LibraryModel(storage);
    final playlists = PlaylistsModel(storage);
    videos = VideoLibraryModel(storage, lib);
    engine = FakeEngine();
    nav = AppNav();
    await tester.runAsync(() async {
      videos.setServerVideos('den', [_episode('ep1', 1, 1), _episode('ep2', 1, 2), _episode('ep3', 2, 1)]);
      await lib.load();
      await lib.settings.appearance.setTvMode(TvMode.on);
      dl = DownloadsModel(
        storage: storage,
        library: lib,
        playlists: playlists,
        videos: videos,
        engine: engine,
        sources: FakeSources(),
      );
      await dl.load();
      await dl.start();
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ...libraryProviders(lib),
        ChangeNotifierProvider.value(value: nav),
        ChangeNotifierProvider.value(value: playlists),
        ChangeNotifierProvider(create: (_) => ListeningModel(storage)),
        ChangeNotifierProvider(create: (_) => BookmarksModel(storage)),
        ChangeNotifierProvider(create: (_) => PlayHistory(storage)),
        ChangeNotifierProvider.value(value: videos),
        ChangeNotifierProvider<DownloadsModel?>.value(value: dl),
        ChangeNotifierProvider(create: (_) => SelectionModel()),
        ChangeNotifierProvider<PlayerModel>(create: (_) => _Player()),
      ],
      child: MaterialApp(
        theme: tvTheme(buildTheme(), AppColors.accent),
        builder: (context, child) => TvFocus(enabled: true, child: child!),
        home: const AppHome(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  VideoItem v(String id) => videos.byId('jf:den:$id')!;

  /// Lets the model hand things to the engine (it makes real folders on the way).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// The model's save and redraw timers started on the test's clock: let them run out.
  Future<void> finish(WidgetTester tester) => tester.pump(const Duration(seconds: 3));

  testWidgets('a collection\'s More options: download it all, keep it offline, or just the season showing', (tester) async {
    await pumpApp(tester);
    nav.openVideoCollection('Silo');
    await tester.pumpAndSettle();
    expect(find.byType(TvCollectionPage), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Download all 3'), findsOneWidget);
    expect(find.text('Keep offline'), findsOneWidget);
    expect(find.text('Download all 2: Season 1'), findsOneWidget);

    // Keep offline: Season 1 › which copy › 720p.
    await tester.tap(find.text('Keep offline: Season 1'));
    await tester.pumpAndSettle();
    expect(find.text('Original file'), findsOneWidget);
    expect(find.text('Smaller copy, 720p'), findsOneWidget);
    await tester.tap(find.text('Smaller copy, 720p'));
    await settle(tester);
    final c = videos.collectionNamed('Silo')!;
    expect(dl.isKept(KeepKind.season, DownloadsModel.seasonKey(c, 'Season 1')), isTrue);
    expect(dl.entryOf(v('ep1').id)?.quality.code, 'v720');
    expect(dl.entryOf(v('ep3').id), isNull, reason: 'season 2 isn\'t kept');
    await finish(tester);
  });

  testWidgets('a video: Download asks which copy; then Stop downloading, and Remove once it\'s here', (tester) async {
    await pumpApp(tester);
    nav.openVideoCollection('Silo');
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(TvCollectionPage));
    showVideoOptions(context, v('ep2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.text('Which copy?'), findsOneWidget);
    expect(find.textContaining('1.5 GB'), findsOneWidget, reason: 'the original\'s size, from the server');
    await tester.tap(find.text('Original file'));
    await settle(tester);
    expect(dl.isPending(v('ep2').id), isTrue);
    expect(engine.jobs, hasLength(1));

    showVideoOptions(context, v('ep2'));
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsNothing);
    expect(find.text('Stop downloading'), findsOneWidget);
    await tester.tapAt(const Offset(20, 270)); // the dimmed screen beside the panel closes it
    await tester.pumpAndSettle();

    await tester.runAsync(() => engine.finish(v('ep2').id));
    await tester.pumpAndSettle();
    showVideoOptions(context, v('ep2'));
    await tester.pumpAndSettle();
    expect(find.text('Remove download'), findsOneWidget);
    await tester.tap(find.text('Remove download'));
    await settle(tester);
    expect(dl.entryOf(v('ep2').id), isNull);
    await finish(tester);
  });

  testWidgets('the TV Downloads page lists what\'s downloading and downloaded', (tester) async {
    await pumpApp(tester);
    await tester.runAsync(() async {
      dl.download([DownloadItem.video(v('ep1')), DownloadItem.video(v('ep2'))], const DownloadQuality.original());
      await pumpEvents();
      await engine.finish(v('ep1').id);
    });
    nav.openDownloads();
    await tester.pumpAndSettle();
    expect(find.byType(TvDownloadsPage), findsOneWidget);
    expect(find.text('Downloading (1)'), findsOneWidget);
    expect(find.text('Downloaded (1)'), findsOneWidget);
    expect(find.byKey(ValueKey('tv-download:${v('ep1').id}')), findsOneWidget);
    expect(find.text('Pause all'), findsOneWidget);
    await tester.tap(find.text('Pause all'));
    await settle(tester);
    expect(dl.entryOf(v('ep2').id)!.state, DownloadState.paused);
    expect(find.text('Carry on with all'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('nothing to download for your own files', (tester) async {
    await pumpApp(tester);
    final context = tester.element(find.byType(AppHome));
    final local = VideoItem(id: VideoItem.idFor('/v/a.mkv'), path: '/v/a.mkv', title: 'Home movie', collection: 'Home');
    expect(tvDownloadOptions(context, [DownloadItem.video(local)]), isEmpty);
    expect([for (final o in videoOptions(context, local)) o.label], isNot(contains('Download')));
  });
}
