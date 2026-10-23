// Draws the TV interface's screens off-screen at the TV's size (960 x 540) and saves pictures to
// C:\Temp\ht\tv-preview (nothing is shown on screen), to compare with the mockups "HomeTunes TV
// Interface". Step 2: Home, Music (Albums, Artists, Songs, Genres), Audiobooks and Videos, with
// the rail and the focus ring. Uses Windows' Segoe UI so the text is readable. Invented titles.
//   flutter test tool/tv_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/book.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/state/bookmarks_model.dart';
import 'package:hometunes/services/storage.dart';
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
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:hometunes/ui/tv/tv_shell.dart';
import 'package:provider/provider.dart';

class _Player extends ChangeNotifier implements PlayerModel {
  @override
  Track? get current => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _artists = ['Harbour Lights', 'The Slow Engines', 'Mara Quill', 'Ana Ruiz', 'Field Days'];
const _albums = [
  'Low Tide', 'Maple Street', 'Marigold', 'Matchlight', 'Meridian', 'Midnight Bus', 'Millpond', 'Mirror Lake',
  'Moth Wings', 'Mountain Rail', 'Night Ferry', 'North Pier', 'Notebook', 'Nova', 'Oak & Iron', 'Paper Lanterns',
  'Second Wind', 'Field Notes', 'Copper Sky', 'Amber Road', 'Bright Water', 'Cold Harbour', 'Driftwood', 'Echo Lane',
];
const _songs = ['Harbour Wall', 'Salt Road', 'Weathervane', 'Small Hours', 'Tidewater'];
const _genres = ['Folk', 'Indie', 'Jazz', 'Ambient', 'Rock'];

List<Track> _library() => [
      for (var a = 0; a < _albums.length; a++)
        for (var s = 0; s < 3; s++)
          Track(
            id: 'local:/m/${_albums[a]}/$s.mp3',
            source: TrackSource.local,
            title: s == 0 ? _albums[a] : '${_songs[(a + s) % _songs.length]}${a > 4 ? ' $a' : ''}',
            artist: _artists[a % _artists.length],
            album: _albums[a],
            albumArtist: _artists[a % _artists.length],
            year: 2000 + a,
            genre: _genres[a % _genres.length],
            trackNumber: s + 1,
            duration: Duration(minutes: 3, seconds: 10 * s + a),
            path: '/m/${_artists[a % _artists.length]}/${_albums[a]}/$s.mp3',
            modifiedMs: 1000 * a,
          ),
    ];

List<Book> _books() {
  Book b(String title, String author, {String? series, double? n}) => Book(
        id: 'book:$title',
        title: title,
        author: author,
        series: series,
        seriesIndex: n,
        parts: [
          Track(
            id: 'local:/b/$title.m4b',
            source: TrackSource.local,
            title: title,
            artist: author,
            album: title,
            albumArtist: author,
            genre: 'Audiobook',
            series: series,
            seriesIndex: n,
            duration: const Duration(hours: 9, minutes: 20),
            path: '/b/$title.m4b',
          ),
        ],
      );
  return [
    b('The Long Road North', 'Ada Brook', series: 'Northlands', n: 1),
    b('Winter at the Pass', 'Ada Brook', series: 'Northlands', n: 2),
    b('The Last Ferry', 'Ada Brook', series: 'Northlands', n: 3),
    b('Glasshouse', 'Tom Reyes'),
    b('A Quiet Year', 'Lena Ford'),
    b('Small Engines', 'Tom Reyes', series: 'The Workshop', n: 1),
    b('Brass and Bone', 'Tom Reyes', series: 'The Workshop', n: 2),
    b('Paper Moons', 'Lena Ford'),
  ];
}

/// A videos model with one collection, Coastline (two seasons), for the collection page.
class _Videos extends VideoLibraryModel {
  _Videos(super.storage, super.library) {
    final list = [
      for (final (s, e) in [(1, 1), (1, 2), (1, 3), (1, 4), (2, 1), (2, 2)])
        VideoItem(
          id: 'local:/v/Coastline S0${s}E0$e.mkv',
          path: '/v/Coastline S0${s}E0$e.mkv',
          title: ['The Harbour', 'Low Water', 'The Lighthouse', 'Night Crossing', 'Return', 'The Long Pier'][(s - 1) * 4 + e - 1],
          collection: 'Coastline',
          season: s,
          episode: e,
          duration: const Duration(minutes: 41, seconds: 12),
        ),
    ];
    videos = list;
    collections = [
      VideoCollection(name: 'Coastline', videos: list, category: 'TV', year: 2024, description: 'A made-up series about a small harbour town.'),
    ];
  }

