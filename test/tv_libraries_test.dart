// The TV interface, step 2 (0.2.0): Home and the libraries. The grids with the A–Z strip and
// the tabs (ui/tv/tv_browse.dart), driven with the arrow keys and OK only, as on the remote.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_index.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/play_history.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:hometunes/ui/tv/tv_browse.dart';
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:hometunes/ui/tv/tv_music.dart';
import 'package:hometunes/ui/tv/tv_pages.dart';
import 'package:hometunes/ui/tv/tv_shell.dart';
import 'package:hometunes/ui/tv/tv_widgets.dart';
import 'package:provider/provider.dart';

import 'idle_player.dart';

const _names = [
  'Amber Road', 'Apple Tree', 'Bright Water', 'Cold Harbour', 'Copper Sky', 'Driftwood', 'Echo Lane', 'Field Notes',
  'Low Tide', 'Maple Street', 'Marigold', 'Matchlight', 'Meridian', 'Midnight Bus', 'Millpond', 'Mirror Lake',
  'Moth Wings', 'Mountain Rail', 'Night Ferry', 'North Pier', 'Notebook', 'Nova', 'Oak & Iron', 'Paper Lanterns',
  'Quiet Hours', 'Second Wind', 'Signal Fire', 'Tidewater', 'Weathervane', 'Zephyr', '1999',
];

/// The TV frame's surroundings: TV mode on, one region, a 960 x 540 screen.
Widget _tv(Widget child) => MaterialApp(
      builder: (context, c) => TvFocus(enabled: true, child: c!),
      home: Scaffold(body: TvRegion(child: child)),
    );

String? _focusedLabel() {
  final n = FocusManager.instance.primaryFocus;
  return n?.debugLabel;
}

