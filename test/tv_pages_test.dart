// The TV interface, step 3 (0.2.0): the pages. In TV mode an album, a playlist, a book and a video
// collection open on their TV pages, and everything on them works with the arrow keys and OK.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/book.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/play_history.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/bookmarks_model.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:hometunes/ui/tv/tv_book_pages.dart';
import 'package:hometunes/ui/tv/tv_collection_page.dart';
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:hometunes/ui/tv/tv_pages.dart';
import 'package:hometunes/ui/tv/tv_shell.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// Records what was asked to play; nothing is playing.
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
      played.add('${tracks[start].title} from $label${shuffle == true ? ', shuffled' : ''}');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A videos model with one collection, Coastline: two episodes of season 1 and one of season 2.
class _Videos extends VideoLibraryModel {
  _Videos(super.storage, super.library) {
    final list = [
      for (final (s, e) in [(1, 1), (1, 2), (2, 1)])
        VideoItem(
          id: 'local:/v/Coastline S0${s}E0$e.mkv',
          path: '/v/Coastline S0${s}E0$e.mkv',
          title: 'Coastline S0${s}E0$e',
          collection: 'Coastline',
          season: s,
          episode: e,
          duration: const Duration(minutes: 41),
        ),
    ];
    videos = list;
    collections = [VideoCollection(name: 'Coastline', videos: list, category: 'TV')];
  }

  @override
  VideoCollection? collectionNamed(String name) => collections.where((c) => c.name == name).firstOrNull;
}

Track _t(String title, String album, int no, {String? path}) => Track(
      id: 'local:/m/$album/$title.mp3',
      source: TrackSource.local,
      title: title,
      artist: 'Harbour Lights',
      album: album,
      albumArtist: 'Harbour Lights',
      trackNumber: no,
      duration: Duration(minutes: 3, seconds: no),
      path: path,
    );

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;
  late PlaylistsModel playlists;
  late VideoLibraryModel videos;
  late AppNav nav;
  late _Player player;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_tv_pages');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    Directory(storage.artDir).createSync(recursive: true);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpApp(WidgetTester tester, {bool withVideos = false}) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final songs = [
      _t('Paper Lanterns', 'Paper Lanterns', 1),
      _t('Harbour Wall', 'Paper Lanterns', 2),
      _t('Salt Road', 'Paper Lanterns', 3),
      _t('Night Ferry', 'Night Ferry', 1),
    ];
    final bookParts = [
      for (var i = 1; i <= 3; i++)
        Track(
          id: 'local:/b/north/$i.mp3',
          source: TrackSource.local,
          title: 'Part $i',
          artist: 'Ada Brook',
          album: 'The Long Road North',
          albumArtist: 'Ada Brook',
          genre: 'Audiobook',
          trackNumber: i,
          duration: const Duration(minutes: 40),
        ),
    ];
    // Through library.json, as the app keeps it, so the library's look-ups are built.
    lib = LibraryModel(storage);
    await tester.runAsync(() async {
      await storage.write('library.json', {
        'local': [for (final t in [...songs, ...bookParts]) t.toJson()],
      });
      await lib.load();
    });
    playlists = PlaylistsModel(storage);
    playlists.addTracks(playlists.create('Road trip'), [songs[3], songs[1]]);
    videos = withVideos ? _Videos(storage, lib) : VideoLibraryModel(storage, lib);
    player = _Player();
    nav = AppNav();
    await tester.runAsync(() async {
      await lib.settings.appearance.setTvMode(TvMode.on);
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
        ChangeNotifierProvider(create: (_) => SelectionModel()),
        ChangeNotifierProvider<PlayerModel>.value(value: player),
      ],
      child: MaterialApp(
        theme: tvTheme(buildTheme(), AppColors.accent),
        builder: (context, child) => TvFocus(enabled: true, child: child!),
        home: const AppHome(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  /// The key ("tv-song:…") of the row or button with focus.
  String? focusedKey() {
    String? found;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
      final k = e.widget.key;
      if (k is ValueKey<String> && k.value.startsWith('tv-')) {
        found = k.value;
        return false;
      }
      return true;
    });
    return found;
  }

  Future<void> holdOk(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
  }

  testWidgets('an album opens on its TV page: Play is first; ↓ to the songs; OK plays from that song', (tester) async {
    await pumpApp(tester);
    nav.openAlbum(lib.albums.firstWhere((a) => a.title == 'Paper Lanterns'));
    await tester.pumpAndSettle();
    expect(find.byType(TvAlbumPage), findsOneWidget);
    expect(find.text('ALBUM'), findsOneWidget);
    expect(focusedKey(), 'tv-page-play');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedKey(), startsWith('tv-song:'));
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.text('Hold OK for options'), findsOneWidget); // only on the row with focus
    await press(tester, LogicalKeyboardKey.select);
    expect(player.played, ['Harbour Wall from Album · Paper Lanterns']);
    // Up to the header: Shuffle.
    await press(tester, LogicalKeyboardKey.arrowUp, 2);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(player.played.last, 'Paper Lanterns from Album · Paper Lanterns, shuffled');
  });

  testWidgets('a playlist: holding OK on a song offers Remove from this playlist', (tester) async {
    await pumpApp(tester);
    nav.openPlaylist(playlists.playlists.single);
    await tester.pumpAndSettle();
    expect(find.byType(TvPlaylistPage), findsOneWidget);
    expect(find.text('Night Ferry'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await holdOk(tester);
    expect(find.text('Remove from this playlist'), findsOneWidget);
    await tester.tap(find.text('Remove from this playlist'));
    await tester.pumpAndSettle();
    expect(playlists.playlists.single.trackIds, ['local:/m/Paper Lanterns/Harbour Wall.mp3']);
    expect(find.text('Night Ferry'), findsNothing);
  });

  // (Playing a book goes through PlayerModel's book code, which this stand-in player can't fake.)
  testWidgets('a book: Play, then one row per chapter for the remote to move through', (tester) async {
    await pumpApp(tester);
    nav.openBook(lib.books.single);
    await tester.pumpAndSettle();
    expect(find.byType(TvBookPage), findsOneWidget);
    expect(find.text('3 chapters'), findsOneWidget);
    expect(focusedKey(), 'tv-page-play');
    await press(tester, LogicalKeyboardKey.arrowDown, 2);
    expect(focusedKey(), 'tv-chapter:1');
    expect(find.text('Part 2'), findsOneWidget);
  });

  testWidgets('a video collection: a tab per season, its episodes as rows', (tester) async {
    await pumpApp(tester, withVideos: true);
    nav.openVideoCollection('Coastline');
    await tester.pumpAndSettle();
    expect(find.byType(TvCollectionPage), findsOneWidget);
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    expect(find.textContaining('S1 E1'), findsWidgets);
    expect(find.textContaining('S2 E1'), findsNothing);
    await tester.tap(find.text('Season 2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('S2 E1'), findsWidgets);
    expect(find.textContaining('S1 E1'), findsNothing);
  });

  test('outside TV mode the usual pages open (AppHome sets this; Shell\'s tests leave it off)', () {
    expect(AppNav().tv, isFalse);
  });
}
