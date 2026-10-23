// The TV interface, step 7 (0.2.0): Settings, choices, sliders and typing with the remote. The
// pages listed on the left, the page beside them; a choice opens its list; a text box opens the
// TV keyboard.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/book.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/equalizer_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/update_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/play_history.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/bookmarks_model.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:hometunes/ui/tv/tv_items.dart';
import 'package:hometunes/ui/tv/tv_keyboard.dart';
import 'package:hometunes/ui/tv/tv_settings.dart';
import 'package:hometunes/ui/tv/tv_shell.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// Records what was asked to play; nothing is playing.
class _Player extends ChangeNotifier implements PlayerModel {
  final played = <String>[];

  @override
  Track? get current => null;
  @override
  Book? get book => null;
  @override
  bool get inBook => false;
  @override
  bool get playing => false;

  @override
  Future<void> playTracks(List<Track> tracks, {int start = 0, bool? shuffle, String? label}) async =>
      played.add('${tracks[start].title} from $label${shuffle == true ? ', shuffled' : ''}');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A videos model with one collection, Coastline: two episodes of season 1 and one of season 2.
class _Videos extends VideoLibraryModel {
  _Videos(super.storage, super.library) {
    final list = [
      for (final (s, e) in [(1, 1), (1, 2), (2, 1)])
        VideoItem(
          id: 'local:/v/Coastline S0${s}E0$e.mkv',
          path: '/v/Coastline S0${s}E0$e.mkv',
          title: 'Coastline S0${s}E0$e',
          collection: 'Coastline',
          season: s,
          episode: e,
          duration: const Duration(minutes: 41),
        ),
    ];
    videos = list;
    collections = [VideoCollection(name: 'Coastline', videos: list, category: 'TV')];
  }

