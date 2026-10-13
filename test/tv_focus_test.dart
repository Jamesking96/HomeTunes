// Tests for TV mode's remote-control navigation (ui/tv/tv_focus.dart, Android TV phase T3, 0.2.0):
// something has focus when the app opens, the arrow keys move between and within the parts of the
// screen, the remote's OK / Select presses the focused thing, and with TV mode off nothing changes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/tv/tv_focus.dart';

void main() {
  tearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);

  /// A sidebar of three items beside a page with a row of two cards and a button.
  Widget screen({required bool tv, required List<String> pressed}) {
    Widget item(String name) => InkWell(
          key: ValueKey(name),
          onTap: () => pressed.add(name),
          child: SizedBox(width: 160, height: 48, child: Center(child: Text(name))),
        );
    return MaterialApp(
      theme: tv ? tvTheme(ThemeData(), Colors.deepOrange) : ThemeData(),
      home: TvFocus(
        enabled: tv,
        child: Scaffold(
          body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TvRegion(child: Column(children: [item('Home'), item('Search'), item('Library')])),
            Expanded(
              child: TvRegion(
                child: Column(children: [
                  Row(children: [item('Album 1'), item('Album 2')]),
                  TextButton(key: const ValueKey('Play all'), onPressed: () => pressed.add('Play all'), child: const Text('Play all')),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  String? focusedName() {
    // The focused widget's key, found by walking up from the focused element.
    final ctx = FocusManager.instance.primaryFocus?.context;
    String? name;
    ctx?.visitAncestorElements((e) {
      final k = e.widget.key;
      if (k is ValueKey<String>) {
        name = k.value;
        return false;
      }
      return true;
    });
    return name;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('something has focus as soon as the app opens', (tester) async {
    await tester.pumpWidget(screen(tv: true, pressed: []));
    await tester.pumpAndSettle();
    expect(focusedName(), 'Home');
    expect(FocusManager.instance.highlightStrategy, FocusHighlightStrategy.alwaysTraditional);
  });

  testWidgets('the arrow keys move within the sidebar and across to the page', (tester) async {
    await tester.pumpWidget(screen(tv: true, pressed: []));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedName(), 'Search');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedName(), 'Library');
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedName(), 'Home');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedName(), 'Album 1');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedName(), 'Album 2');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedName(), 'Play all');
    // Up again goes back into the row, not across to the sidebar.
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedName(), isIn(['Album 1', 'Album 2']));
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedName(), isIn(['Home', 'Search', 'Library']));
  });

  testWidgets('OK / Select on the remote presses the focused thing', (tester) async {
    final pressed = <String>[];
    await tester.pumpWidget(screen(tv: true, pressed: pressed));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.select);
    expect(pressed, ['Home']);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.gameButtonA);
    expect(pressed, ['Home', 'Album 1']);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);
    expect(pressed, ['Home', 'Album 1', 'Play all']);
  });

  testWidgets('TV mode off: no focus at start, highlights as usual', (tester) async {
    await tester.pumpWidget(screen(tv: false, pressed: []));
    await tester.pumpAndSettle();
    expect(focusedName(), isNull);
    expect(FocusManager.instance.highlightStrategy, FocusHighlightStrategy.automatic);
  });

  test('the TV theme highlights focused buttons in the accent colour', () {
    final t = tvTheme(ThemeData(), Colors.deepOrange);
    expect(t.focusColor, Colors.deepOrange.withValues(alpha: 0.45));
    final overlay = t.textButtonTheme.style!.overlayColor!;
    expect(overlay.resolve({WidgetState.focused}), Colors.deepOrange.withValues(alpha: 0.45));
    expect(overlay.resolve({}), isNull);
    expect(t.iconButtonTheme.style!.overlayColor!.resolve({WidgetState.focused}), isNotNull);
  });
}
