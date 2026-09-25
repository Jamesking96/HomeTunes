// Selecting several albums or audiobooks and editing them together: the
// selection itself, the Select menu on album tiles, and the editors, where a
// detail that differs shows --:-- and is kept unless something is typed.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/edit_book.dart';
import 'package:hometunes/ui/screens/edit_details.dart';
import 'package:hometunes/ui/widgets/cards.dart';
import 'package:provider/provider.dart';

Track song(String id, String album, {String artist = 'Tidewater', int? year, String? genre, String ext = 'mp3'}) =>
    Track(
      id: 'local:/m/$id.$ext',
      source: TrackSource.local,
      title: id,
      artist: artist,
      album: album,
      albumArtist: artist,
      year: year,
      genre: genre,
      duration: const Duration(minutes: 3),
      path: '/m/$id.$ext',
    );

void main() {
  group('Selection', () {
    test('albums, books and songs are selected one kind at a time', () {
      final s = SelectionModel();
      s.start('a1', kind: SelectKind.albums, scope: ['a1', 'a2', 'a3']);
      expect(s.selecting(SelectKind.albums), isTrue);
      expect(s.contains('a1', kind: SelectKind.albums), isTrue);
      expect(s.contains('a1'), isFalse); // not a song
      expect(s.canSelectAll, isTrue);
      s.selectScope();
      expect(s.count, 3);
      expect(s.canSelectAll, isFalse);
      s.toggle('song');
      expect(s.kind, SelectKind.songs);
      expect(s.ids, {'song'});
    });

    test('Select all straight away ticks everything shown', () {
      final s = SelectionModel()..start('b2', kind: SelectKind.books, scope: ['b1', 'b2'], all: true);
      expect(s.ids, {'b1', 'b2'});
      s.clear();
      expect(s.active, isFalse);
      expect(s.canSelectAll, isFalse);
    });
  });

  group('Editing together', () {
    late Directory dir;
    late LibraryModel lib;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('hometunes_multi');
      final storage = Storage.at(dir);
      await storage.write('library.json', {
        'local': [
          song('a1', 'Harbour Lights', year: 2001, genre: 'Folk').toJson(),
          song('a2', 'Harbour Lights', year: 2001, genre: 'Folk', artist: 'Tidewater').toJson(),
          song('b1', 'Night Ferry', year: 2004, genre: 'Folk').toJson(),
          song('c1', 'Paper Kites', year: 2010, genre: 'Pop', artist: 'Mira Olsen').toJson(),
          song('k1', 'The Long Road', artist: 'A. Writer', genre: 'Audiobook', ext: 'm4b').toJson(),
          song('k2', 'The Short Road', artist: 'B. Writer', genre: 'Audiobook', ext: 'm4b').toJson(),
        ],
        'remote': [],
        'missing': [],
      });
      lib = LibraryModel(storage);
      await lib.load();
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      dir.deleteSync(recursive: true);
    });

    Future<void> pump(WidgetTester tester, Future<bool> Function(BuildContext) open) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider(create: (_) => SelectionModel()),
          ChangeNotifierProvider(create: (_) => AppNav()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(child: TextButton(onPressed: () => open(context), child: const Text('open'))),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
    }

    Album album(String title) => lib.albums.firstWhere((a) => a.title == title);

    testWidgets('two albums: no album title box, --:-- where they differ, only the typed detail changes',
        (tester) async {
      final picked = [album('Harbour Lights'), album('Paper Kites')];
      await pump(tester, (c) => showEditDetails(c, [for (final a in picked) ...a.tracks], albumCount: 2));
      expect(find.text('Edit 2 albums'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Album'), findsNothing);
      // Album artist, artist, year and genre all differ.
      final keeping = find.textContaining('Different for each album');
      expect(find.text(differentMarker), findsNWidgets(4));
      expect(keeping, findsNWidgets(4));

      final genre = find.widgetWithText(TextField, 'Genre');
      await tester.enterText(genre, 'Jazz');
      await tester.pump();
      expect(find.text('Every album gets this genre'), findsOneWidget);
      expect(keeping, findsNWidgets(3));
      // Typed in year, then changed my mind: back to --:--.
      final year = find.widgetWithText(TextField, 'Year');
      await tester.enterText(year, '1999');
      await tester.pump();
      expect(keeping, findsNWidgets(2));
      await tester.tap(find.byTooltip('Keep each album\'s own year'));
      await tester.pump();
      expect(keeping, findsNWidgets(3));
      await save(tester);

      expect(album('Harbour Lights').tracks.every((t) => t.genre == 'Jazz'), isTrue);
      expect(album('Paper Kites').tracks.single.genre, 'Jazz');
      expect(album('Harbour Lights').year, 2001);
      expect(album('Paper Kites').year, 2010);
      expect(album('Paper Kites').artist, 'Mira Olsen');
      expect(album('Night Ferry').tracks.single.genre, 'Folk'); // not selected
    });

    testWidgets('several songs show --:-- too', (tester) async {
      final songs = [album('Harbour Lights').tracks.first, album('Paper Kites').tracks.first];
      await pump(tester, (c) => showEditDetails(c, songs));
      expect(find.text('Edit 2 songs'), findsOneWidget);
      expect(find.text(differentMarker), findsWidgets);
      expect(find.textContaining('Mixed'), findsNothing);
    });

    testWidgets('two books: no title or number boxes, --:-- where they differ, only the typed detail changes',
        (tester) async {
      expect(lib.books.length, 2);
      await pump(tester, (c) => showEditBooks(c, lib.books));
      expect(find.text('Edit 2 books'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Title'), findsNothing);
      expect(find.widgetWithText(TextField, 'Number in series'), findsNothing);
      expect(find.textContaining('Different for each book'), findsOneWidget); // only the author differs
      await tester.enterText(find.widgetWithText(TextField, 'Narrator'), 'Kim Reader');
      await save(tester);

      expect(lib.books.every((b) => b.narrator == 'Kim Reader'), isTrue);
      expect({for (final b in lib.books) b.author}, {'A. Writer', 'B. Writer'});
      expect({for (final b in lib.books) b.title}, {'The Long Road', 'The Short Road'});
    });

    testWidgets('right-clicking an album offers Select; then a tap ticks instead of opening', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sel = SelectionModel();
      final albums = lib.albums;
      final keys = [for (final a in albums) a.key];
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: sel),
          ChangeNotifierProvider(create: (_) => AppNav()),
          ChangeNotifierProvider(create: (_) => PlaylistsModel(Storage.at(dir))),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Row(children: [
              for (final a in albums.take(3)) SizedBox(width: 180, child: AlbumCard(album: a, scope: keys)),
            ]),
          ),
        ),
      ));
      await tester.tap(find.text(albums[0].title), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Select'), findsOneWidget);
      expect(find.text('Select all (${keys.length})'), findsOneWidget);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(sel.selecting(SelectKind.albums), isTrue);
      expect(sel.ids, {albums[0].key});

      await tester.tap(find.text(albums[1].title));
      await tester.pump();
      expect(sel.ids, {albums[0].key, albums[1].key});
      await tester.tap(find.text(albums[0].title));
      await tester.pump();
      expect(sel.ids, {albums[1].key});
    });
  });
}
