// A video in a small window (0.1.68): the video may take more of the page, and the text and
// buttons under it shrink, but never below three quarters of their usual size on screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/widgets/window_scale.dart';

void main() {
  const big = Size(1400, 900), middle = Size(980, 640), small = Size(700, 480);

  test('the video\'s share of the page: 70 % in a big window, up to 85 % in the smallest', () {
    expect(WindowScale.videoShare(big), 0.7);
    expect(WindowScale.videoShare(small), closeTo(0.85, 1e-9));
    final m = WindowScale.videoShare(middle);
    expect(m > 0.7 && m < 0.85, isTrue);
  });

  test('text and buttons: full size in a big window, never below 75 % on screen', () {
    for (final shrinkApp in [true, false]) {
      double onScreen(Size w) {
        final app = shrinkApp ? WindowScale.factorFor(w) : 1.0;
        return app * WindowScale.videoInfoScale(w, appFactor: app);
      }

      expect(onScreen(big), 1.0, reason: 'big, app shrink $shrinkApp');
      expect(onScreen(small), closeTo(WindowScale.smallestVideoInfo, 1e-9), reason: 'small, app shrink $shrinkApp');
      final m = onScreen(middle);
      expect(m > 0.75 && m < 1, isTrue, reason: 'middle, app shrink $shrinkApp');
    }
    // The whole app already shrinks to 80 % at the smallest, so the details only shrink a little more.
    expect(WindowScale.videoInfoScale(small, appFactor: WindowScale.factorFor(small)), closeTo(0.9375, 1e-9));
  });

  testWidgets('ShrinkToWidth draws smaller, takes only that space, and clicks still land', (tester) async {
    var clicks = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          ShrinkToWidth(
            scale: 0.75,
            child: Column(children: [
              const SizedBox(key: ValueKey('box'), height: 200, width: double.infinity),
              TextButton(key: const ValueKey('btn'), onPressed: () => clicks++, child: const Text('Press')),
            ]),
          ),
          const SizedBox(key: ValueKey('after'), height: 10),
        ]),
      ),
    ));
    // Laid out 800 / 0.75 wide, drawn 800 wide: the 200 high box is 150 high on screen.
    final box = find.byKey(const ValueKey('box'));
    expect(tester.getBottomLeft(box).dy - tester.getTopLeft(box).dy, closeTo(150, 0.01));
    expect(tester.getTopRight(box).dx - tester.getTopLeft(box).dx, closeTo(800, 0.01));
    // Nothing left over under it.
    final shrunkBottom = tester.getBottomLeft(find.byKey(const ValueKey('shrink-to-width'))).dy;
    expect(tester.getTopLeft(find.byKey(const ValueKey('after'))).dy, closeTo(shrunkBottom, 0.01));
    await tester.tap(find.byKey(const ValueKey('btn')));
    expect(clicks, 1);
  });

  testWidgets('at full size it changes nothing', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ShrinkToWidth(scale: 1, child: Text('x'))));
    expect(find.byKey(const ValueKey('shrink-to-width')), findsNothing);
  });
}
