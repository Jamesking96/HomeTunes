// Tests for swipe-to-skip on the player (0.1.17): a quick or long swipe left means "forward"
// (next song, or skip forward in a book), right means "back"; short or slow drags, mouse drags
// and a turned-off setting do nothing, and taps still reach the player underneath.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/ui/widgets/player_controls.dart';

void main() {
  var forward = 0, back = 0, taps = 0;

  Future<void> pump(WidgetTester tester, {bool enabled = true}) async {
    forward = back = taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 80,
            child: SwipeToSkip(
              enabled: enabled,
              onForward: () => forward++,
              onBack: () => back++,
              child: GestureDetector(
                onTap: () => taps++,
                child: Container(color: Colors.blue, child: const Center(child: Text('Now playing'))),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('a quick swipe left is forward, right is back', (tester) async {
    await pump(tester);
    await tester.fling(find.text('Now playing'), const Offset(-150, 0), 1000);
    await tester.pumpAndSettle();
    expect((forward, back), (1, 0));
    await tester.fling(find.text('Now playing'), const Offset(150, 0), 1000);
    await tester.pumpAndSettle();
    expect((forward, back), (1, 1));
  });

  testWidgets('a slow but long swipe counts; a small nudge doesn\'t', (tester) async {
    await pump(tester);
    // Slow and long: counts.
    final g = await tester.startGesture(tester.getCenter(find.text('Now playing')));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(-12, 0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300)); // stop, so there's no speed left
    await g.up();
    await tester.pumpAndSettle();
    expect(forward, 1);
    // A small nudge: nothing.
    await tester.drag(find.text('Now playing'), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(back, 0);
  });

  testWidgets('taps still reach the player', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Now playing'));
    expect(taps, 1);
    expect((forward, back), (0, 0));
  });

  testWidgets('dragging with a mouse does nothing (PCs)', (tester) async {
    await pump(tester);
    await tester.fling(find.text('Now playing'), const Offset(-150, 0), 1000, deviceKind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect((forward, back), (0, 0));
  });

  testWidgets('turned off in Settings: swipes do nothing', (tester) async {
    await pump(tester, enabled: false);
    await tester.fling(find.text('Now playing'), const Offset(-150, 0), 1000);
    await tester.pumpAndSettle();
    expect((forward, back), (0, 0));
  });

  test('the setting is on by default and remembered', () async {
    final dir = Directory.systemTemp.createTempSync('hometunes_swipe');
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      dir.deleteSync(recursive: true);
    });
    final lib = LibraryModel(Storage.at(dir));
    await lib.load();
    expect(lib.swipeToSkip, isTrue);
    await lib.updatePlaybackSettings(swipeToSkip: false);
    final again = LibraryModel(Storage.at(dir));
    await again.load();
    expect(again.swipeToSkip, isFalse);
  });
}
