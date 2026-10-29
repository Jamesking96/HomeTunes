// The TV interface, step 5 (0.2.0): the players. The progress bar the remote moves along
// (TvSeekBar), and the TV video player (TvVideoView) driving a real VideoSession over a pretend
// engine: the controls coming and going, Back, the panels, Up next and the remote's media keys.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/engine/video_engine.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/state/video_session.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:hometunes/ui/tv/tv_seek_bar.dart';
import 'package:hometunes/ui/tv/tv_video_player.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'fake_audio_engine.dart';
import 'fake_video_engine.dart';

/// Two episodes of Coastline, without scanning (the files needn't exist).
class _Videos extends VideoLibraryModel {
  _Videos(super.storage, super.library) {
    final list = [
      for (final e in [1, 2])
        VideoItem(
          id: 'local:/v/Coastline S01E0$e.mkv',
          path: '/v/Coastline S01E0$e.mkv',
          title: e == 1 ? 'The Harbour' : 'Low Water',
          collection: 'Coastline',
          season: 1,
          episode: e,
          duration: const Duration(minutes: 20),
        ),
    ];
    videos = list;
    collections = [VideoCollection(name: 'Coastline', videos: list)];
  }

  @override
  VideoItem? byId(String id) => videos.where((v) => v.id == id).firstOrNull;
  @override
  VideoCollection? collectionNamed(String name) => collections.where((c) => c.name == name).firstOrNull;
  @override
  String? playableFile(VideoItem v) => v.path;
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(key);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('the progress bar', () {
    late List<Duration> seeks;
    late int activated;
    late FocusNode node;
    late StreamController<Duration> ticks;

    Future<void> pumpBar(WidgetTester tester) async {
      seeks = [];
      activated = 0;
      node = FocusNode();
      ticks = StreamController<Duration>.broadcast();
      addTearDown(node.dispose);
      addTearDown(ticks.close);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              child: TvSeekBar(
                focusNode: node,
                position: () => const Duration(minutes: 1),
                length: () => const Duration(minutes: 4),
                positions: ticks.stream,
                onSeek: seeks.add,
                onActivate: () => activated++,
              ),
            ),
          ),
        ),
      ));
      node.requestFocus();
      await tester.pump();
    }

    testWidgets('→ → put a marker 20 s on; OK jumps there', (tester) async {
      await pumpBar(tester);
      await press(tester, LogicalKeyboardKey.arrowRight, 2);
      expect(find.text('1:20'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.select);
      expect(seeks, [const Duration(minutes: 1, seconds: 20)]);
      expect(find.byKey(const ValueKey('tv-seek-target')), findsNothing);
    });

    testWidgets('resting on the marker jumps there by itself', (tester) async {
      await pumpBar(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pump(TvSeekBar.jumpAfter);
      expect(seeks, [const Duration(seconds: 50)]);
    });

    testWidgets('Back puts the marker away; OK with no marker plays / pauses', (tester) async {
      await pumpBar(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pump(TvSeekBar.jumpAfter);
      expect(seeks, isEmpty);
      await press(tester, LogicalKeyboardKey.select);
      expect(activated, 1);
    });

    test('held down, each step goes further, but never more than a tenth', () {
      const length = Duration(hours: 2);
      expect(TvSeekBar.step(length, 0), const Duration(seconds: 10)); // 10 s to start, even in 2 h (0.2.5)
      expect(TvSeekBar.step(length, 3), const Duration(seconds: 20));
      expect(TvSeekBar.step(length, 100), const Duration(seconds: 340));
      expect(TvSeekBar.step(length, 1000), const Duration(minutes: 12)); // at most a tenth
      expect(TvSeekBar.step(const Duration(minutes: 4), 0), const Duration(seconds: 10));
    });
  });

  group('the video player', () {
    late Directory dir;
    late LibraryModel lib;
    late _Videos videos;
    late PlayerModel music;
    late FakeVideoEngine engine;
    late VideoSession session;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_tv_players');
      final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      lib = LibraryModel(storage);
      videos = _Videos(storage, lib);
      music = PlayerModel(lib, engine: FakeAudioEngine());
      engine = FakeVideoEngine();
    });
    tearDown(() async {
      music.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// The player opened over a page, its first video loaded and playing.
    Future<void> pumpPlayer(WidgetTester tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      session = VideoSession(
        engine: engine,
        videos: videos,
        music: music,
        videoId: 'local:/v/Coastline S01E01.mkv',
        upNextTick: const Duration(milliseconds: 100),
        tracksSettle: Duration.zero,
        openingTimeout: const Duration(seconds: 1),
      );
      await tester.pumpWidget(MultiProvider(
        providers: [
          ...libraryProviders(lib),
          ChangeNotifierProvider<VideoLibraryModel>.value(value: videos),
          ChangeNotifierProvider(create: (_) => AppNav()),
        ],
        child: MaterialApp(
          theme: tvTheme(buildTheme(), AppColors.accent),
          builder: (context, child) => TvFocus(enabled: true, child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TvVideoView(session: session, picture: const ColoredBox(color: Colors.indigo)),
                  )),
                  child: const Text('Watch'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Watch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // the page slides in
      engine.loaded(
        audio: const [MediaTrack('1', language: 'eng'), MediaTrack('2', language: 'jpn')],
        subtitles: const [MediaTrack('3', language: 'eng')],
      );
      engine.moveTo(const Duration(minutes: 5));
      session.shown();
      await tester.pump();
    }

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

    /// Closes everything and lets its timers run out (the test checks none are left).
    Future<void> done(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await tester.pump(const Duration(seconds: 15));
    }

    testWidgets('opens with the controls up and the bar in focus; → and OK move through the video', (tester) async {
      await pumpPlayer(tester);
      expect(find.text('The Harbour'), findsOneWidget);
      expect(find.text('Coastline · Season 1 · Episode 1'), findsOneWidget);
      expect(focused(), 'tv video bar');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text('5:10'), findsOneWidget); // the marker
      await press(tester, LogicalKeyboardKey.select);
      expect(engine.calls.last, 'seek 0:05:10.000000');
      await done(tester);
    });

    testWidgets('the controls fade while it plays; the first press only brings them back; Back hides them, then closes', (tester) async {
      await pumpPlayer(tester);
      await tester.pump(TvVideoView.hideAfter + const Duration(seconds: 1));
      expect(focused(), 'tv video (controls hidden)');
      final seeks = engine.calls.where((c) => c.startsWith('seek')).length;
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 300));
      expect(focused(), 'tv video bar');
      expect(engine.calls.where((c) => c.startsWith('seek')).length, seeks); // nothing moved
      await tester.binding.handlePopRoute(); // Back
      await tester.pump(const Duration(milliseconds: 300));
      expect(focused(), 'tv video (controls hidden)');
      expect(find.byType(TvVideoView), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TvVideoView), findsNothing);
      await done(tester);
    });

    testWidgets('paused, the controls stay up', (tester) async {
      await pumpPlayer(tester);
      await press(tester, LogicalKeyboardKey.select); // OK on the bar: pause
      expect(engine.isPlaying, isFalse);
      await tester.pump(TvVideoView.hideAfter * 2);
      expect(focused(), 'tv video bar');
      await done(tester);
    });

    testWidgets('paused, Back hides the controls first, then closes (27 Oct)', (tester) async {
      await pumpPlayer(tester);
      await press(tester, LogicalKeyboardKey.select); // pause
      expect(engine.isPlaying, isFalse);
      // The remote's Back, pressed and let go: used here, both are taken (Android would otherwise
      // go back on the letting go and close the player too).
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.browserBack, platform: 'web'), isTrue);
      expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.browserBack, platform: 'web'), isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(focused(), 'tv video (controls hidden)');
      expect(find.byType(TvVideoView), findsOneWidget);
      // With the controls hidden, the remote's Back is left to the system's Back, which closes it.
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.browserBack, platform: 'web'), isFalse);
      expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.browserBack, platform: 'web'), isFalse);
      await tester.binding.handlePopRoute(); // Back, the system's
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TvVideoView), findsNothing);
      await done(tester);
    });

    testWidgets('the remote\'s media keys work whatever has focus', (tester) async {
      await pumpPlayer(tester);
      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      expect(engine.isPlaying, isFalse);
      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      expect(engine.isPlaying, isTrue);
      await press(tester, LogicalKeyboardKey.mediaTrackNext);
      await tester.pump();
      expect(engine.openName, 'Coastline S01E02');
      await done(tester);
    });

    testWidgets('Audio & subtitles › Audio lists the tracks; choosing one switches to it', (tester) async {
      await pumpPlayer(tester);
      Future<void> settle() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      await tester.tap(find.byKey(const ValueKey('tv-video-tracks')));
      await settle();
      expect(find.text('Audio & subtitles'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('tv-option-Audio')));
      await settle();
      expect(find.textContaining('Japanese'), findsOneWidget);
      await tester.tap(find.textContaining('Japanese'));
      await settle();
      expect(engine.calls, contains('audio 2'));
      await done(tester);
    });

    testWidgets('at the end: Up next has focus on Play now; OK plays the next episode', (tester) async {
      await pumpPlayer(tester);
      engine.finish();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('tv-up-next')), findsOneWidget);
      expect(find.textContaining('Low Water'), findsOneWidget);
      expect(focused(), 'tv up next play now');
      await press(tester, LogicalKeyboardKey.select);
      await tester.pump();
      expect(engine.openName, 'Coastline S01E02');
      await done(tester);
    });

    // 23 Oct, on the TV: moving left from Audio & subtitles while a video played lost its way.
    testWidgets('the buttons: ← and → go along the row, both ways, past Audio & subtitles', (tester) async {
      await pumpPlayer(tester);
      String? key() {
        String? found;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
          final k = e.widget.key;
          if (k is ValueKey<String> && k.value.startsWith('tv-video-')) {
            found = k.value;
            return false;
          }
          return true;
        });
        return found;
      }

      await press(tester, LogicalKeyboardKey.arrowDown); // off the bar onto the buttons
      expect(key(), 'tv-video-play'); // Play / Pause, at the start of the row (0.2.5)
      // Along to Audio & subtitles, then left, past it, to the start of the row.
      for (var i = 0; i < 3; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      expect(key(), 'tv-video-tracks');
      final left = <String?>[];
      for (var i = 0; i < 4; i++) {
        await press(tester, LogicalKeyboardKey.arrowLeft);
        left.add(key());
      }
      expect(left, ['tv-video-ahead', 'tv-video-back', 'tv-video-play', 'tv-video-play']);
      // Then right all the way along, and back.
      final right = <String?>[];
      for (var i = 0; i < 8; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
        right.add(key());
      }
      expect(right, ['tv-video-back', 'tv-video-ahead', 'tv-video-tracks', 'tv-video-speed', 'tv-video-episodes', 'tv-video-next', 'tv-video-more', 'tv-video-more']);
      for (var i = 0; i < 4; i++) {
        await press(tester, LogicalKeyboardKey.arrowLeft);
      }
      expect(key(), 'tv-video-tracks');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(key(), 'tv-video-ahead');
      expect(engine.isPlaying, isTrue); // still playing, and the controls still up
      expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('tv video (controls hidden)'));
      await done(tester);
    });

    testWidgets('holding OK on the bar opens the options, Watch from the beginning first; a short press pauses', (tester) async {
      await pumpPlayer(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('tv-option-Watch from the beginning')), findsOneWidget);
      expect(engine.isPlaying, isTrue); // held: not paused
      await tester.tap(find.byKey(const ValueKey('tv-option-Watch from the beginning')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(engine.calls.last, 'seek 0:00:00.000000');
      await press(tester, LogicalKeyboardKey.select);
      expect(engine.isPlaying, isFalse);
      await done(tester);
    });
  });
}
