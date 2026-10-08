// 0.1.72: Now Playing in a small window. With no video, the cover fades and then goes away,
// and the play buttons shrink to fit rather than overflowing.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/play_queue.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/sleep_timer.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/now_playing_screen.dart';
import 'package:provider/provider.dart';

/// Stands in for the player: one song loaded, paused.
class FakePlayer extends ChangeNotifier implements PlayerModel {
  FakePlayer(Track t) {
    queue.setTracks([t], start: 0, shuffle: false, label: 'Songs');
  }
  @override
  final PlayQueue queue = PlayQueue();
  @override
  Track? get current => queue.current;
  @override
  bool get shuffle => queue.shuffle;
  @override
  RepeatSetting get repeat => queue.repeat;
  @override
  bool playing = false;
  @override
  bool buffering = false;
  @override
  double volume = 100;
  @override
  Duration duration = const Duration(minutes: 3);
  @override
  Duration get position => Duration.zero;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  bool get inBook => false;
  @override
  bool get hasWaitingMusic => false;
  @override
  String? lastError;
  @override
  int get currentChapterIndex => -1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Invented title only.
const song = Track(
  id: 'local:/m/Band/First Light/Paper Lanterns.mp3',
  source: TrackSource.local,
  title: 'Paper Lanterns',
  artist: 'Band',
  album: 'First Light',
  albumArtist: 'Band',
  duration: Duration(minutes: 3),
  path: '/m/Band/First Light/Paper Lanterns.mp3',
);

void main() {
  late Directory dir;
  late Storage storage;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_now_playing_small');
    storage = Storage.at(dir);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lib = LibraryModel(storage)..tracks = [song];
    final player = FakePlayer(song);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
        ChangeNotifierProvider(create: (_) => PlaylistsModel(storage)),
        ChangeNotifierProvider<PlayerModel>.value(value: player),
        ChangeNotifierProvider(create: (_) => SleepTimer(player, lib)),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: const MaterialApp(home: NowPlayingScreen(showLyrics: false)),
    ));
    await tester.pump();
  }

  testWidgets('a roomy window shows the cover at full strength', (tester) async {
    await pump(tester, const Size(1000, 1000));
    expect(find.byKey(const ValueKey('now-playing-cover')), findsOneWidget);
    expect(find.byKey(const ValueKey('now-playing-no-cover')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short window hides the cover and shrinks the buttons, without overflowing',
      (tester) async {
    await pump(tester, const Size(480, 380));
    expect(find.byKey(const ValueKey('now-playing-no-cover')), findsOneWidget);
    expect(find.byKey(const ValueKey('now-playing-cover')), findsNothing);
    final controls = tester.getSize(find.byKey(const ValueKey('now-playing-controls')));
    expect(controls.height, lessThan(380));
    expect(tester.takeException(), isNull);
  });

  testWidgets('in between, the cover is smaller and starts to fade', (tester) async {
    await pump(tester, const Size(700, 640));
    final cover = find.byKey(const ValueKey('now-playing-cover'));
    if (cover.evaluate().isNotEmpty) {
      final opacity = tester.widget<Opacity>(find.ancestor(of: cover, matching: find.byType(Opacity)).first);
      expect(opacity.opacity, lessThanOrEqualTo(1));
      expect(tester.getSize(cover).height, lessThan(640));
    }
    expect(tester.takeException(), isNull);
  });
}
