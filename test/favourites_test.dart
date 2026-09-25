// Favourite albums and audiobooks: marking them, keeping them through moves,
// edits and backups, and the heart on album tiles.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/book.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/widgets/cards.dart';
import 'package:provider/provider.dart';

Track song(String id, String album) => Track(
      id: 'local:/m/$id.mp3',
      source: TrackSource.local,
      title: id,
      artist: 'Tidewater',
      album: album,
      albumArtist: 'Tidewater',
      duration: const Duration(minutes: 3),
      path: '/m/$id.mp3',
    );

Album album(String title, List<Track> tracks) =>
    Album(key: tracks.first.albumKey, title: title, artist: 'Tidewater', tracks: tracks);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_fav'));
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save started inside a widget test can still hold the file; it's only a temp folder.
    }
  });

  final a1 = song('a1', 'Harbour Lights'), a2 = song('a2', 'Harbour Lights'), b1 = song('b1', 'Night Ferry');
  final harbour = album('Harbour Lights', [a1, a2]);
  final ferry = album('Night Ferry', [b1]);

  group('Favourites', () {
    test('albums and books can be made favourites, and it\'s saved', () async {
      final p = PlaylistsModel(Storage.at(dir));
      await p.load();
      expect(p.isFavouriteAlbum(harbour), isFalse);
      p.setFavouriteAlbums([harbour], true);
      expect(p.isFavouriteAlbum(harbour), isTrue);
      expect(p.isFavouriteAlbum(ferry), isFalse);

      final book = Book(id: 'book1', title: 'The Long Road', author: 'A. Writer', parts: [song('k1', 'The Long Road')]);
      p.setFavouriteBooks([book], true);
      expect(p.isFavouriteBook(book), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final again = PlaylistsModel(Storage.at(dir));
      await again.load();
      expect(again.isFavouriteAlbum(harbour), isTrue);
      expect(again.isFavouriteBook(book), isTrue);

      again.setFavouriteAlbums([harbour], false);
      expect(again.isFavouriteAlbum(harbour), isFalse);
      expect(again.isFavouriteBook(book), isTrue);
    });

    test('a favourite album stays one when a song is added to it or its files move', () async {
      final p = PlaylistsModel(Storage.at(dir));
      await p.load();
      p.setFavouriteAlbums([harbour], true);
      // A new song joins the album (e.g. after editing its album name): still a favourite.
      expect(p.isFavouriteAlbum(album('Harbour Lights', [a1, a2, song('a3', 'Harbour Lights')])), isTrue);
      // The files move.
      p.remapIds({a1.id: 'local:/new/a1.mp3', a2.id: 'local:/new/a2.mp3'});
      expect(p.isFavouriteAlbum(album('Harbour Lights', [song('x', 'Harbour Lights')])), isFalse);
      expect(p.referencedIds, containsAll(['local:/new/a1.mp3', 'local:/new/a2.mp3']));
      // Forgetting missing songs removes them from favourites too.
      p.removeIds({'local:/new/a1.mp3', 'local:/new/a2.mp3'});
      expect(p.referencedIds, isEmpty);
    });

    test('merging a backup keeps favourites from both', () {
      final merged = AppBackup.mergePlaylists(
        {'playlists': [], 'liked': [], 'favouriteAlbums': ['x'], 'favouriteBooks': ['b']},
        {'playlists': [], 'liked': [], 'favouriteAlbums': ['x', 'y']},
      );
      expect(merged['favouriteAlbums'], ['x', 'y']);
      expect(merged['favouriteBooks'], ['b']);
    });
  });

  testWidgets('an album tile\'s menu adds it to favourites, and it shows a heart', (tester) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final playlists = PlaylistsModel(Storage.at(dir));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LibraryModel(Storage.at(dir))),
        ChangeNotifierProvider.value(value: playlists),
        ChangeNotifierProvider(create: (_) => SelectionModel()),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: MaterialApp(
        home: Scaffold(body: Row(children: [SizedBox(width: 200, child: AlbumCard(album: harbour))])),
      ),
    ));
    expect(find.bySemanticsLabel('Favourite'), findsNothing);
    await tester.tap(find.text('Harbour Lights'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Add to favourites'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(playlists.isFavouriteAlbum(harbour), isTrue);
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.tap(find.text('Harbour Lights'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Remove from favourites'), findsOneWidget);
  });
}
