// Tests for the 29 Sep feedback (0.1.26): the queue opens as a drawer from the side; on an
// artist page an album's songs open in place under its row, with "Open album page" in its
// right-click menu; and hovering an album cover shows a play button that plays it.
// The real player needs the audio engine, so a stand-in records what would have played.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_index.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/artist_screen.dart';
import 'package:hometunes/ui/screens/queue_screen.dart';
import 'package:provider/provider.dart';

/// Stands in for the player: nothing is playing, and playTracks is recorded.
class FakePlayer extends ChangeNotifier implements PlayerModel {
  List<Track>? played;
  String? playedLabel;
  bool? playedShuffled;

  @override
  Track? get current => null;

  @override
  Future<void> playTracks(List<Track> tracks, {int start = 0, bool? shuffle, String? label}) async {
    played = tracks;
    playedLabel = label;
    playedShuffled = shuffle;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Track t(String title, String album, {int no = 1, int? year}) => Track(
      id: 'local:/m/Band/$album/$title.mp3',
      source: TrackSource.local,
      title: title,
      artist: 'Band',
      album: album,
      albumArtist: 'Band',
      year: year,
      trackNumber: no,
      duration: const Duration(minutes: 3),
      path: '/m/Band/$album/$title.mp3',
    );

// Invented titles only.
final songs = [
  t('Paper Lanterns', 'First Light', no: 1, year: 2001),
  t('Harbour Wall', 'First Light', no: 2, year: 2001),
  t('Slow Engines', 'Second Wind', no: 1, year: 2004),
  t('Copper Sky', 'Second Wind', no: 2, year: 2004),
];

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_ui_feedback'));
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    dir.deleteSync(recursive: true);
  });

  Future<FakePlayer> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final albums = groupAlbums(songs);
    final lib = LibraryModel(Storage.at(dir))
      ..tracks = songs
      ..albums = albums
      ..artists = groupArtists(albums);
    final player = FakePlayer();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
        ChangeNotifierProvider(create: (_) => PlaylistsModel(Storage.at(dir))),
        ChangeNotifierProvider<PlayerModel>.value(value: player),
        ChangeNotifierProvider(create: (_) => SelectionModel()),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: MaterialApp(home: home),
    ));
    await tester.pump();
    return player;
  }

  group('Artist page', () {
    testWidgets('clicking an album shows its songs underneath; clicking again hides them', (tester) async {
      await pump(tester, const ArtistScreen(name: 'Band'));
      expect(find.byType(AlbumSongsPanel), findsNothing);

      await tester.tap(find.text('Second Wind').first);
      await tester.pumpAndSettle();
      expect(find.byType(AlbumSongsPanel), findsOneWidget);
      final panel = find.byType(AlbumSongsPanel);
      expect(find.descendant(of: panel, matching: find.text('Slow Engines')), findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('Paper Lanterns')), findsNothing);
      expect(find.byType(ArtistScreen), findsOneWidget); // still the same page

      // Another album swaps the panel over; the same one again closes it.
      await tester.tap(find.text('First Light').first);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(AlbumSongsPanel), matching: find.text('Paper Lanterns')), findsOneWidget);
      await tester.tap(find.text('First Light').first);
      await tester.pumpAndSettle();
      expect(find.byType(AlbumSongsPanel), findsNothing);
    });

    testWidgets('the panel plays and shuffles the album, and has Open album page and Close', (tester) async {
      final player = await pump(tester, const ArtistScreen(name: 'Band'));
      await tester.tap(find.text('Second Wind').first);
      await tester.pumpAndSettle();
      final panel = find.byType(AlbumSongsPanel);
      await tester.tap(find.descendant(of: panel, matching: find.byTooltip('Play')));
      expect(player.played?.map((s) => s.title), ['Slow Engines', 'Copper Sky']);
      expect(player.playedLabel, 'Album · Second Wind');
      await tester.tap(find.descendant(of: panel, matching: find.byTooltip('Shuffle')));
      expect(player.playedShuffled, isTrue);
      expect(find.byKey(const ValueKey('panel-open-page')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('panel-close')));
      await tester.pumpAndSettle();
      expect(find.byType(AlbumSongsPanel), findsNothing);
    });

    testWidgets('right-clicking an album offers "Open album page"', (tester) async {
      await pump(tester, const ArtistScreen(name: 'Band'));
      await tester.tap(find.text('Second Wind').first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Open album page'), findsOneWidget);
      expect(find.text('Select'), findsOneWidget); // the usual menu is still there
    });

    testWidgets('hovering a cover shows a play button that plays the album', (tester) async {
      final player = await pump(tester, const ArtistScreen(name: 'Band'));
      final cover = find.byKey(ValueKey('hover-play:${groupAlbums(songs).firstWhere((a) => a.title == 'First Light').key}'));
      final button = find.descendant(of: cover, matching: find.byKey(const ValueKey('hover-play-button')));
      double opacity() => tester.widget<AnimatedOpacity>(find.ancestor(of: button, matching: find.byType(AnimatedOpacity))).opacity;
      expect(opacity(), 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(cover));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      await tester.tap(button);
      await tester.pump();
      expect(player.played?.map((s) => s.title), ['Paper Lanterns', 'Harbour Wall']);
      expect(find.byType(AlbumSongsPanel), findsNothing); // playing doesn't open the songs
    });
  });

  group('Queue drawer', () {
    test('takes up to 420 px, never more than 88% of the window', () {
      expect(QueuePanel.widthFor(1600), 420);
      expect(QueuePanel.widthFor(400), closeTo(352, 0.01));
    });

    testWidgets('slides in over the page and closes by tapping outside', (tester) async {
      await pump(
        tester,
        Scaffold(body: Builder(builder: (context) => Center(
          child: TextButton(onPressed: () => openQueueDrawer(context), child: const Text('open queue')),
        ))),
      );
      await tester.tap(find.text('open queue'));
      await tester.pumpAndSettle();
      final drawer = find.byKey(const ValueKey('queue-drawer'));
      expect(drawer, findsOneWidget);
      expect(find.text('The queue is empty'), findsOneWidget);
      expect(find.text('open queue'), findsOneWidget); // the page is still there underneath
      // On the right-hand side, 420 px wide on a 1000 px window.
      expect(tester.getSize(drawer).width, 420);
      expect(tester.getTopRight(drawer).dx, 1000);

      await tester.tapAt(const Offset(100, 800)); // outside the drawer
      await tester.pumpAndSettle();
      expect(drawer, findsNothing);
    });

    testWidgets('its close button and a swipe to the right close it too', (tester) async {
      await pump(
        tester,
        Scaffold(body: Builder(builder: (context) => Center(
          child: TextButton(onPressed: () => openQueueDrawer(context), child: const Text('open queue')),
        ))),
      );
      await tester.tap(find.text('open queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('queue-drawer')), findsNothing);

      await tester.tap(find.text('open queue'));
      await tester.pumpAndSettle();
      await tester.fling(find.text('Queue'), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('queue-drawer')), findsNothing);
    });
  });
}
