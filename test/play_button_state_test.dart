// 0.1.82: the Play button on an album / playlist page and on an album's cover follows what's
// playing. While the music playing came from that album or playlist it shows Pause (Resume once
// paused) and pressing it pauses or carries on; for anything else it plays from the start.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/state/play_queue.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/ui/widgets/cards.dart';
import 'package:hometunes/ui/widgets/collection_header.dart';
import 'package:provider/provider.dart';

/// Stands in for the player with a real queue: playTracks fills it and plays, pause / play flip
/// "playing". How many times playTracks was used is counted.
class FakePlayer extends ChangeNotifier implements PlayerModel {
  @override
  final PlayQueue queue = PlayQueue();
  @override
  bool playing = false;
  int started = 0;

  @override
  Track? get current => queue.current;
  @override
  bool get inBook => false;

  @override
  Future<void> playTracks(List<Track> tracks, {int start = 0, bool? shuffle, String? label}) async {
    queue.setTracks(tracks, start: start, shuffle: shuffle, label: label);
    playing = true;
    started++;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    playing = false;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    playing = true;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Track t(String title, String album) => Track(
      id: 'local:/m/Band/$album/$title.mp3',
      source: TrackSource.local,
      title: title,
      artist: 'Band',
      album: album,
      albumArtist: 'Band',
      duration: const Duration(minutes: 3),
      path: '/m/Band/$album/$title.mp3',
    );

// Invented titles only.
final firstLight = [t('Paper Lanterns', 'First Light'), t('Harbour Wall', 'First Light')];
final secondWind = [t('Slow Engines', 'Second Wind'), t('Night Ferry', 'Second Wind')];

void main() {
  group('which music is playing', () {
    test('only the songs the queue was started from count', () async {
      final player = FakePlayer();
      expect(player.isPlayingFrom(firstLight), isFalse); // nothing playing
      await player.playTracks(firstLight, start: 1);
      expect(player.isPlayingFrom(firstLight), isTrue);
      expect(player.isPlayingNowFrom(firstLight), isTrue);
      expect(player.isPlayingFrom(secondWind), isFalse);
      expect(player.isPlayingFrom(firstLight.sublist(0, 1)), isFalse); // part of it isn't it
      await player.pause();
      expect(player.isPlayingFrom(firstLight), isTrue);
      expect(player.isPlayingNowFrom(firstLight), isFalse);
    });

    test('shuffled, it is still that album', () async {
      final player = FakePlayer();
      await player.playTracks([...firstLight, ...secondWind], shuffle: true);
      expect(player.isPlayingFrom([...firstLight, ...secondWind]), isTrue);
    });
  });

  Future<FakePlayer> pumpHeader(WidgetTester tester, List<Track> tracks, {FakePlayer? player}) async {
    final p = player ?? FakePlayer();
    await tester.pumpWidget(ChangeNotifierProvider<PlayerModel>.value(
      value: p,
      child: MaterialApp(
        home: Scaffold(
          body: CollectionHeader(
            art: const SizedBox(),
            kind: 'Album',
            title: 'First Light',
            subtitle: 'Band',
            tracks: tracks,
            contextLabel: 'First Light',
          ),
        ),
      ),
    ));
    return p;
  }

  IconData playIcon(WidgetTester tester) =>
      (tester.widget<IconButton>(find.byKey(const ValueKey('collection-play'))).icon as Icon).icon!;

  testWidgets('the page\'s Play button turns into Pause, then Resume, and does what it says', (tester) async {
    final player = await pumpHeader(tester, firstLight);
    expect(playIcon(tester), Icons.play_arrow_rounded);
    expect(find.byTooltip('Play'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('collection-play')));
    await tester.pump();
    expect(player.started, 1);
    expect(playIcon(tester), Icons.pause_rounded);
    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('collection-play')));
    await tester.pump();
    expect(player.playing, isFalse);
    expect(player.started, 1); // paused, not started again
    expect(playIcon(tester), Icons.play_arrow_rounded);
    expect(find.byTooltip('Resume'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('collection-play')));
    await tester.pump();
    expect(player.playing, isTrue);
    expect(player.started, 1); // carried on from where it was
    expect(playIcon(tester), Icons.pause_rounded);
  });

  testWidgets('another album playing: this page still offers Play, and plays its own songs', (tester) async {
    final player = FakePlayer();
    await player.playTracks(secondWind);
    await pumpHeader(tester, firstLight, player: player);
    expect(playIcon(tester), Icons.play_arrow_rounded);
    await tester.tap(find.byKey(const ValueKey('collection-play')));
    await tester.pump();
    expect(player.started, 2);
    expect(player.isPlayingFrom(firstLight), isTrue);
    expect(playIcon(tester), Icons.pause_rounded);
  });

  testWidgets('a cover\'s play button stays in view with Pause while its album plays', (tester) async {
    Widget cover({required bool active, required bool playing}) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: HoverPlayCover(
                active: active,
                playing: playing,
                onPlay: () {},
                child: const ColoredBox(color: Colors.grey),
              ),
            ),
          ),
        );
    double opacity() => tester
        .widget<AnimatedOpacity>(
            find.ancestor(of: find.byKey(const ValueKey('hover-play-button')), matching: find.byType(AnimatedOpacity)))
        .opacity;

    await tester.pumpWidget(cover(active: false, playing: false));
    expect(opacity(), 0); // only on hover
    await tester.pumpWidget(cover(active: true, playing: true));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pumpWidget(cover(active: true, playing: false));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byTooltip('Resume'), findsOneWidget);
  });
}
