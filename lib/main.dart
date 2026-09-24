import 'dart:io';

import 'package:audio_service_win/audio_service_win.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'services/media_session.dart';
import 'services/storage.dart';
import 'state/library_model.dart';
import 'state/listening_model.dart';
import 'state/player_model.dart';
import 'state/playlists_model.dart';
import 'state/selection_model.dart';
import 'state/sleep_timer.dart';
import 'ui/nav.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final storage = await Storage.open();
  final library = LibraryModel(storage);
  final playlists = PlaylistsModel(storage);
  final listening = ListeningModel(storage);
  await Future.wait([library.load(), playlists.load(), listening.load()]);
  // Songs in playlists / Liked Songs are kept track of even when their files
  // are missing, and follow them if they move.
  library
    ..otherReferencedIds = (() => {...playlists.referencedIds, ...listening.referencedIds})
    ..onIdsRemapped = ((moved) {
      playlists.remapIds(moved);
      listening.remapIds(moved);
    })
    ..onIdsForgotten = ((ids) {
      playlists.removeIds(ids);
      listening.removeIds(ids);
    });

  // The player lives for the whole app, and the system media controls
  // (Android notification/lock screen, Windows media keys) are wired to it.
  final player = PlayerModel(library, listening: listening);
  // Save the place in an audiobook whenever the app is put away.
  WidgetsBinding.instance.addObserver(_SaveOnBackground(player));
  if (Platform.isWindows) {
    // Make sure the Windows media-controls plugin is the one audio_service uses.
    AudioServiceWin.registerWith();
  }
  final session = await MediaSession.start(player, library);
  debugPrint(session == null
      ? 'HomeTunes: system media controls are off'
      : 'HomeTunes: system media controls connected');

  runApp(HomeTunesApp(library: library, playlists: playlists, listening: listening, player: player));

  // Android: can we read the music files? (Shows a banner with a fix if not.)
  await library.refreshMusicAccess(rescanIfNewlyAllowed: false);

  // Pick up new / changed files in the background after start-up.
  if (library.folders.isNotEmpty) library.scanLocal();
}

class _SaveOnBackground with WidgetsBindingObserver {
  final PlayerModel player;
  _SaveOnBackground(this.player);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Back from the phone's Settings: music access may have been turned on.
      player.library.refreshMusicAccess();
    } else {
      player.saveBookPlace();
    }
  }
}

class HomeTunesApp extends StatelessWidget {
  final LibraryModel library;
  final PlaylistsModel playlists;
  final ListeningModel listening;
  final PlayerModel player;
  const HomeTunesApp({
    super.key,
    required this.library,
    required this.playlists,
    required this.listening,
    required this.player,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: playlists),
        ChangeNotifierProvider.value(value: listening),
        ChangeNotifierProvider.value(value: player),
        ChangeNotifierProvider(create: (_) => SleepTimer(player, library)),
        ChangeNotifierProvider(create: (_) => AppNav()),
        ChangeNotifierProvider(create: (_) => SelectionModel()),
      ],
      child: MaterialApp(
        title: 'HomeTunes',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      ),
    );
  }
}
