// The screen shown while HomeTunes opens on Android (0.2.12, lib/ui/start_screen.dart): the dark
// background and the icon at once, "Loading your library…" only after a second.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/start_screen.dart';

void main() {
  testWidgets('dark background and the icon at once; the words only after a second', (tester) async {
    await tester.pumpWidget(const StartScreen());
    final box = tester.widget<ColoredBox>(find.byType(ColoredBox).first);
    expect(box.color, StartScreen.background);
    expect(find.byType(Image), findsOneWidget);
    double wordsOpacity() =>
        tester.widget<AnimatedOpacity>(find.ancestor(of: find.text('Loading your library…'), matching: find.byType(AnimatedOpacity))).opacity;
    expect(wordsOpacity(), 0);
    await tester.pump(const Duration(milliseconds: 900));
    expect(wordsOpacity(), 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(wordsOpacity(), 1);
  });

  testWidgets('the icon is in the very middle, as in the launch window', (tester) async {
    await tester.pumpWidget(const StartScreen());
    final screen = tester.getRect(find.byType(StartScreen));
    final icon = tester.getRect(find.byType(Image));
    expect(icon.center, screen.center);
    expect(icon.width, StartScreen.logoSize);
  });
}
