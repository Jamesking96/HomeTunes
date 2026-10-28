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

  testWidgets('↑ on a page\'s top row stays there rather than jumping into the sidebar (0.2.5)', (tester) async {
    // A page whose only button sits a little lower than the sidebar's first item: ↑ used to land
    // on that item (on the TV, Play on a collection page opened the menu on Music).
    Widget item(String name) => InkWell(key: ValueKey(name), onTap: () {}, child: SizedBox(width: 160, height: 48, child: Center(child: Text(name))));
    await tester.pumpWidget(MaterialApp(
      theme: tvTheme(ThemeData(), Colors.deepOrange),
      home: TvFocus(
        enabled: true,
        child: Scaffold(
          body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TvRegion(child: Column(children: [item('Home'), item('Videos')])),
            Expanded(child: TvRegion(child: Column(children: [const SizedBox(height: 60), item('Play')]))),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedName(), 'Play');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedName(), 'Play');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedName(), 'Play');
    // ← is still the way to the sidebar.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedName(), isIn(['Home', 'Videos']));
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

  // 22 Oct fix (tried on the TV): on a TV-sized screen Settings opens each page over its list. ↓
  // went on into the hidden list underneath, so OK opened About instead of "Add video folder".
  group('pages opened over others', () {
    Widget item(String name, {List<String>? pressed, double width = 200}) => InkWell(
          key: ValueKey(name),
          onTap: () => pressed?.add(name),
          child: SizedBox(width: width, height: 48, child: Center(child: Text(name))),
        );

    final pageKey = GlobalKey<NavigatorState>();

    /// The sidebar, and the page area with its own pages (as each tab has): a list of five, and
    /// later a page with two buttons opened over it.
    Widget app(List<String> pressed) => MaterialApp(
          home: TvFocus(
            enabled: true,
            child: Scaffold(
              body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TvRegion(child: Column(children: [item('Home'), item('Settings')])),
                Expanded(
                  child: TvRegion(
                    child: Navigator(
                      key: pageKey,
                      onGenerateRoute: (_) => MaterialPageRoute(
                        builder: (_) => Material(
                          child: Column(children: [
                            for (final n in ['Library', 'Playback', 'Videos', 'Backup', 'About']) item(n, pressed: pressed),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );

    Future<void> openPage(WidgetTester tester, List<String> pressed) async {
      pageKey.currentState!.push(MaterialPageRoute(
        builder: (_) => Material(
          child: Column(children: [item('Add video folder', pressed: pressed), item('Rescan', pressed: pressed)]),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
    }

    testWidgets('the arrows stay on the page that\'s open, and OK presses what\'s on it', (tester) async {
      final pressed = <String>[];
      await tester.pumpWidget(app(pressed));
      await tester.pumpAndSettle();
      await openPage(tester, pressed);
      expect(focusedName(), 'Add video folder'); // the new page's first item
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedName(), 'Rescan');
      // Further down is only the hidden list (Backup, About): nothing there to go to.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedName(), isNot(isIn(['Library', 'Playback', 'Videos', 'Backup', 'About'])));
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedName(), 'Add video folder');
      await press(tester, LogicalKeyboardKey.select);
      expect(pressed, ['Add video folder']);
      // ← from the open page still reaches the sidebar.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedName(), isIn(['Home', 'Settings']));
    });

    testWidgets('a long list scrolls to keep the focused item in view', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: TvFocus(
          enabled: true,
          child: Scaffold(
            body: SizedBox(
              height: 300,
              child: TvRegion(
                child: ListView(children: [for (var i = 1; i <= 40; i++) item('Item $i')]),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(focusedName(), 'Item 1');
      for (var i = 0; i < 24; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(focusedName(), 'Item 25');
      final shown = tester.getRect(find.byKey(const ValueKey('Item 25')));
      expect(shown.bottom, lessThanOrEqualTo(300.5)); // scrolled into view
      expect(shown.top, greaterThanOrEqualTo(0));
    });

    testWidgets('→ from a list goes on to the page beside it, even when nothing is level with it', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: TvFocus(
          enabled: true,
          child: Scaffold(
            body: TvRegion(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [item('List 1'), item('List 2'), item('List 3'), item('List 4')]),
                Padding(padding: const EdgeInsets.only(top: 10), child: Column(children: [item('Pane 1')])),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(focusedName(), 'List 4');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedName(), 'Pane 1');
    });
  });
}
