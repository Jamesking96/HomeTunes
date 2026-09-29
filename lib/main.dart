// The app's starting point.
// main() opens the storage folder, creates every shared "model" (library, playlists, listening
// places, bookmarks, lyrics, player), loads their saved JSON files, links them together, starts
// the system media controls and then hands everything to Flutter through a MultiProvider.
// Screens further down the tree reach these models with context.watch / select / read.
// Order matters here: the models must be loaded before the UI appears, and the player must exist
// before the media controls (notification, lock screen, Windows media keys) can be connected.
import 'dart:io';

import 'package:audio_service_win/audio_service_win.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'services/media_session.dart';
import 'services/playback_log.dart';
import 'services/storage.dart';
import 'state/bookmarks_model.dart';
import 'state/equalizer_model.dart';
import 'state/library_model.dart';
import 'state/listening_model.dart';
import 'state/lyrics_model.dart';
import 'state/player_model.dart';
import 'state/playlists_model.dart';
import 'state/selection_model.dart';
import 'state/sleep_timer.dart';
import 'state/update_model.dart';
import 'ui/nav.dart';
import 'ui/screens/settings/appearance_settings.dart';
import 'ui/screens/settings/update_ui.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

/// Starts HomeTunes: sets up storage and the models, then shows the app.
Future<void> main() async {
  // Both of these must run before any plugin or media_kit Player is used.
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 1. Open the data folder and create the models (nothing is read from disk yet).
  final storage = await Storage.open();
  await PlaybackLog.attach(storage.root.path);
  PlaybackLog.add('HomeTunes started');
  final library = LibraryModel(storage);
  final playlists = PlaylistsModel(storage);
  final listening = ListeningModel(storage);
  final bookmarks = BookmarksModel(storage);
  final lyrics = LyricsModel(library, storage);
  final equalizer = EqualizerModel(storage);
  final updates = UpdateModel(storage, readVersion: () async => (await PackageInfo.fromPlatform()).version);
  // 2. Load all the saved JSON files at the same time, to keep start-up quick.
  //    HomeTunes: each model reads its file defensively, but as a last resort an unexpected
  //    error in one of them is reported and that model keeps its defaults, rather than
  //    stopping the app before its first screen.
  Future<void> safely(String what, Future<void> Function() load) async {
    try {
      await load();
    } catch (e, st) {
      debugPrint('HomeTunes: loading $what failed: $e\n$st');
      storage.report('HomeTunes couldn\'t load your $what, so it started without them.');
    }
  }

  await Future.wait([
    safely('library and settings', library.load),
    safely('playlists', playlists.load),
    safely('audiobook places', listening.load),
    safely('bookmarks', bookmarks.load),
    safely('saved lyrics', lyrics.load),
    safely('equaliser settings', equalizer.load),
    safely('update settings', updates.load),
  ]);
  // Songs in playlists / Liked Songs are kept track of even when their files
  // are missing, and follow them if they move.
  library
    // Asked during a scan: which song ids do other parts of the app still point at?
    ..otherReferencedIds = (() => {...playlists.referencedIds, ...listening.referencedIds, ...bookmarks.referencedIds})
    // A file moved: update the old id to the new one everywhere it's stored.
    ..onIdsRemapped = ((moved) {
      playlists.remapIds(moved);
      listening.remapIds(moved);
      bookmarks.remapIds(moved);
      lyrics.remapIds(moved);
    })
    // The user chose to forget missing songs: drop them from everything else too.
    ..onIdsForgotten = ((ids) {
      playlists.removeIds(ids);
      listening.removeIds(ids);
      bookmarks.removeIds(ids);
    });

  // Books whose folder moved get a new id: their listening place follows (after each rebuild,
  // only when the list of books actually changed).
  var lastBooks = library.books;
  listening.adoptMoved(lastBooks);
  library.addListener(() {
    if (identical(library.books, lastBooks)) return;
    lastBooks = library.books;
    listening.adoptMoved(lastBooks);
  });

  // The player lives for the whole app, and the system media controls
  // (Android notification/lock screen, Windows media keys) are wired to it.
  final player = PlayerModel(library, listening: listening, equalizer: equalizer);
  // Save the place in an audiobook whenever the app is put away.
  WidgetsBinding.instance.addObserver(_SaveOnBackground(player));
  if (Platform.isWindows) {
    // Make sure the Windows media-controls plugin is the one audio_service uses.
    AudioServiceWin.registerWith();
  }
  // Can come back null (e.g. the platform refused); the app still works, just without
  // the system controls.
  final session = await MediaSession.start(player, library);
  debugPrint(session == null
      ? 'HomeTunes: system media controls are off'
      : 'HomeTunes: system media controls connected');

  // 3. Show the app. Everything below runs after the first screen is up.
  runApp(HomeTunesApp(
    library: library,
    playlists: playlists,
    listening: listening,
    bookmarks: bookmarks,
    lyrics: lyrics,
    equalizer: equalizer,
    player: player,
    updates: updates,
  ));

  // Look for a newer HomeTunes once a day, a little after start-up so it doesn't compete with
  // the scan; if there is one, a notice with an Update… button appears (0.1.23).
  Future<void>.delayed(const Duration(seconds: 8), () async {
    final found = await updates.checkIfDue();
    if (found != null) showUpdateNotice(found);
  });

  // Android: can we read the music files? (Shows a banner with a fix if not.)
  await library.refreshMusicAccess(rescanIfNewlyAllowed: false);

  // Pick up new / changed files in the background after start-up.
  if (library.folders.isNotEmpty) library.scanLocal(); // not awaited on purpose
}

