// 0.1.84: the seek preview, the small picture and time above a video's progress bar while moving
// through the video (services/seek_preview.dart, ui/widgets/seek_preview_overlay.dart). The real
// pictures need the engine, so a stand-in source is used; the bar is a stand-in for media_kit's.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/engine/engines.dart';
import 'package:hometunes/services/seek_preview.dart';
import 'package:flutter/services.dart';
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:hometunes/ui/widgets/seek_preview_overlay.dart';

/// Hands out a tiny picture per spot; each can be held back until [release] to act like a slow
/// engine.
class FakeFrames implements SeekFrameSource {
  final opened = <String>[];
  final asked = <Duration>[];
  int closes = 0;
  bool failOpen = false;
  bool slow = false;
  final _waiting = <Completer<void>>[];

  @override
  Future<void> open(String source) async {
    if (failOpen) throw StateError('no');
    opened.add(source);
  }

  @override
  Future<Uint8List?> frameAt(Duration at) async {
    asked.add(at);
    if (slow) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    return Uint8List.fromList(kTinyPng);
  }

  void release() {
    for (final c in List.of(_waiting)) {
      c.complete();
    }
    _waiting.clear();
  }

  @override
  Future<void> close() async => closes++;
}

/// A 1×1 PNG, so Image.memory has something real to show.
const kTinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

const hour = Duration(hours: 1);

Future<void> settle() => Future<void>.delayed(Duration.zero).then((_) => Future<void>.delayed(Duration.zero));

/// Stands in for media_kit's progress bar: 600 wide, 36 tall, along the bottom of the picture.
class FakeBar extends StatelessWidget {
  const FakeBar({super.key});
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 36, width: double.infinity, child: LayoutBuilder(builder: (_, _) => const ColoredBox(color: Colors.red)));
}

