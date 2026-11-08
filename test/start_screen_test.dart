// The screen shown while HomeTunes opens (lib/ui/start_screen.dart): 0.2.13, the user's picture
// fitted whole on its edge colour; "Loading your library…" only after a second.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/start_screen.dart';

void main() {
  Future<void> show(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const StartScreen());
  }

  testWidgets('the picture fills a TV-shaped screen; the words only after a second', (tester) async {
    await show(tester, const Size(1920, 1080));
    expect(tester.widget<ColoredBox>(find.byType(ColoredBox).first).color, StartScreen.background);
    expect(tester.getRect(find.byType(Image)), const Rect.fromLTWH(0, 0, 1920, 1080));
    double wordsOpacity() =>
        tester.widget<AnimatedOpacity>(find.ancestor(of: find.text('Loading your library…'), matching: find.byType(AnimatedOpacity))).opacity;
    expect(wordsOpacity(), 0);
    await tester.pump(const Duration(milliseconds: 900));
    expect(wordsOpacity(), 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(wordsOpacity(), 1);
  });

  testWidgets('on a phone held upright it goes across the width, in the middle', (tester) async {
    await show(tester, const Size(1080, 2400));
    final r = tester.getRect(find.byType(Image));
    expect(r.width, 1080);
    expect(r.height, closeTo(1080 * 9 / 16, 0.01));
    expect(r.center, const Offset(540, 1200));
  });

  test('the big picture only for a screen wider than the small one', () {
    expect(StartScreen.pictureFor(1920), StartScreen.small);
    expect(StartScreen.pictureFor(3840), StartScreen.large);
  });
}