/// Watches the app going into / coming out of the background (a Flutter lifecycle observer).
class _SaveOnBackground with WidgetsBindingObserver {
  final PlayerModel player;
  _SaveOnBackground(this.player);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    PlaybackLog.add('App ${state.name}${player.playing ? ' (playing)' : ''}');
    if (state == AppLifecycleState.resumed) {
      // Back from the phone's Settings: music access may have been turned on.
      player.library.refreshMusicAccess();
      // Playback may have been stopped while the app was asleep.
      player.checkAfterResume();
    } else {
      // Any other state (inactive, paused, hidden, detached) may be the last chance
      // before the app is closed, so save the book place (and anything else waiting) now.
      player.saveBookPlace();
      player.library.flushPendingSaves();
    }
  }
}

/// The root widget. Makes every model available to the screens below it and
/// starts the [Shell] (the sidebar / bottom-bar frame that holds all the pages).
class HomeTunesApp extends StatelessWidget {
  final LibraryModel library;
  final PlaylistsModel playlists;
  final ListeningModel listening;
  final BookmarksModel bookmarks;
  final LyricsModel lyrics;
  final EqualizerModel equalizer;
  final PlayerModel player;
  final UpdateModel updates;
  const HomeTunesApp({
    super.key,
    required this.library,
    required this.playlists,
    required this.listening,
    required this.bookmarks,
    required this.lyrics,
    required this.equalizer,
    required this.player,
    required this.updates,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Models made in main() are passed in with `.value`, so Provider won't dispose them.
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: playlists),
        ChangeNotifierProvider.value(value: listening),
        ChangeNotifierProvider.value(value: bookmarks),
        ChangeNotifierProvider.value(value: lyrics),
        ChangeNotifierProvider.value(value: equalizer),
        ChangeNotifierProvider.value(value: player),
        ChangeNotifierProvider.value(value: updates),
        // These only matter to the UI, so Provider creates (and owns) them itself.
        ChangeNotifierProvider(create: (_) => SleepTimer(player, library)),
        ChangeNotifierProvider(create: (_) => AppNav()),
        ChangeNotifierProvider(create: (_) => SelectionModel()),
      ],
      // The look from Settings › Appearance: colour theme (0.1.24), text size and corner
      // roundness (0.1.25). Only a change to one of those rebuilds this; then every screen is
      // redrawn so colours and corners read from AppColors / AppShape change too.
      child: Selector<LibraryModel, AppLook>(
        selector: (_, lib) => lookOfSettings(lib),
        builder: (context, look, _) {
          AppColors.current = look.palette;
          AppShape.scale = look.corners;
          return RedrawOnThemeChange(
            look: look,
            child: MaterialApp(
              title: 'HomeTunes',
              debugShowCheckedModeBanner: false,
              // Let the start-up update notice (and its dialog) be shown from outside the tree.
              scaffoldMessengerKey: appMessengerKey,
              navigatorKey: appNavigatorKey,
              theme: buildTheme(look.palette, look.corners),
              scrollBehavior: appScrollBehavior,
              // Text size: on top of the system's own setting.
              builder: (context, child) => withTextSize(context, look.textSize, child!),
              home: const Shell(),
            ),
          );
        },
      ),
    );
  }
}

/// Lists can be dragged with a mouse as well as a finger, so rows that go off
/// the side of the window can be pulled across on a PC.
final appScrollBehavior = const MaterialScrollBehavior().copyWith(
  dragDevices: {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  },
);
