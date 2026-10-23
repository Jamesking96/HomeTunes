// The TV interface, step 6 (0.2.0): Search. The keyboard on the left types with the remote (or a
// real keyboard); the results on the right update as it types; → and ← go between them.
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
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:hometunes/ui/tv/tv_search.dart';
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
    dir = Directory.systemTemp.createTempSync('hometunes_tv_search');
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

  /// Opens Search from the menu at the side, as the remote would.
  Future<void> openSearch(WidgetTester tester) async {
    await press(tester, LogicalKeyboardKey.arrowLeft); // onto the menu
    await press(tester, LogicalKeyboardKey.arrowUp, 6); // Home, at the top
    await press(tester, LogicalKeyboardKey.arrowDown, 4); // Search
    await press(tester, LogicalKeyboardKey.select);
  }

  /// Types on a real keyboard.
  Future<void> type(WidgetTester tester, String text) async {
    for (final c in text.split('')) {
      await press(tester, c == ' ' ? LogicalKeyboardKey.space : LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + c.codeUnitAt(0) - 97));
    }
  }

  testWidgets('Search opens on the TV keyboard; OK types; the results show as it types', (tester) async {
    await pumpApp(tester);
    await openSearch(tester);
    expect(nav.tab, tvSearchTab);
    expect(find.byType(TvSearchScreen), findsOneWidget);
    expect(find.text('Type to search'), findsOneWidget);
    expect(find.text('Search your library'), findsOneWidget);
    expect(focusedKey(), 'tv-key-a');
    // ↓ → to H, then OK.
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedKey(), 'tv-key-h');
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text('h|'), findsOneWidget);
    await type(tester, 'arb');
    expect(find.text('harb|'), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-search-artists')), findsOneWidget);
    expect(find.text('Harbour Wall'), findsOneWidget);
    expect(focusedKey(), 'tv-key-h'); // typing doesn't move the focus
    // → along the row and off its end: into the results. ← comes back to the keyboard.
    await press(tester, LogicalKeyboardKey.arrowRight, 5);
    expect(focusedKey(), isNot(startsWith('tv-key-')));
    expect(focusedKey(), anyOf(startsWith('tv-artist'), startsWith('tv-song:')));
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedKey(), startsWith('tv-key-'));
  });

  testWidgets('Delete takes off a letter, Clear (or holding Delete) empties it; Backspace too', (tester) async {
    await pumpApp(tester);
    await openSearch(tester);
    await type(tester, 'salt');
    expect(find.text('salt|'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.backspace);
    expect(find.text('sal|'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tv-key-Delete')));
    await tester.pumpAndSettle();
    expect(find.text('sa|'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tv-key-Clear')));
    await tester.pumpAndSettle();
    expect(find.text('Type to search'), findsOneWidget);
    await type(tester, 'road');
    // Down to Delete with the remote: OK takes off a letter; holding OK empties it.
    await press(tester, LogicalKeyboardKey.arrowDown, 6);
    expect(focusedKey(), 'tv-key-Space');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedKey(), 'tv-key-Delete');
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text('roa|'), findsOneWidget);
    await holdOk(tester);
    expect(find.text('Type to search'), findsOneWidget);
  });

  testWidgets('OK on a song found plays the songs found, from that one', (tester) async {
    await pumpApp(tester);
    await openSearch(tester);
    await type(tester, 'harbour');
    await tester.tap(find.text('Harbour Wall'));
    await tester.pumpAndSettle();
    expect(player.played, ['Harbour Wall from Search · harbour']);
  });

  testWidgets('nothing found says so; videos and their collections are found too', (tester) async {
    await pumpApp(tester, withVideos: true);
    await openSearch(tester);
    await type(tester, 'zzq');
    expect(find.text('Nothing found for "zzq"'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tv-key-Clear')));
    await tester.pumpAndSettle();
    await type(tester, 'coast');
    expect(find.byKey(const ValueKey('tv-search-collections')), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-search-videos')), findsOneWidget);
  });
}
