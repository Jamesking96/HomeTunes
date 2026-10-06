// Tests for the Artists, Albums and Songs tabs' filters, sorting and title box (0.1.18).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_index.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/music_filters.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/library_screen.dart';
import 'package:hometunes/ui/widgets/cards.dart' show ArtistCard;
import 'package:provider/provider.dart';

Track t(String title, String artist, String album,
        {int? year, String? genre, int minutes = 3, int modified = 0, int? no}) =>
    Track(
      id: 'local:/m/$artist/$album/$title.mp3',
      source: TrackSource.local,
      title: title,
      artist: artist,
      album: album,
      albumArtist: artist,
      year: year,
      genre: genre,
      trackNumber: no,
      duration: Duration(minutes: minutes),
      path: '/m/$artist/$album/$title.mp3',
      modifiedMs: modified,
    );

final songs = [
  t('Blue in Green', 'Miles Davis', 'Kind of Blue', year: 1959, genre: 'Jazz', minutes: 5, modified: 10, no: 3),
  t('So What', 'Miles Davis', 'Kind of Blue', year: 1959, genre: 'Jazz', minutes: 9, modified: 10, no: 1),
  t('Yesterday', 'The Beatles', 'Help!', year: 1965, genre: 'Rock', minutes: 2, modified: 30, no: 13),
  t('Help!', 'The Beatles', 'Help!', year: 1965, genre: 'Rock', minutes: 2, modified: 30, no: 1),
  t('Blue Monday', 'New Order', 'Power, Corruption & Lies', year: 1983, genre: 'Electronic', modified: 20),
  t('Untitled', 'Nobody', 'No Year', modified: 5),
];

