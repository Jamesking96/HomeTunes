// The TV interface's frame (0.2.0, step 1): pressing and holding OK, the focus look, the options
// panel and the rail (ui/tv/tv_widgets.dart, tv_options.dart, tv_rail.dart).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/tv/tv_options.dart';
import 'package:hometunes/ui/tv/tv_rail.dart';
import 'package:hometunes/ui/tv/tv_widgets.dart';

Widget app(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('pressing and holding OK', () {
    late List<String> did;
    late FocusNode node;
    setUp(() {
      did = [];
      node = FocusNode();
    });
    tearDown(() => node.dispose());

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(app(TvRow(
        title: 'Harbour Wall',
        focusNode: node,
        onPressed: () => did.add('press'),
        onHold: () => did.add('hold'),
      )));
      node.requestFocus();
      await tester.pump();
    }

    testWidgets('a short press of OK presses it', (tester) async {
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(did, ['press']);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(did, ['press', 'press']);
    });

    testWidgets('holding OK is "hold", and letting go then presses nothing', (tester) async {
      await pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 300));
      expect(did, isEmpty); // not yet
      await tester.pump(const Duration(milliseconds: 300));
      expect(did, ['hold']);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(did, ['hold']);
    });

    testWidgets('a mouse or a finger works too: click, long press', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Harbour Wall'));
      await tester.longPress(find.text('Harbour Wall'));
      expect(did, ['press', 'hold']);
    });

    testWidgets('with nothing to do it can\'t take focus', (tester) async {
      await tester.pumpWidget(app(TvRow(title: 'Just a label', focusNode: node)));
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isFalse);
    });
  });

  testWidgets('what has focus grows a little and gets the ring', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(app(TvTile(
      picture: const ColoredBox(color: Colors.blueGrey),
      title: 'Paper Lanterns',
      subtitle: 'Harbour Lights',
      focusNode: node,
      onPressed: () {},
    )));
    double scale() => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(scale(), 1.0);
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(scale(), TvStyle.focusScale);
    final box = tester.widget<AnimatedContainer>(find.descendant(of: find.byType(TvFocusFrame), matching: find.byType(AnimatedContainer)));
    expect((box.decoration! as BoxDecoration).boxShadow, isNotEmpty); // the ring
  });

  testWidgets('the hint bubble fades after a few seconds and comes back with the next press (0.2.5)', (tester) async {
    await tester.pumpWidget(app(const TvHints([('OK', 'Open'), ('←', 'Menu')])));
    double opacity() => tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    expect(find.text('OK Open', findRichText: true), findsOneWidget);
    expect(opacity(), 1);
    await tester.pump(TvHints.showFor);
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(opacity(), 1);
    await tester.pump(TvHints.showFor);
    expect(opacity(), 0);
  });

  group('the options panel', () {
    Future<List<String>> open(WidgetTester tester) async {
      final did = <String>[];
      await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
          onPressed: () => showTvOptions(context, title: 'Harbour Wall', subtitle: 'Harbour Lights · Paper Lanterns', options: [
            TvOption('Play next', Icons.playlist_play, () => did.add('next')),
            TvOption('Add to a playlist', Icons.playlist_add, () => did.add('playlist'), opensMore: true),
          ]),
          child: const Text('Options'),
        ),
      )));
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
      return did;
    }

    testWidgets('slides in with one big row per action; the first has focus; OK runs it and closes', (tester) async {
      final did = await open(tester);
      expect(find.text('Harbour Wall'), findsOneWidget);
      expect(find.text('Add to a playlist'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget); // leads on
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(did, ['playlist']);
      expect(find.text('Harbour Wall'), findsNothing);
    });

    testWidgets('Back closes it and does nothing', (tester) async {
      final did = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Play next'), findsNothing);
      expect(did, isEmpty);
    });
  });

  group('the rail', () {
    final items = [
      const TvRailItem('Home', Icons.home_outlined),
      const TvRailItem('Music', Icons.library_music_outlined),
      const TvRailItem('Settings', Icons.tune),
    ];

    testWidgets('slim with icons; with the remote on it, it opens with labels; OK picks the place', (tester) async {
      final picked = <int>[];
      final opened = <bool>[];
      final rail = GlobalKey<TvRailState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TvRail(key: rail, items: items, selected: 1, onSelect: picked.add, onOpenChange: opened.add),
            Expanded(child: TextButton(onPressed: () {}, child: const Text('The page'))),
          ]),
        ),
      ));
      expect(find.text('Music'), findsNothing); // icons only
      expect(tester.getSize(find.byType(TvRail)).width, TvRail.width);

      rail.currentState!.focusSelected(); // e.g. Back from a page's top
      await tester.pumpAndSettle();
      expect(opened, [true]);
      expect(find.text('Music'), findsOneWidget);
      expect(tester.getSize(find.byType(TvRail)).width, TvRail.openWidth);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(picked, [2]);
    });

    testWidgets('← from the page lands on the place showing, not the nearest item (0.2.5)', (tester) async {
      final page = FocusNode();
      addTearDown(page.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TvRail(items: items, selected: 1, onSelect: (_) {}),
            // A button level with Settings, the rail's last item.
            Expanded(child: Column(children: [const SizedBox(height: 125), TextButton(focusNode: page, onPressed: () {}, child: const Text('Clear'))])),
          ]),
        ),
      ));
      page.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'rail Music');
    });

    testWidgets('what\'s playing sits at the bottom and opens it', (tester) async {
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TvRail(
            items: items,
            selected: 0,
            onSelect: (_) {},
            nowPlaying: const ColoredBox(color: Colors.blueGrey),
            nowPlayingLabel: 'Harbour Wall · Harbour Lights',
            onNowPlaying: () => opened++,
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('tv-rail-now-playing')));
      expect(opened, 1);
    });
  });
}
