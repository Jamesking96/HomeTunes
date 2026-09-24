import 'dart:io';

import 'package:audio_service_win/audio_service_win.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'services/media_session.dart';
import 'services/storage.dart';
import 'state/library_model.dart';
import 'state/player_model.dart';
import 'state/playlists_model.dart';
import 'state/selection_model.dart';
import 'ui/nav.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final storage = await Storage.open();
  final library = LibraryModel(storage);
  final playlists = PlaylistsModel(storage);
  await Future.wait([library.load(), playlists.load()]);

  // The player lives for the whole app, and the system media controls
  // (Android notification/lock screen, Windows media keys) are wired to it.
  final player = PlayerModel(library);
  if (Platform.isWindows) {
    // Make sure the Windows media-controls plugin is the one audio_service uses.
    AudioServiceWin.registerWith();
  }
  final session = await MediaSession.start(player, library);
  debugPrint(session == null
      ? 'HomeTunes: system media controls are off'
      : 'HomeTunes: system media controls connected');

  runApp(HomeTunesApp(library: library, playlists: playlists, player: player));

  // Pick up new / changed files in the background after start-up.
  if (library.folders.isNotEmpty) library.scanLocal();
}

class HomeTunesApp extends StatelessWidget {
  final LibraryModel library;
  final PlaylistsModel playlists;
  final PlayerModel player;
  const HomeTunesApp({super.key, required this.library, required this.playlists, required this.player});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: playlists),
        ChangeNotifierProvider.value(value: player),
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