  @override
  VideoCollection? collectionNamed(String name) => collections.where((c) => c.name == name).firstOrNull;
}

Track _t(String title, String album, int no, {String? path}) => Track(
  id: 'local:/m/$album/$title.mp3',
  source: TrackSource.local,
  title: title,
  artist: 'Harbour Lights',
  album: album,
  albumArtist: 'Harbour Lights',
  trackNumber: no,
  duration: Duration(minutes: 3, seconds: no),
  path: path,
);

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;
  late PlaylistsModel playlists;
  late VideoLibraryModel videos;
  late AppNav nav;
  late _Player player;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_tv_settings');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    Directory(storage.artDir).createSync(recursive: true);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpApp(WidgetTester tester, {bool withVideos = false}) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final songs = [
      _t('Paper Lanterns', 'Paper Lanterns', 1),
      _t('Harbour Wall', 'Paper Lanterns', 2),
      _t('Salt Road', 'Paper Lanterns', 3),
      _t('Night Ferry', 'Night Ferry', 1),
    ];
    final bookParts = [
      for (var i = 1; i <= 3; i++)
        Track(
          id: 'local:/b/north/$i.mp3',
          source: TrackSource.local,
          title: 'Part $i',
          artist: 'Ada Brook',
          album: 'The Long Road North',
          albumArtist: 'Ada Brook',
          genre: 'Audiobook',
          trackNumber: i,
          duration: const Duration(minutes: 40),
        ),
    ];
    // Through library.json, as the app keeps it, so the library's look-ups are built.
    lib = LibraryModel(storage);
    await tester.runAsync(() async {
      await storage.write('library.json', {
        'local': [
          for (final t in [...songs, ...bookParts]) t.toJson(),
        ],
      });
      await lib.load();
    });
    playlists = PlaylistsModel(storage);
    playlists.addTracks(playlists.create('Road trip'), [songs[3], songs[1]]);
    videos = withVideos ? _Videos(storage, lib) : VideoLibraryModel(storage, lib);
    player = _Player();
    nav = AppNav();
    await tester.runAsync(() async {
      await lib.settings.appearance.setTvMode(TvMode.on);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ...libraryProviders(lib),
          ChangeNotifierProvider.value(value: nav),
          ChangeNotifierProvider.value(value: playlists),
          ChangeNotifierProvider(create: (_) => ListeningModel(storage)),
          ChangeNotifierProvider(create: (_) => BookmarksModel(storage)),
          ChangeNotifierProvider(create: (_) => PlayHistory(storage)),
          ChangeNotifierProvider.value(value: videos),
          ChangeNotifierProvider(create: (_) => SelectionModel()),
          ChangeNotifierProvider<PlayerModel>.value(value: player),
          ChangeNotifierProvider(create: (_) => EqualizerModel(storage)),
          ChangeNotifierProvider(create: (_) => UpdateModel(storage, readVersion: () async => '0.2.0')),
        ],
        child: MaterialApp(
          theme: tvTheme(buildTheme(), AppColors.accent),
          builder: (context, child) => TvFocus(enabled: true, child: child!),
          home: const AppHome(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  /// The key ("tv-song:…") of the row or button with focus.
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

  /// Opens Settings from the menu at the side, as the remote would.
  Future<void> openSettings(WidgetTester tester) async {
    await press(tester, LogicalKeyboardKey.arrowLeft); // onto the menu
    await press(tester, LogicalKeyboardKey.arrowUp, 6); // Home, at the top
    await press(tester, LogicalKeyboardKey.arrowDown, 5); // Settings
    await press(tester, LogicalKeyboardKey.select);
    expect(nav.tab, AppNav.settingsTab);
    expect(find.byType(TvSettingsScreen), findsOneWidget);
  }

  /// Types on a real keyboard (small letters).
  Future<void> type(WidgetTester tester, String text) async {
    for (final c in text.split('')) {
      await press(
        tester,
        c == ' ' ? LogicalKeyboardKey.space : LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + c.codeUnitAt(0) - 97),
      );
    }
  }

  testWidgets('Settings: the pages on the left; resting on one shows it; → goes in at the top, ← comes back to it', (
    tester,
  ) async {
    await pumpApp(tester);
    await openSettings(tester);
    expect(focusedKey(), 'tv-settings-search'); // the top of the list
    expect(find.text('Folders & scanning'), findsWidgets);
    // Down to Playback (About, Appearance, … Playback is the 8th page).
    await press(tester, LogicalKeyboardKey.arrowDown, 8);
    expect(focusedKey(), 'tv-settings-playback');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('tv-settings-title'))).data, 'Playback');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedKey(), isNot(startsWith('tv-settings-'))); // in the page
    final inPage = FocusManager.instance.primaryFocus!.rect;
    expect(inPage.left, greaterThan(300));
    expect(inPage.top, lessThan(260)); // its top, not level with the Playback row
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedKey(), 'tv-settings-playback');
  });

  testWidgets('a choice shows its value; OK opens the list with it ticked; choosing one changes it', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    await press(tester, LogicalKeyboardKey.arrowDown, 8); // Playback
    await press(tester, LogicalKeyboardKey.select); // into it
    expect(find.text('Off'), findsWidgets);
    await tester.ensureVisible(find.text('Even out volume (ReplayGain)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Even out volume (ReplayGain)'));
    await tester.pumpAndSettle();
    expect(find.text('By album'), findsOneWidget); // the list
    expect(focusedKey(), 'tv-option-Off'); // the remote on the current one
    await press(tester, LogicalKeyboardKey.arrowDown, 2);
    await press(tester, LogicalKeyboardKey.select);
    expect(lib.settings.playback.replayGain.name, 'album');
    expect(find.text('By album'), findsOneWidget); // now shown on the row
  });

  testWidgets('Search settings: the keyboard, then what matches; choosing one opens its page with the remote on it', (
    tester,
  ) async {
    await pumpApp(tester);
    await openSettings(tester);
    await press(tester, LogicalKeyboardKey.select); // Search settings
    expect(find.byType(TvTextInput), findsOneWidget);
    expect(focusedKey(), 'tv-key-a');
    await type(tester, 'gapless');
    expect(find.text('gapless|'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tv-text-done')));
    await tester.pumpAndSettle();
    expect(find.text('Settings matching "gapless"'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('tv-settings-title'))).data, 'Playback');
    // The remote is on Gapless playback's switch row.
    final gapless = tester.getRect(find.byKey(const ValueKey('setting:gapless')));
    expect(gapless.overlaps(FocusManager.instance.primaryFocus!.rect), isTrue);
    await tester.pump(const Duration(seconds: 2)); // the light on it fades
  });

  testWidgets('menus that need typing: Rename a playlist, and New playlist under Add to a playlist', (tester) async {
    await pumpApp(tester);
    final ctx = tester.element(find.byType(AppHome));
    final road = playlists.playlists.single;
    unawaited(showPlaylistOptions(ctx, road));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tv-option-Rename')));
    await tester.pumpAndSettle();
    expect(find.text('Road trip|'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tv-key-Clear')));
    await tester.pumpAndSettle();
    await type(tester, 'drive');
    await tester.tap(find.byKey(const ValueKey('tv-text-done')));
    await tester.pumpAndSettle();
    expect(road.name, 'drive');

    final song = lib.tracks.firstWhere((t) => t.title == 'Salt Road');
    unawaited(showSongOptions(ctx, song));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tv-option-Add to a playlist')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tv-option-New playlist')));
    await tester.pumpAndSettle();
    await type(tester, 'mix');
    await tester.tap(find.byKey(const ValueKey('tv-text-done')));
    await tester.pumpAndSettle();
    final mix = playlists.playlists.firstWhere((p) => p.name == 'mix');
    expect(mix.trackIds, [song.id]);
    await tester.pump(const Duration(seconds: 4)); // the notice goes
  });

  group('the keyboard and text boxes', () {
    Future<void> pumpField(WidgetTester tester, Widget field) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: tvTheme(buildTheme(), AppColors.accent),
          builder: (context, child) => TvFocus(enabled: true, child: child!),
          home: Scaffold(
            body: Center(child: SizedBox(width: 400, child: field)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a text box opens the keyboard; Shift, symbols and Done put the text in it', (tester) async {
      final c = TextEditingController(text: 'Old');
      addTearDown(c.dispose);
      final changed = <String>[];
      await pumpField(
        tester,
        TvTextField(
          field: TextField(
            controller: c,
            onChanged: changed.add,
            decoration: const InputDecoration(labelText: 'Server name'),
          ),
        ),
      );
      expect(find.text('Server name'), findsOneWidget);
      expect(find.text('Old'), findsOneWidget);
      await tester.tap(find.text('Old'));
      await tester.pumpAndSettle();
      expect(find.text('Server name'), findsWidgets); // the keyboard's title
      expect(find.text('Old|'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.backspace, 3);
      // On screen: Shift, then H (↓ 1, → 1 from a), then Shift off and i.
      await tester.tap(find.byKey(const ValueKey('tv-key-Shift')));
      await tester.pumpAndSettle();
      expect(find.text('H'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tv-key-h')));
      await tester.tap(find.byKey(const ValueKey('tv-key-Shift')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tv-key-i')));
      await tester.tap(find.byKey(const ValueKey('tv-key-Symbols')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tv-key-l'))); // the '!' in the same place
      await tester.pumpAndSettle();
      expect(find.text('Hi!|'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tv-key-Done')));
      await tester.pumpAndSettle();
      expect(c.text, 'Hi!');
      expect(changed, ['Hi!']);
      expect(find.byType(TvTextInput), findsNothing);
    });

    testWidgets('a password shows as dots, Show reveals it; Back leaves the text as it was', (tester) async {
      final c = TextEditingController(text: 'pw');
      addTearDown(c.dispose);
      await pumpField(
        tester,
        TvTextField(
          field: TextField(
            controller: c,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
        ),
      );
      expect(find.text('••'), findsOneWidget);
      await tester.tap(find.text('••'));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.keyX);
      expect(find.text('•••|'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tv-text-show')));
      await tester.pumpAndSettle();
      expect(find.text('pwx|'), findsOneWidget);
      await tester.binding.handlePopRoute(); // Back
      await tester.pumpAndSettle();
      expect(c.text, 'pw');
    });

    testWidgets('off TV mode it is the usual text box', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TvTextField(field: TextField())),
        ),
      );
      expect(find.byType(EditableText), findsOneWidget);
    });

    testWidgets('a slider: ← → move it, ↓ leaves it', (tester) async {
      var value = 0.5;
      await pumpField(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(value: value, onChanged: (v) => setState(() => value = v), autofocus: true),
              TextButton(key: const ValueKey('tv-below'), onPressed: () {}, child: const Text('Below')),
            ],
          ),
        ),
      );
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(value, greaterThan(0.5));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedKey(), 'tv-below');
      expect(value, greaterThan(0.5));
    });
  });
}
