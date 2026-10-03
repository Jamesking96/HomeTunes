// 0.1.45: the new Home page ("The home tab should include showing videos too ... revamp the
// home page"): recently played music (PlayHistory), the mixed "Jump back in" row, and the Music,
// Audiobooks and Videos sections.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/play_history.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/home_screen.dart';
import 'package:hometunes/ui/widgets/jump_back_in.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'metadata_features_test.dart' show silentWav;

const _song = Track(
  id: 'local:/m/1.flac',
  source: TrackSource.local,
  title: 'One',
  artist: 'Muse',
  album: 'Absolution',
  albumArtist: 'Muse',
  duration: Duration(minutes: 3),
);

void main() {
  group('recently played music', () {
    test('where a song was played from, from the queue\'s label', () {
      expect(playedFrom('Playlist · Road trip', _song, 5)!.kind, PlayedKind.playlist);
      expect(playedFrom('Playlist · Road trip', _song, 5)!.key, 'Road trip');
      expect(playedFrom('Artist · Muse', _song, 5)!.kind, PlayedKind.artist);
      expect(playedFrom('Liked Songs', _song, 5)!.kind, PlayedKind.liked);
      final album = playedFrom('Album · Absolution', _song, 5)!;
      expect(album.kind, PlayedKind.album);
      expect(album.key, _song.albumKey);
      expect(album.title, 'Absolution');
      // All songs, a search, nothing: the song's album.
      expect(playedFrom('All songs', _song, 5)!.kind, PlayedKind.album);
      expect(playedFrom(null, _song, 5)!.kind, PlayedKind.album);
      expect(playedFrom('Book · Dune', _song, 5), isNull); // audiobooks aren't recorded here
    });

    test('newest first, each place once, at most 50, saved and read back', () async {
      final dir = Directory.systemTemp.createTempSync('hometunes_history');
      addTearDown(() => dir.deleteSync(recursive: true));
      final storage = Storage.at(dir);
      final h = PlayHistory(storage);
      for (var i = 0; i < 60; i++) {
        h.record(PlayedItem(PlayedKind.album, 'a$i', 'Album $i', i));
      }
      h.record(const PlayedItem(PlayedKind.album, 'a10', 'Album 10', 100));
      expect(h.items.length, PlayHistory.max);
      expect(h.items.first.key, 'a10');
      expect(h.items.where((x) => x.key == 'a10').length, 1);
      await h.save();
      final again = PlayHistory(storage);
      await again.load();
      expect(again.items.length, PlayHistory.max);
      expect(again.items.first.title, 'Album 10');
      await again.clear();
      expect(again.items, isEmpty);
      h.dispose();
      again.dispose();
    });

    test('backups merge both lists, newest first, each place once', () {
      final merged = AppBackup.mergeHistory(
        [
          {'kind': 'album', 'key': 'a', 'title': 'A', 'at': 5},
          {'kind': 'artist', 'key': 'Muse', 'title': 'Muse', 'at': 1},
        ],
        [
          {'kind': 'album', 'key': 'a', 'title': 'A', 'at': 9},
          {'kind': 'playlist', 'key': 'Road', 'title': 'Road', 'at': 7},
          'nonsense',
        ],
      );
      expect([for (final x in merged) x['key']], ['a', 'Road', 'Muse']);
      expect(merged.first['at'], 9);
    });
  });

  group('the Home page', () {
    late Directory dir;
    late Storage storage;
    late LibraryModel lib;
    late PlaylistsModel playlists;
    late ListeningModel listening;
    late PlayHistory history;
    late VideoLibraryModel videos;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('hometunes_home');
      storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      Directory(storage.artDir).createSync();
      // A song, an audiobook, a series with two episodes and a film.
      final music = Directory(p.join(dir.path, 'music', 'Muse', 'Absolution'))..createSync(recursive: true);
      File(p.join(music.path, '01 Apocalypse Please.wav')).writeAsBytesSync(silentWav());
      final book = Directory(p.join(dir.path, 'listen', 'Book 01 - A Story'))..createSync(recursive: true);
      File(p.join(book.path, '01.wav')).writeAsBytesSync(silentWav());
      final season = Directory(p.join(dir.path, 'vids', 'TV', 'Silo', 'Season 1'))..createSync(recursive: true);
      File(p.join(season.path, 'Silo S01E01.mkv')).writeAsBytesSync([1]);
      File(p.join(season.path, 'Silo S01E02.mkv')).writeAsBytesSync([1]);
      final films = Directory(p.join(dir.path, 'vids', 'Films'))..createSync(recursive: true);
      File(p.join(films.path, 'Arrival (2016).mkv')).writeAsBytesSync([1]);

      lib = LibraryModel(storage);
      await lib.addFolder(p.join(dir.path, 'music'));
      await lib.addAudiobookFolder(p.join(dir.path, 'listen'));
      await lib.addVideoFolder(p.join(dir.path, 'vids'));
      playlists = PlaylistsModel(storage);
      listening = ListeningModel(storage)..now = () => 1000;
      history = PlayHistory(storage);
      videos = VideoLibraryModel(storage, lib);
      await videos.scan();

      // Part-way through the film and the book; Silo episode 1 watched; the album played long ago.
      final film = videos.videos.firstWhere((v) => v.title.startsWith('Arrival'));
      videos.savePlace(film.id, const Duration(minutes: 30), const Duration(minutes: 116));
      final e1 = videos.videos.firstWhere((v) => v.episode == 1);
      await videos.setWatched([e1.id], true);
      final b = lib.books.single;
      await listening.record(b, b.parts.first.id, const Duration(minutes: 5));
      history.record(PlayedItem(PlayedKind.album, lib.albums.single.key, lib.albums.single.title, 1));
    });
    tearDown(() async {
      await videos.settle();
      for (var i = 0; i < 20; i++) {
        try {
          dir.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });

    Widget app() => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
        ChangeNotifierProvider.value(value: playlists),
        ChangeNotifierProvider.value(value: listening),
        ChangeNotifierProvider.value(value: history),
        ChangeNotifierProvider.value(value: videos),
        ChangeNotifierProvider(create: (_) => AppNav()),
        ChangeNotifierProvider(create: (_) => SelectionModel()),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );

    test('Jump back in mixes them, newest first', () {
      final jumps = jumpsFrom(lib: lib, listening: listening, playlists: playlists, history: history, videos: videos);
      expect(jumps.length, 3);
      expect(jumps[0], isA<VideoJump>()); // watched just now
      expect(jumps[1], isA<BookJump>()); // at 1000
      expect(jumps[2], isA<MusicJump>()); // at 1
      // Something that's gone isn't offered.
      history.record(const PlayedItem(PlayedKind.album, 'gone', 'Gone', 5000));
      history.record(const PlayedItem(PlayedKind.playlist, 'Nope', 'Nope', 5001));
      expect(jumpsFrom(lib: lib, history: history).length, 1);
    });

    test('Up next is the next episode after one you finished', () {
      final next = upNextVideos(videos);
      expect(next.single.episode, 2);
    });

    testWidgets('shows Jump back in and a section each for music, audiobooks and videos', (tester) async {
      tester.view.physicalSize = const Size(1400, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.text(HomeScreen.greeting()), findsOneWidget);
      expect(find.text('Jump back in'), findsOneWidget);
      expect(find.byType(JumpCard), findsNWidgets(3));
      expect(find.text('Continue watching'), findsOneWidget);
      expect(find.text('Continue listening'), findsOneWidget);
      expect(find.text('Absolution'), findsWidgets);
      for (final section in ['Music', 'Audiobooks', 'Videos']) {
        expect(find.byKey(ValueKey('see-all-$section')), findsOneWidget, reason: section);
      }
      expect(find.byKey(const ValueKey('home-recent-albums')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-recent-books')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-up-next')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-recent-collections')), findsOneWidget);

      // "See all" opens the tab.
      await tester.tap(find.byKey(const ValueKey('see-all-Videos')));
      expect(tester.element(find.byType(HomeScreen)).read<AppNav>().tab, AppNav.videosTab);
    });

    testWidgets('an empty library offers to add music and videos', (tester) async {
      final empty = Directory.systemTemp.createTempSync('hometunes_home_empty');
      addTearDown(() => empty.deleteSync(recursive: true));
      final s = Storage.at(empty);
      final bare = LibraryModel(s);
      final noVideos = VideoLibraryModel(s, bare);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: bare),
            ChangeNotifierProvider.value(value: PlaylistsModel(s)),
            ChangeNotifierProvider.value(value: ListeningModel(s)),
            ChangeNotifierProvider.value(value: noVideos),
            ChangeNotifierProvider(create: (_) => AppNav()),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Add music'), findsOneWidget);
      expect(find.text('Add videos'), findsOneWidget);
    });
  });
}