void main() {
  test('the seek preview player: pictures only, jumping to key frames', () {
    expect(engineSettings(EngineUse.seekPreview), [
      ('vid', 'auto'),
      ('aid', 'no'),
      ('sid', 'no'),
      ('hr-seek', 'no'),
      ('screenshot-format', 'jpg'),
      ('screenshot-jpeg-quality', '85'),
    ]);
    expect(EngineUse.seekPreview.title, 'HomeTunes seek preview');
  });

  test('opens the video the first time a picture is wanted, and keeps pictures for spots close together', () async {
    final frames = FakeFrames();
    final p = SeekPreviewer(source: frames);
    p.setVideo('/v/film.mkv');
    expect(frames.opened, isEmpty); // nothing until a picture is wanted
    p.request(const Duration(minutes: 10), hour);
    await settle();
    expect(frames.opened, ['/v/film.mkv']);
    expect(frames.asked, [const Duration(minutes: 10)]);
    expect(p.frame.value?.at, const Duration(minutes: 10));
    // A second later is the same picture (a long video's spots are 9 s apart): no new fetch.
    p.request(const Duration(minutes: 10, seconds: 1), hour);
    await settle();
    expect(frames.asked, hasLength(1));
    expect(p.keptFor(const Duration(minutes: 10, seconds: 1), hour), isNotNull);
    expect(SeekPreviewer.bucket(const Duration(seconds: 3), const Duration(minutes: 5)), 1); // short: every 2 s
    await p.dispose();
    expect(frames.closes, 1);
  });

  test('while the engine is busy, only the newest spot is fetched next', () async {
    final frames = FakeFrames()..slow = true;
    final p = SeekPreviewer(source: frames)..setVideo('/v/film.mkv');
    p.request(const Duration(minutes: 1), hour);
    await settle();
    p.request(const Duration(minutes: 5), hour);
    p.request(const Duration(minutes: 9), hour);
    p.request(const Duration(minutes: 20), hour);
    frames.release();
    await settle();
    frames.release();
    await settle();
    expect(frames.asked, [const Duration(minutes: 1), const Duration(minutes: 20)]);
    expect(p.frame.value?.at, const Duration(minutes: 20));
    await p.dispose();
  });

  test('the next video gets its own pictures; one that can\'t open is left alone', () async {
    final frames = FakeFrames();
    final p = SeekPreviewer(source: frames)..setVideo('/v/one.mkv');
    p.request(const Duration(minutes: 2), hour);
    await settle();
    p.setVideo('/v/two.mkv');
    expect(p.frame.value, isNull);
    expect(p.keptFor(const Duration(minutes: 2), hour), isNull);
    p.request(const Duration(minutes: 2), hour);
    await settle();
    expect(frames.opened, ['/v/one.mkv', '/v/two.mkv']);

    frames.failOpen = true;
    p.setVideo('/v/broken.mkv');
    p.request(const Duration(minutes: 3), hour);
    await settle();
    p.request(const Duration(minutes: 4), hour);
    await settle();
    expect(frames.asked, hasLength(2)); // gave up on it, no more tries
    await p.dispose();
  });

  test('the hidden player closes when it\'s been idle a while, and opens again when wanted', () async {
    final frames = FakeFrames();
    final p = SeekPreviewer(source: frames, idleClose: const Duration(milliseconds: 20))..setVideo('/v/film.mkv');
    p.request(const Duration(minutes: 2), hour);
    await settle();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(frames.closes, 1);
    p.request(const Duration(minutes: 30), hour);
    await settle();
    expect(frames.opened, ['/v/film.mkv', '/v/film.mkv']);
    await p.dispose();
  });

  test('times read like the player\'s', () {
    expect(seekPreviewTime(const Duration(minutes: 4, seconds: 5)), '4:05');
    expect(seekPreviewTime(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });

  group('above the progress bar', () {
    late FakeFrames frames;
    late SeekPreviewer previewer;
    var on = true;

    setUp(() {
      frames = FakeFrames();
      previewer = SeekPreviewer(source: frames)..setVideo('/v/film.mkv');
      on = true;
    });
    tearDown(() => previewer.dispose());

    // A 640 × 360 picture with the bar along its bottom: 20 px in from each side, so its track
    // runs from x = 20 to 620.
    Widget page({double barOpacity = 1}) => MaterialApp(
          home: Center(
            child: SizedBox(
              width: 640,
              height: 360,
              child: SeekPreviewOverlay(
                previewer: previewer,
                length: () => hour,
                enabled: () => on,
                isSeekBar: (w) => w is FakeBar,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: AnimatedOpacity(
                        opacity: barOpacity, duration: const Duration(milliseconds: 1), child: const FakeBar()),
                  ),
                ),
              ),
            ),
          ),
        );

    Offset onBar(WidgetTester tester, double fraction) {
      final box = tester.getRect(find.byType(FakeBar));
      return Offset(box.left + box.width * fraction, box.center.dy);
    }

    testWidgets('the mouse over the bar shows the picture and time there, and leaving hides it', (tester) async {
      await tester.pumpWidget(page());
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(onBar(tester, 0.5));
      await tester.pump();
      expect(find.byKey(const ValueKey('seek-preview')), findsOneWidget);
      expect(find.text('30:00'), findsOneWidget);
      await tester.runAsync(settle);
      await tester.pump();
      expect(frames.asked, [const Duration(minutes: 30)]);
      expect(find.byKey(const ValueKey('seek-preview-picture')), findsOneWidget);
      // Above the bar, centred on the spot.
      final preview = tester.getRect(find.byKey(const ValueKey('seek-preview')));
      expect(preview.bottom, lessThanOrEqualTo(tester.getRect(find.byType(FakeBar)).top));
      expect(preview.center.dx, closeTo(onBar(tester, 0.5).dx, 1));

      await mouse.moveTo(onBar(tester, 0.25));
      await tester.pump();
      expect(find.text('15:00'), findsOneWidget);
      // Off the bar (up into the picture): gone.
      await mouse.moveTo(onBar(tester, 0.25) - const Offset(0, 120));
      await tester.pump();
      expect(find.byKey(const ValueKey('seek-preview')), findsNothing);
      await mouse.removePointer();
      await previewer.dispose(); // its idle timer, before the test ends
    });

    testWidgets('a finger on the bar shows it while dragging, and lifting it hides it', (tester) async {
      await tester.pumpWidget(page());
      final finger = await tester.startGesture(onBar(tester, 0.1));
      await tester.pump();
      expect(find.text('6:00'), findsOneWidget);
      // Dragging along (and a little above the bar, as fingers do) keeps following.
      await finger.moveTo(onBar(tester, 0.9) - const Offset(0, 30));
      await tester.pump();
      expect(find.text('54:00'), findsOneWidget);
      await finger.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('seek-preview')), findsNothing);
      await previewer.dispose();
    });

    testWidgets('nothing while the controls are faded out, or with the setting off', (tester) async {
      await tester.pumpWidget(page(barOpacity: 0));
      final finger = await tester.startGesture(onBar(tester, 0.5));
      await tester.pump();
      expect(find.byKey(const ValueKey('seek-preview')), findsNothing);
      await finger.up();

      await tester.pumpWidget(page());
      on = false;
      final again = await tester.startGesture(onBar(tester, 0.5));
      await tester.pump();
      expect(find.byKey(const ValueKey('seek-preview')), findsNothing);
      await again.up();
      expect(frames.asked, isEmpty);
    });
  });

  // 0.2.0: on a TV the remote moves along the bar instead of a pointer.
  group('with the TV remote', () {
    var pos = Duration.zero;
    late List<Duration> seeks;
    var activated = 0;

    setUp(() {
      pos = const Duration(minutes: 5);
      seeks = [];
      activated = 0;
    });

    Widget page({bool tv = true}) => MaterialApp(
          home: TvFocus(
            enabled: tv,
            child: Scaffold(
              body: Column(children: [
                TextButton(key: const ValueKey('a-button'), onPressed: () {}, child: const Text('A button')),
                SizedBox(
                  width: 640,
                  height: 360,
                  child: SeekPreviewOverlay(
                    previewer: null,
                    length: () => hour,
                    position: () => pos,
                    onSeek: seeks.add,
                    onActivate: () => activated++,
                    isSeekBar: (w) => w is FakeBar,
                    child: const Align(alignment: Alignment.bottomCenter, child: FakeBar()),
                  ),
                ),
              ]),
            ),
          ),
        );

    Future<void> open(WidgetTester tester, {bool tv = true}) async {
      await tester.pumpWidget(page(tv: tv));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

    test('one press moves 10 s, or a 150th of a long video, and more while held', () {
      expect(SeekPreviewOverlayState.remoteStep(const Duration(minutes: 20), 0), const Duration(seconds: 10));
      expect(SeekPreviewOverlayState.remoteStep(hour, 0), const Duration(seconds: 24));
      expect(SeekPreviewOverlayState.remoteStep(hour, 6), const Duration(seconds: 72));
      expect(SeekPreviewOverlayState.remoteStep(hour, 300), const Duration(minutes: 6)); // at most a tenth
    });

    testWidgets('the bar has focus when the video opens; → moves the spot with its time, OK jumps there', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('tv-seek-bar')), findsOneWidget);
      expect(focused(), 'seek bar');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text('5:24'), findsOneWidget); // 5:00 + an hour's 150th
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text('5:48'), findsOneWidget);
      expect(seeks, isEmpty); // not until OK, or a rest
      await press(tester, LogicalKeyboardKey.select);
      expect(seeks, [const Duration(minutes: 5, seconds: 48)]);
      expect(find.byKey(const ValueKey('seek-preview')), findsNothing);
      await tester.pumpWidget(const SizedBox()); // ends the bar's redraw timer
    });

    testWidgets('← stops at the start; the video jumps by itself once the remote rests; Back drops the spot',
        (tester) async {
      pos = const Duration(seconds: 10);
      await open(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(find.text('0:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(seeks, [Duration.zero]);
      await press(tester, LogicalKeyboardKey.mediaFastForward);
      expect(find.text('0:34'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const ValueKey('seek-preview')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(seeks, [Duration.zero]); // dropped, no jump
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('OK with no spot chosen plays or pauses; ↑ moves on to the buttons', (tester) async {
      await open(tester);
      await press(tester, LogicalKeyboardKey.select);
      expect(activated, 1);
      expect(seeks, isEmpty);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), isNot('seek bar'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('not on a computer or phone', (tester) async {
      await open(tester, tv: false);
      expect(find.byKey(const ValueKey('tv-seek-bar')), findsNothing);
    });
  });
}