void main() {
  final albums = groupAlbums(songs);
  final artists = groupArtists(albums);

  group('title box', () {
    test('every typed word must be in the title, in any order, ignoring case', () {
      expect(titleMatches('Blue in Green', 'blue'), isTrue);
      expect(titleMatches('Blue in Green', 'green BLUE'), isTrue);
      expect(titleMatches('Blue in Green', 'blue monday'), isFalse);
      expect(titleMatches('Anything', '   '), isTrue);
    });
  });

  group('filters', () {
    test('albums by artist, genre and decade', () {
      final jazz = const MusicFilters({'Genre': 'Jazz'});
      expect([for (final a in albums) if (jazz.matches(a, albumFields)) a.title], ['Kind of Blue']);
      final sixties = const MusicFilters({'Decade': '1960s'});
      expect([for (final a in albums) if (sixties.matches(a, albumFields)) a.title], ['Help!']);
      final both = const MusicFilters({'Decade': '1960s', 'Genre': 'Jazz'});
      expect(albums.where((a) => both.matches(a, albumFields)), isEmpty);
    });

    test('choices are narrowed by the other picks, not by their own', () {
      final f = const MusicFilters({'Genre': 'Jazz'});
      final genre = albumFields.firstWhere((x) => x.label == 'Genre');
      final artist = albumFields.firstWhere((x) => x.label == 'Artist');
      // Genre choices ignore the genre pick itself…
      expect(f.choices(albums, albumFields, genre).keys, containsAll(['Jazz', 'Rock', 'Electronic']));
      // …but artists only offer the jazz ones.
      expect(f.choices(albums, albumFields, artist), {'Miles Davis': 1});
    });

    test('songs by album; decades come from years, none without one', () {
      final f = const MusicFilters({'Album': 'Help!'});
      expect([for (final s in songs) if (f.matches(s, songFields)) s.title], ['Yesterday', 'Help!']);
      expect(decadeOf(1983), '1980s');
      expect(decadeOf(null), isNull);
      expect(decadeOf(0), isNull);
    });

    test('withValue sets and removes a pick', () {
      final f = MusicFilters.none.withValue('Genre', 'Rock');
      expect(f.picked, {'Genre': 'Rock'});
      expect(f.withValue('Genre', null).isEmpty, isTrue);
    });
  });

  group('sorting', () {
    test('artists: name ignores "The", most songs, recently added', () {
      expect(sortArtists(artists, ArtistSort.name).map((a) => a.name),
          ['The Beatles', 'Miles Davis', 'New Order', 'Nobody']);
      expect(sortArtists(artists, ArtistSort.nameDescending).first.name, 'Nobody');
      expect(sortArtists(artists, ArtistSort.mostSongs).take(2).map((a) => a.name), ['The Beatles', 'Miles Davis']);
      expect(sortArtists(artists, ArtistSort.recentlyAdded).first.name, 'The Beatles');
    });

    test('albums: the year sorts are grouped by decade, no year last', () {
      final newest = sortAlbums(albums, AlbumSort.newest);
      expect(newest.map((g) => g.$1), ['1980s', '1960s', '1950s', noYear]);
      final oldest = sortAlbums(albums, AlbumSort.oldest);
      expect(oldest.map((g) => g.$1), ['1950s', '1960s', '1980s', noYear]);
      final byTitle = sortAlbums(albums, AlbumSort.title);
      expect(byTitle.single.$1, isNull);
      expect(byTitle.single.$2.map((a) => a.title), ['Help!', 'Kind of Blue', 'No Year', 'Power, Corruption & Lies']);
    });

    test('songs: by artist plays each album in order; longest first', () {
      expect(sortSongs(songs, SongSort.artist).take(4).map((s) => s.title), ['Help!', 'Yesterday', 'So What', 'Blue in Green']);
      expect(sortSongs(songs, SongSort.longest).first.title, 'So What');
      expect(sortSongs(songs, SongSort.newest).last.title, 'Untitled');
      expect(sortSongs(songs, SongSort.recentlyAdded).first.artist, 'The Beatles');
    });
  });

  group('Your Library tabs', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_libfilter'));
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<PlaylistsModel> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final lib = LibraryModel(Storage.at(dir))
        ..tracks = songs
        ..albums = albums
        ..artists = artists;
      final playlists = PlaylistsModel(Storage.at(dir));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: playlists),
          ChangeNotifierProvider(create: (_) => SelectionModel()),
          ChangeNotifierProvider(create: (_) => AppNav()),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ));
      return playlists;
    }

    testWidgets('Artists: typing narrows the list to matching names', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Artists'));
      await tester.pumpAndSettle();
      expect(find.text('New Order'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('library-title-filter')), 'beat');
      await tester.pumpAndSettle();
      expect(find.text('The Beatles'), findsOneWidget);
      expect(find.text('New Order'), findsNothing);
      expect(find.text('All (1)'), findsOneWidget);
      // Nothing matches: a message with a way out.
      await tester.enterText(find.byKey(const ValueKey('library-title-filter')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No artists match.'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('New Order'), findsOneWidget);
    });

    testWidgets('Artists: list and grid views, remembered (0.1.52)', (tester) async {
      await pump(tester);
      final lib = Provider.of<LibraryModel>(tester.element(find.byType(LibraryScreen)), listen: false);
      await tester.tap(find.text('Artists'));
      await tester.pumpAndSettle();
      // A list to start with.
      expect(find.byKey(const ValueKey('artists-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('artists-grid')), findsNothing);
      expect(find.byTooltip('Show as a grid'), findsOneWidget);
      expect(find.text('1 album · 2 songs'), findsNWidgets(2)); // Miles Davis and The Beatles

      // Grid: round cards with the same counts; filters and the title box still apply.
      await tester.tap(find.byKey(const ValueKey('artists-view')));
      await tester.pumpAndSettle();
      expect(lib.artistsGrid, isTrue);
      expect(find.byKey(const ValueKey('artists-grid')), findsOneWidget);
      expect(find.byType(ArtistCard), findsNWidgets(4));
      expect(find.text('1 album · 2 songs'), findsNWidgets(2));
      await tester.enterText(find.byKey(const ValueKey('library-title-filter')), 'order');
      await tester.pumpAndSettle();
      expect(find.byType(ArtistCard), findsOneWidget);
      expect(find.text('New Order'), findsOneWidget);

      // And back to the list.
      await tester.tap(find.byTooltip('Show as a list'));
      await tester.pumpAndSettle();
      expect(lib.artistsGrid, isFalse);
      expect(find.byKey(const ValueKey('artists-list')), findsOneWidget);
    });

    testWidgets('Albums: title box, genre filter chip and the year sort', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      expect(find.text('Kind of Blue'), findsOneWidget);
      expect(find.text('Help!'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('library-title-filter')), 'blue');
      await tester.pumpAndSettle();
      expect(find.text('Kind of Blue'), findsOneWidget);
      expect(find.text('Help!'), findsNothing);
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Help!'), findsOneWidget);

      // Filter sheet: pick the Rock genre.
      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-Genre')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rock  (1)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show albums'));
      await tester.pumpAndSettle();
      expect(find.text('Genre: Rock'), findsOneWidget);
      expect(find.text('Help!'), findsOneWidget);
      expect(find.text('Kind of Blue'), findsNothing);
      // Removing the chip brings everything back.
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Kind of Blue'), findsOneWidget);

      // Year sort: decade headings.
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Year').last, warnIfMissed: false); // the menu is still animating in
      await tester.pumpAndSettle();
      expect(find.text('1980s'), findsOneWidget);
      expect(find.text('1950s'), findsOneWidget);
      expect(tester.getTopLeft(find.text('1980s')).dy, lessThan(tester.getTopLeft(find.text('1950s')).dy));

      // Ascending / descending (0.1.69): Year starts newest first; Ascending turns it round.
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      expect(find.text('Descending (Newest first)'), findsOneWidget);
      await tester.tap(find.text('Ascending (Oldest first)'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('1950s')).dy, lessThan(tester.getTopLeft(find.text('1980s')).dy));
      // Another sort starts in its own usual direction again.
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      final ascending = tester.widget<CheckedPopupMenuItem<Object>>(find.byKey(const ValueKey('sort-ascending')));
      expect(ascending.checked, isTrue);
      expect(find.text('Ascending (A to Z)'), findsOneWidget);
    });
  });
}
