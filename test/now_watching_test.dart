// 30 Sep: the video playing on its page in the bottom player bar and the system media controls
// (NowWatching, VideoPlayerBar, MediaSession), and the mouse wheel over a progress bar skipping
// 5 seconds (wheelSeekTarget, WheelSeek on the music / book SeekBar and the video's bar).
import 'dart:async';

import 'package:audio_service/audio_service.dart' show MediaAction;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/media_session.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/now_watching.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/ui/widgets/player_controls.dart';
import 'package:hometunes/ui/widgets/wheel_seek.dart';
import 'package:provider/provider.dart';

/// The music player, as far as these tests need it.
class FakeMusic extends ChangeNotifier implements PlayerModel {
  @override
  bool playing = false;
  @override
  Duration position = const Duration(seconds: 30);
  @override
  Duration duration = const Duration(minutes: 3);
  final seeks = <Duration>[];
  final _positions = StreamController<Duration>.broadcast();
  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Track? get current => null;
  @override
  bool get inBook => false;
  @override
  Future<void> seek(Duration to) async => seeks.add(to);
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

class FakeLibrary extends ChangeNotifier implements LibraryModel {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A video player without the engine.
class FakeVideo implements VideoTransport {
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  @override
  bool playing = false;
  @override
  Duration position = const Duration(minutes: 10);
  @override
  Duration duration = const Duration(minutes: 45);
  @override
  double volume = 100;
  @override
  double get rate => 1.0;
  final seeks = <Duration>[];

  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration> get durationStream => _duration.stream;
  @override
  Future<void> play() async {
    playing = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    playing = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration to) async {
    seeks.add(to);
    position = to;
  }

  final _volume = StreamController<double>.broadcast();
  @override
  Stream<double> get volumeStream => _volume.stream;

  @override
  Future<void> setVolume(double v) async {
    volume = v;
    _volume.add(v);
  }
}

const _episode = VideoItem(
  id: 'video:/v/Silo S01E02.mkv',
  path: '/v/Silo S01E02.mkv',
  title: 'Holston\'s Pick',
  collection: 'Silo',
  season: 1,
  episode: 2,
);

/// Lets stream events reach their listeners.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('the mouse wheel over a progress bar', () {
    test('up goes forward 5 s, down back 5 s, kept inside the file', () {
      const len = Duration(minutes: 3);
      expect(wheelSeekTarget(const Duration(seconds: 30), len, -1), const Duration(seconds: 35));
      expect(wheelSeekTarget(const Duration(seconds: 30), len, 1), const Duration(seconds: 25));
      expect(wheelSeekTarget(const Duration(seconds: 3), len, 1), Duration.zero);
      expect(wheelSeekTarget(const Duration(seconds: 178), len, -1), len);
      expect(wheelSeekTarget(const Duration(seconds: 30), Duration.zero, -1), const Duration(seconds: 35));
      expect(wheelSeekTarget(const Duration(seconds: 30), len, 0), isNull);
    });