  @override
  VideoCollection? collectionNamed(String name) => collections.where((c) => c.name == name).firstOrNull;
}

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: r'C:\Temp\ht\tv-preview');

  testWidgets('TV previews (steps 2 and 3)', (tester) async {
    await tester.runAsync(() async {
      for (final f in [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\segoeuib.ttf', r'C:\Windows\Fonts\seguisb.ttf']) {
        if (!File(f).existsSync()) continue;
        final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
        await loader.load();
      }
    });
    Directory(out).createSync(recursive: true);
    final dir = Directory(r'C:\Temp\ht\preview-data\tv')..createSync(recursive: true);
    for (final e in dir.listSync()) {
      e.deleteSync(recursive: true);
    }
    final storage = Storage.at(dir);
    Directory(storage.artDir).createSync(recursive: true);
    final songs = _library();
    // Through library.json, as the app keeps it, so the library's look-ups are built.
    final lib = LibraryModel(storage);
    await tester.runAsync(() async {
      await storage.write('library.json', {
        'local': [for (final t in [...songs, for (final b in _books()) ...b.parts]) t.toJson()],
      });
      await lib.load();
    });
    final albums = lib.albums;
    final playlists = PlaylistsModel(storage);
    for (final (i, name) in ['Sunday morning', 'Road trip', 'Late night', 'Kitchen'].indexed) {
      playlists.addTracks(playlists.create(name), songs.skip(i * 7).take(6 + i));
    }
    for (final t in songs.take(12)) {
      playlists.toggleLike(t);
    }
    final listening = ListeningModel(storage);
    final history = PlayHistory(storage);
    for (final (i, a) in albums.take(4).indexed) {
      history.record(PlayedItem(PlayedKind.album, a.key, a.title, 200 - i));
    }
    history.record(const PlayedItem(PlayedKind.liked, '', 'Liked Songs', 100));
    history.record(const PlayedItem(PlayedKind.playlist, 'Road trip', 'Road trip', 99));
    history.record(const PlayedItem(PlayedKind.artist, 'Mara Quill', 'Mara Quill', 98));
    final VideoLibraryModel videos = _Videos(storage, lib);
    final nav = AppNav();
    final appearance = lib.settings.appearance;
    await tester.runAsync(() async {
      final north = lib.books.firstWhere((b) => b.title == 'The Long Road North');
      await listening.record(north, north.parts.first.id, const Duration(hours: 5, minutes: 50));
      await appearance.setTvMode(TvMode.on);
    });

    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ...libraryProviders(lib),
        ChangeNotifierProvider.value(value: nav),
        ChangeNotifierProvider.value(value: playlists),
        ChangeNotifierProvider.value(value: listening),
        ChangeNotifierProvider.value(value: history),
        ChangeNotifierProvider(create: (_) => BookmarksModel(storage)),
        ChangeNotifierProvider<PlayerModel>.value(value: _Player()),
        ChangeNotifierProvider(create: (_) => SelectionModel()),
        ChangeNotifierProvider.value(value: videos),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tvTheme(buildTheme(), AppColors.accent),
          builder: (context, child) => TvFocus(enabled: true, child: child!),
          home: const AppHome(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    Future<void> shoot(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final png = await (await b.toImage()).toByteData(format: ui.ImageByteFormat.png);
        File('$out\\$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    Future<void> press(LogicalKeyboardKey k, [int times = 1]) async {
      for (var i = 0; i < times; i++) {
        await tester.sendKeyEvent(k);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    // 1. Home as it opens, then the remote on the second "Recently played" tile.
    await shoot('tv-home-top');
    await press(LogicalKeyboardKey.arrowDown, 2);
    await press(LogicalKeyboardKey.arrowRight);
    await shoot('tv-home');

    // 2. Music › Albums, A–Z, the remote on an album; then on the A–Z strip.
    nav.selectTab(AppNav.libraryTab);
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.arrowDown, 2);
    await press(LogicalKeyboardKey.arrowRight, 2);
    await shoot('tv-music-albums');
    await press(LogicalKeyboardKey.arrowRight, 4);
    await press(LogicalKeyboardKey.arrowDown, 13);
    await shoot('tv-music-az');
    await press(LogicalKeyboardKey.arrowLeft);
    await shoot('tv-music-az-back');

    // 3. The other Music tabs: up to the tabs, then along.
    await press(LogicalKeyboardKey.arrowUp, 8);
    await press(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 400));
    await shoot('tv-music-artists');
    await press(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 400));
    await press(LogicalKeyboardKey.arrowDown, 2);
    await shoot('tv-music-songs');
    await press(LogicalKeyboardKey.arrowUp, 4);
    await press(LogicalKeyboardKey.arrowRight, 2);
    await tester.pump(const Duration(milliseconds: 400));
    await shoot('tv-music-genres');

    // 4. Audiobooks and Videos.
    nav.selectTab(AppNav.booksTab);
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.arrowDown);
    await shoot('tv-books');
    await press(LogicalKeyboardKey.arrowUp);
    await press(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 400));
    await press(LogicalKeyboardKey.arrowDown);
    await shoot('tv-books-all');
    nav.selectTab(AppNav.videosTab);
    await tester.pumpAndSettle();
    await shoot('tv-videos');

    // 5. The rail open over Music.
    nav.selectTab(AppNav.libraryTab);
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.arrowLeft, 8);
    await shoot('tv-rail-open');

    // 6. Step 3: the pages, each opened as the app would, the remote on its first song / row.
    Future<void> page(String name, void Function() open, {int down = 1}) async {
      nav.selectTab(AppNav.libraryTab);
      await tester.pumpAndSettle();
      open();
      await tester.pumpAndSettle();
      await press(LogicalKeyboardKey.arrowDown, down);
      await shoot(name);
      nav.current?.popUntil((r) => r.isFirst);
      await tester.pumpAndSettle();
    }

    await page('tv-page-album', () => nav.openAlbum(albums.firstWhere((a) => a.title == 'Paper Lanterns')), down: 2);
    await page('tv-page-artist', () => nav.openArtist('Harbour Lights'));
    await page('tv-page-playlist', () => nav.openPlaylist(playlists.playlists[1]));
    await page('tv-page-book', () => nav.openBook(lib.books.firstWhere((b) => b.title == 'The Long Road North')), down: 2);
    await page('tv-page-series', () => nav.openSeries('Northlands'));
    await page('tv-page-collection', () => nav.openVideoCollection('Coastline'), down: 2);

    // 7. Step 4: a song's options, and Add to a playlist ›.
    nav.selectTab(AppNav.libraryTab);
    await tester.pumpAndSettle();
    nav.openAlbum(albums.firstWhere((a) => a.title == 'Paper Lanterns'));
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.arrowDown, 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.arrowDown, 2);
    await shoot('tv-options-song');
    await press(LogicalKeyboardKey.select);
    await shoot('tv-options-playlist');
  });
}
