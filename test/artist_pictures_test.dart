// 0.1.53: choosing an artist's picture: an image file, one of their album covers, or back to the
// automatic one (their first album's cover). Kept in settings.json and in backups.
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_index.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/artist_screen.dart';
import 'package:hometunes/ui/widgets/cards.dart' show ArtistCard;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// Stands in for the player (the artist page's Play / Shuffle need one).
class FakePlayer extends ChangeNotifier implements PlayerModel {
  @override
  Track? get current => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Track t(String title, String album, {String? art}) => Track(
      id: 'local:/m/Band/$album/$title.mp3',
      source: TrackSource.local,
      title: title,
      artist: 'Band',
      album: album,
      albumArtist: 'Band',
      duration: const Duration(minutes: 3),
      path: '/m/Band/$album/$title.mp3',
      art: art,
    );

// Invented titles only.
List<Track> songs(String artDir) => [
      t('Paper Lanterns', 'First Light', art: p.join(artDir, 'first.jpg')),
      t('Slow Engines', 'Second Wind', art: p.join(artDir, 'second.jpg')),
    ];

void main() {
  late Directory dir;
  late Storage storage;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_artist_pictures');
    storage = Storage.at(dir);
    Directory(storage.artDir).createSync(recursive: true);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  LibraryModel model() {
    final tracks = songs(storage.artDir);
    final albums = groupAlbums(tracks);
    return LibraryModel(storage)
      ..tracks = tracks
      ..albums = albums
      ..artists = groupArtists(albums);
  }

  Album albumNamed(Artist a, String title) => a.albums.firstWhere((x) => x.title == title);

  group('LibraryModel', () {
    test('automatic, an album cover, a file, and back; saved in settings.json', () async {
      final lib = model();
      final band = lib.artistByName('Band')!;
      final first = band.albums.first.artTrack;
      expect(lib.artistAlbumArt(band), same(first));
      expect(lib.hasArtistPicture(band), isFalse);

      // One of their album covers.
      final other = band.albums.firstWhere((a) => a.artTrack != first);
      await lib.setArtistPicture(band, album: other);
      expect(lib.artistAlbumArt(band), same(other.artTrack));
      expect(lib.artistPictureFile(band), isNull);

      // An image file, copied in (it survives the clean-up of unused covers).
      final copy = await lib.importCoverBytes([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      await lib.setArtistPicture(band, file: copy);
      expect(lib.artistPictureFile(band), copy);
      await lib.setArtistPicture(lib.artistByName('Band')!, file: copy); // runs the clean-up again
      expect(File(copy).existsSync(), isTrue);
      final saved = await storage.read('settings.json') as Map;
      expect((saved['artistPictures'] as Map)['Band'], copy);

      // A path outside HomeTunes' pictures is never used.
      lib.artistPictures['Band'] = p.join(dir.path, '..', 'elsewhere.jpg');
      expect(lib.artistPictureFile(band), isNull);

      // Back to automatic: the copy is tidied away once nothing uses it.
      await lib.setArtistPicture(band, file: copy);
      await lib.setArtistPicture(band);
      expect(lib.hasArtistPicture(band), isFalse);
      expect(lib.artistAlbumArt(band), same(first));
    });

    test('a restored backup only keeps pictures inside the art folder', () {
      final root = dir.path;
      final art = p.join(root, 'art', 'custom', 'a.jpg');
      final cleaned = AppBackup.sanitize('settings.json', {
        'artistPictures': {
          'Inside': art,
          'Album': 'album:band|first light',
          'Outside': p.join(root, '..', 'secret.jpg'),
          'Wrong': 42,
        },
      }, root);
      expect(cleaned['artistPictures'], {'Inside': art, 'Album': 'album:band|first light'});
    });
  });

  group('On screen', () {
    Future<LibraryModel> pump(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final lib = model();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider(create: (_) => PlaylistsModel(storage)),
          ChangeNotifierProvider<PlayerModel>.value(value: FakePlayer()),
          ChangeNotifierProvider(create: (_) => SelectionModel()),
          ChangeNotifierProvider(create: (_) => AppNav()),
        ],
        child: MaterialApp(home: home),
      ));
      await tester.pump();
      return lib;
    }

    testWidgets('the artist page: Change picture › Use one of their album covers', (tester) async {
      final lib = await pump(tester, const ArtistScreen(name: 'Band'));
      final band = lib.artistByName('Band')!;
      await tester.tap(find.byKey(const ValueKey('artist-change-picture')));
      await tester.pumpAndSettle();
      expect(find.text('Picture for Band'), findsOneWidget);
      expect(find.byKey(const ValueKey('artist-picture-file')), findsOneWidget);
      expect(find.byKey(const ValueKey('artist-picture-auto')), findsNothing); // nothing chosen yet
      await tester.tap(find.byKey(const ValueKey('artist-picture-album')));
      await tester.pumpAndSettle();
      final second = albumNamed(band, 'Second Wind');
      await tester.tap(find.byKey(ValueKey('artist-album-pick:${second.key}')));
      await tester.pump();
      expect(lib.artistPictures['Band'], 'album:${second.key}');
      expect(lib.artistAlbumArt(band), same(second.artTrack));

      // Clicking the picture itself opens the same choices, now with "automatic".
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('artist-header-picture')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('artist-picture-auto')));
      await tester.pump();
      expect(lib.hasArtistPicture(band), isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('right-clicking an artist card offers Change picture…', (tester) async {
      final lib = await pump(tester, Builder(builder: (context) {
        final band = context.read<LibraryModel>().artistByName('Band')!;
        return Scaffold(body: Center(child: ArtistCard(artist: band, width: 180)));
      }));
      await tester.tap(find.byType(ArtistCard), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Change picture…'), findsOneWidget);
      expect(find.text('Use the automatic picture'), findsNothing);
      await tester.tap(find.text('Change picture…'));
      await tester.pumpAndSettle();
      expect(find.text('Picture for Band'), findsOneWidget);
      expect(lib.hasArtistPicture(lib.artistByName('Band')!), isFalse);
    });
  });
}
