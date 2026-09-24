import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'services/storage.dart';
import 'state/library_model.dart';
import 'state/player_model.dart';
import 'state/playlists_model.dart';
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

  runApp(HomeTunesApp(library: library, playlists: playlists));

  // Pick up new / changed files in the background after start-up.
  if (library.folders.isNotEmpty) library.scanLocal();
}

class HomeTunesApp extends StatelessWidget {
  final LibraryModel library;
  final PlaylistsModel playlists;
  const HomeTunesApp({super.key, required this.library, required this.playlists});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: playlists),
        ChangeNotifierProvider(create: (_) => PlayerModel(library)),
        ChangeNotifierProvider(create: (_) => AppNav()),
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