void main() {
  setUp(() {});

  Future<List<String>> pumpGrid(WidgetTester tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pressed = <String>[];
    final sorted = [..._names]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    await tester.pumpWidget(_tv(TvAzGrid<String>(
      items: sorted,
      letterOf: tvLetterOf,
      itemBuilder: (context, name, i, node, w) => TvTile(
        key: ValueKey(name),
        focusNode: node,
        width: w,
        picture: const ColoredBox(color: Colors.blueGrey),
        title: name,
        onPressed: () => pressed.add(name),
      ),
    )));
    await tester.pumpAndSettle();
    return pressed;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  bool focusedOn(WidgetTester tester, String name) {
    final f = FocusManager.instance.primaryFocus;
    final ctx = f?.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<TvTile>()?.title == name;
  }

  test('a name\'s letter ignores "The" and case; anything else is #', () {
    expect(tvLetterOf('The Slow Engines'), 'S');
    expect(tvLetterOf('amber road'), 'A');
    expect(tvLetterOf('1999'), '#');
    expect(tvLetterOf('Élan'), '#');
    expect(tvLetterOf(''), '#');
  });

  testWidgets('OK presses the tile with focus; arrows move along the grid', (tester) async {
    final pressed = await pumpGrid(tester);
    // Going into the page from the rail: the first tile (top left), not the A–Z strip beside it.
    await tester.pumpAndSettle();
    expect(tvFocusFirstIn(FocusManager.instance.rootScope), isTrue);
    await tester.idle(); // the focus request is applied in a microtask
    await tester.pumpAndSettle();
    expect(focusedOn(tester, '1999'), isTrue, reason: _focusedLabel());
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedOn(tester, 'Amber Road'), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);
    expect(pressed, hasLength(1));
  });

  testWidgets('→ at a row\'s end reaches the A–Z strip; ↓ jumps letter by letter; ← goes back in at that letter', (tester) async {
    final pressed = await pumpGrid(tester);
    // Along the first row to its end, then once more: the strip.
    await press(tester, LogicalKeyboardKey.arrowRight, 10);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvLetterStrip>(), isNotNull);
    // # → A → B … M (letters with nothing under them are skipped: G, H, I, J, K).
    await press(tester, LogicalKeyboardKey.arrowDown, 8);
    expect(tester.widget<TvLetterStrip>(find.byType(TvLetterStrip)).current, 'M');
    // The grid has scrolled to the M's.
    expect(find.text('Maple Street'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedOn(tester, 'Maple Street'), isTrue, reason: _focusedLabel());
    await press(tester, LogicalKeyboardKey.select);
    expect(pressed, ['Maple Street']);
  });

  testWidgets('OK on the strip also goes back into the grid; past the last letter the press goes on', (tester) async {
    await pumpGrid(tester);
    await press(tester, LogicalKeyboardKey.arrowRight, 10);
    await press(tester, LogicalKeyboardKey.arrowDown, 30); // stops at Z
    expect(tester.widget<TvLetterStrip>(find.byType(TvLetterStrip)).current, 'Z');
    await press(tester, LogicalKeyboardKey.select);
    expect(focusedOn(tester, 'Zephyr'), isTrue, reason: _focusedLabel());
  });

  testWidgets('tabs: moving onto one shows it after a moment; coming up lands on the one showing', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var selected = 0;
    await tester.pumpWidget(_tv(StatefulBuilder(
      builder: (context, setState) => Column(children: [
        TvTabBar(labels: const ['Albums', 'Artists', 'Songs'], selected: selected, onSelect: (i) => setState(() => selected = i)),
        const SizedBox(height: 20),
        Row(children: [
          for (final n in ['one', 'two', 'three', 'four'])
            Padding(
              padding: const EdgeInsets.all(8),
              child: TvTile(key: ValueKey(n), picture: const ColoredBox(color: Colors.grey), title: n, onPressed: () {}),
            ),
        ]),
      ]),
    )));
    await tester.pumpAndSettle();
    // The first thing (the Albums tab) has focus; → passes over Artists to Songs quickly.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 100));
    expect(selected, 0); // not yet
    await tester.pump(TvTabBar.settle);
    expect(selected, 2); // Songs, but never Artists
    // Down to the tiles, along to the last, back up: onto Songs, the tab showing.
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight, 3);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tab Songs');
    await tester.pump(TvTabBar.settle);
    expect(selected, 2);
  });

  group('in the TV frame', () {
    late Directory dir;
    late LibraryModel lib;
    late AppNav nav;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_tv_libraries');
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = Storage.at(dir);
      Directory(storage.artDir).createSync(recursive: true);
      final songs = [
        for (final (i, name) in _names.indexed)
          Track(
            id: 'local:/m/$name.mp3',
            source: TrackSource.local,
            title: name,
            artist: i.isEven ? 'Harbour Lights' : 'Mara Quill',
            album: name,
            albumArtist: i.isEven ? 'Harbour Lights' : 'Mara Quill',
            genre: i.isEven ? 'Folk' : 'Jazz',
            duration: const Duration(minutes: 3),
            path: '${dir.path}${Platform.pathSeparator}m${Platform.pathSeparator}$name.mp3',
          ),
      ];
      final albums = groupAlbums(songs);
      lib = LibraryModel(storage)
        ..tracks = songs
        ..albums = albums
        ..artists = groupArtists(albums);
      await tester.runAsync(() => lib.settings.appearance.setTvMode(TvMode.on));
      nav = AppNav();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ...libraryProviders(lib),
          ChangeNotifierProvider.value(value: nav),
          ChangeNotifierProvider(create: (_) => PlaylistsModel(storage)),
          ChangeNotifierProvider(create: (_) => ListeningModel(storage)),
          ChangeNotifierProvider(create: (_) => PlayHistory(storage)),
          ChangeNotifierProvider(create: (_) => VideoLibraryModel(storage, lib)),
          ChangeNotifierProvider(create: (_) => SelectionModel()),
          idlePlayerProvider(),
        ],
        child: MaterialApp(
          theme: tvTheme(buildTheme(), AppColors.accent),
          builder: (context, child) => TvFocus(enabled: true, child: child!),
          home: const AppHome(),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// The key ("tv-album:…", "tv-song:…") of the tile or row with focus.
    String? focusedKey() {
      String? found;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
        final k = e.widget.key;
        if (k is ValueKey<String> && k.value.startsWith('tv-')) {
          found = k.value;
          return false;
        }
        return true;
      });
      return found;
    }

    testWidgets('Home, Music, Audiobooks and Videos open on their TV screens; the rest are as before', (tester) async {
      await pumpApp(tester);
      expect(find.text('Your playlists'), findsOneWidget); // TV Home
      nav.selectTab(AppNav.libraryTab);
      await tester.pumpAndSettle();
      expect(find.byType(TvMusicScreen), findsOneWidget);
      for (final t in TvMusicTab.values) {
        expect(find.text(t.label), findsOneWidget);
      }
      expect(find.text('Amber Road'), findsWidgets);
      // The hint bubble says what the remote does here.
      expect(find.textContaining('jump A–Z'), findsOneWidget);
    });

    testWidgets('from the rail into Music: the tabs, ↓ to an album, OK opens it, Back comes back to it', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft); // onto the rail
      await press(tester, LogicalKeyboardKey.arrowUp, 6); // Home, at the top
      await press(tester, LogicalKeyboardKey.arrowDown); // Music
      await press(tester, LogicalKeyboardKey.select);
      expect(nav.tab, AppNav.libraryTab);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tab Albums');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedKey(), startsWith('tv-album:'));
      final album = focusedKey();
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(TvAlbumPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TvAlbumPage), findsNothing);
      expect(focusedKey(), album);
    });

    testWidgets('↑ from the top of a grid goes to the tab showing, not the nearer Sort button', (tester) async {
      await pumpApp(tester);
      nav.selectTab(AppNav.libraryTab);
      await tester.pumpAndSettle();
      // Onto the Songs tab, wait for it, then into the list at the right-hand end of a row.
      await press(tester, LogicalKeyboardKey.arrowLeft); // the rail, Music
      await press(tester, LogicalKeyboardKey.select); // into the page: the Albums tab
      await press(tester, LogicalKeyboardKey.arrowRight, 2);
      await tester.pump(TvTabBar.settle);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tv-shuffle')), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedKey(), startsWith('tv-song:'));
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tab Songs');
      // The buttons are along the tabs' row, after the last tab.
      for (var i = 0; i < 8 && (focusedKey()?.startsWith('tv-tab-') ?? true); i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      expect(focusedKey(), anyOf('tv-shuffle', 'tv-sort'));
    });

    testWidgets('a genre opens a page of its songs with Play and Shuffle', (tester) async {
      await pumpApp(tester);
      nav.selectTab(AppNav.libraryTab);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('tv-tab-Genres')));
      await tester.tap(find.byKey(const ValueKey('tv-tab-Genres')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tv-genre:Jazz')));
      await tester.pumpAndSettle();
      expect(find.text('GENRE'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Apple Tree'), findsOneWidget); // odd ones are Jazz
      expect(find.text('Amber Road'), findsNothing);
    });
  });
}