    testWidgets('over the music bar: notches skip, and quick ones add up', (tester) async {
      final music = FakeMusic();
      await tester.pumpWidget(
        ChangeNotifierProvider<PlayerModel>.value(
          value: music,
          child: const MaterialApp(
            home: Scaffold(
              body: Center(child: SizedBox(width: 400, child: SeekBar(compact: true))),
            ),
          ),
        ),
      );
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final at = tester.getCenter(find.byType(SeekBar));
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -40)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -40)));
      expect(music.seeks, [const Duration(seconds: 35), const Duration(seconds: 40)]);
      // Later, from where the player really is.
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
      expect(music.seeks.last, const Duration(seconds: 25));
    });
  });

  group('NowWatching', () {
    test('comes to the front when the video plays, and goes when music starts', () async {
      final music = FakeMusic();
      final w = NowWatching(music);
      final video = FakeVideo();
      w.attach(video);
      w.showing(_episode, skipBack: 10, skipForward: 30);
      expect(w.inFront, isFalse); // not playing yet
      await video.play();
      await settle();
      expect(w.inFront, isTrue);

      await music.play();
      expect(w.inFront, isFalse);

      // Play from the bar / media keys: the music pauses and the video is back in front.
      await w.play();
      await settle();
      expect((music.playing, video.playing, w.inFront), (false, true, true));

      await w.skip(forward: true);
      expect(video.seeks.last, const Duration(minutes: 10, seconds: 30));
      video.position = const Duration(minutes: 44, seconds: 50);
      await w.skip(forward: true);
      expect(video.seeks.last, const Duration(minutes: 45)); // not past the end

      w.detach(video);
      expect((w.inFront, w.video), (false, null));
    });

    test('music to video: the bar switches even if the "started" signal was missed', () async {
      final music = FakeMusic();
      final w = NowWatching(music);
      final video = FakeVideo();
      w.attach(video);
      w.showing(_episode);
      await music.play();
      var told = 0;
      w.addListener(() => told++);
      // The video starts, but its "playing" signal never reaches NowWatching...
      video.playing = true;
      await music.pause();
      // ...the video moving (or the music stopping) is enough.
      expect(w.inFront, isTrue);
      expect(told, greaterThan(0));

      // And from the position alone, with the music already quiet.
      final w2 = NowWatching(FakeMusic());
      final v2 = FakeVideo();
      w2.attach(v2);
      w2.showing(_episode);
      v2.playing = true;
      v2._position.add(const Duration(minutes: 10, seconds: 1));
      await settle();
      expect(w2.inFront, isTrue);
    });

    test('the video player\'s own volume changes reach the bar', () async {
      final w = NowWatching(FakeMusic());
      final video = FakeVideo();
      w.attach(video);
      var told = 0;
      w.addListener(() => told++);
      await video.setVolume(40); // as the player page's volume bar does
      await settle();
      expect((w.volume, told > 0), (40.0, true));
    });

    test('a second video page closing hands the bar back to the one still open', () async {
      final w = NowWatching(FakeMusic());
      final first = FakeVideo()..playing = true, second = FakeVideo();
      const other = VideoItem(id: 'video:/v/Other.mkv', path: '/v/Other.mkv', title: 'Other', collection: 'Other');
      w.attach(first);
      w.showing(_episode, transport: first);
      w.attach(second);
      w.showing(other, transport: second);
      expect(w.video?.title, 'Other');
      // The page underneath moving on only changes its own record.
      w.showing(_episode, transport: first, skipBack: 5);
      expect(w.video?.title, 'Other');
      w.detach(second);
      expect((w.video?.title, w.transport == first, w.inFront, w.skipBackSeconds), ('Holston\'s Pick', true, true, 5));
      // Still listening to it.
      await first.pause();
      await settle();
      expect(w.playing, isFalse);
      w.detach(first);
      expect(w.video, isNull);
    });
  });

  testWidgets('the bottom bar shows the video while it plays, and controls it', (tester) async {
    final music = FakeMusic();
    final w = NowWatching(music);
    final video = FakeVideo()..playing = true; // already playing when the page registers it
    w.attach(video);
    w.showing(_episode);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerModel>.value(value: music),
          ChangeNotifierProvider.value(value: w),
        ],
        // Compact, as on a computer (the bar is sized for it).
        child: MaterialApp(
          theme: ThemeData(visualDensity: VisualDensity.compact),
          home: const Scaffold(bottomNavigationBar: SizedBox(height: 88, child: DesktopPlayerBar())),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('video-player-bar')), findsOneWidget);
    expect(find.text('Holston\'s Pick'), findsOneWidget);
    expect(find.text('Silo · S1 E2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('video-bar-play')));
    await tester.runAsync(settle);
    await tester.pump();
    expect(video.playing, isFalse);

    // The wheel over its progress bar.
    final pointer = TestPointer(2, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(find.byKey(const ValueKey('video-bar-seek')))));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
    expect(video.seeks.last, const Duration(minutes: 9, seconds: 55));

    // Previous / next video: greyed out without one, and working with one.
    IconButton button(String key) => tester.widget<IconButton>(find.byKey(ValueKey(key)));
    expect(button('video-bar-next').onPressed, isNull);
    var went = '';
    w.showing(_episode, onNext: () => went = 'next');
    await tester.pump();
    expect(button('video-bar-previous').onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('video-bar-next')));
    expect(went, 'next');
  });

  test('the system media controls show the video and send their buttons to it', () async {
    final music = FakeMusic();
    final w = NowWatching(music);
    final session = MediaSession(music, FakeLibrary(), watching: w);
    final video = FakeVideo();
    w.attach(video);
    w.showing(_episode);
    await video.play();
    await settle();
    expect(session.mediaItem.value?.title, 'Holston\'s Pick');
    expect(session.mediaItem.value?.artist, 'Silo · S1 E2');
    expect(session.playbackState.value.playing, isTrue);

    await session.pause(); // the media key
    await settle();
    expect(video.playing, isFalse);
    expect(session.playbackState.value.playing, isFalse);
    await session.skipToNext();
    expect(video.seeks.last, const Duration(minutes: 10, seconds: 10)); // no next video: seconds

    // With a next / previous video, the next / previous keys go to them.
    var went = '';
    w.showing(_episode, onNext: () => went = 'next', onPrevious: () => went = 'previous');
    expect(session.playbackState.value.controls.map((c) => c.action),
        [MediaAction.skipToPrevious, MediaAction.play, MediaAction.skipToNext]);
    await session.skipToNext();
    expect(went, 'next');
    await session.skipToPrevious();
    expect(went, 'previous');

    // The page closes: back to the music (nothing loaded here).
    w.detach(video);
    expect(session.mediaItem.value, isNull);
  });
}
