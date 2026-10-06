// Playlist icons (0.1.67): a built-in icon on a colour, or a chosen picture (copied into the
// app's folder, tidied when unused, carried by backups), else the first song's cover.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/playlist.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/ui/widgets/playlist_art.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;
  late PlaylistsModel playlists;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_playlist_icons');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
    playlists = PlaylistsModel(storage);
  });
  tearDown(() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        // a write still finishing
      }
    }
  });

  test('saved with the playlist; a picture name can\'t point outside its folder', () {
    final pl = Playlist(id: '1', name: 'Run', iconName: 'run', iconColour: 0xFFE53935);
    final back = Playlist.fromJson(pl.toJson());
    expect((back.iconName, back.iconColour, back.iconImage, back.hasOwnIcon), ('run', 0xFFE53935, null, true));
    expect(Playlist(id: '2', name: 'x').toJson().containsKey('iconName'), isFalse);
    for (final bad in ['../evil.png', r'..\evil.png', 'a/b.png', '.hidden']) {
      final j = {'id': '3', 'name': 'x', 'trackIds': <String>[], 'iconImage': bad};
      expect(Playlist.fromJson(j).iconImage, isNull, reason: bad);
    }
    expect(Playlist.fromJson({'id': '3', 'name': 'x', 'trackIds': <String>[], 'iconImage': 'abc.png'}).iconImage,
        'abc.png');
  });

  test('icon, picture, back to the cover: kept, and unused pictures tidied away', () async {
    final pl = playlists.create('Gym');
    playlists.setIcon(pl, 'fitness', 0xFF43A047);
    final source = File(p.join(dir.path, 'me.png'))..writeAsBytesSync([137, 80, 78, 71, 1, 2, 3]);
    await playlists.setPicture(pl, source.path);
    final file = playlists.pictureFile(pl)!;
    expect(p.isWithin(playlists.pictureDir, file), isTrue);
    expect(p.isWithin(storage.artDir, file) && p.split(file).contains('custom'), isTrue); // backed up
    expect((pl.iconName, pl.iconColour), (null, null));
    source.deleteSync();
    expect(File(file).existsSync(), isTrue); // its own copy

    await Future<void>.delayed(const Duration(milliseconds: 200));
    final again = PlaylistsModel(storage);
    await again.load();
    expect(again.pictureFile(again.byId(pl.id)!), file);

    playlists.setIcon(pl, 'rocket', null);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(File(file).existsSync(), isFalse); // nothing uses it now
    playlists.clearIcon(pl);
    expect(pl.hasOwnIcon, isFalse);
  });

  test('merging a backup: a playlist without an icon takes the backup\'s', () {
    Map<String, dynamic> file(Map<String, dynamic> pl) => {'playlists': [pl]};
    final merged = AppBackup.mergePlaylists(
      file({'id': '1', 'name': 'Run', 'trackIds': ['a']}),
      file({'id': '1', 'name': 'Run', 'trackIds': ['b'], 'iconName': 'run', 'iconColour': 1}),
    );
    final pl = (merged['playlists'] as List).single as Map;
    expect((pl['iconName'], pl['iconColour']), ('run', 1));
    expect(pl['trackIds'], ['a', 'b']);
    final kept = AppBackup.mergePlaylists(
      file({'id': '1', 'name': 'Run', 'trackIds': <String>[], 'iconImage': 'x.png'}),
      file({'id': '1', 'name': 'Run', 'trackIds': <String>[], 'iconName': 'run'}),
    );
    final k = (kept['playlists'] as List).single as Map;
    expect((k['iconImage'], k['iconName']), ('x.png', null));
  });

  Future<void> pump(WidgetTester tester, Widget body) => tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: playlists),
        ],
        child: MaterialApp(home: Scaffold(body: body)),
      ));

  testWidgets('the art: the icon when it has one, else the cover; the chooser sets it', (tester) async {
    final pl = playlists.create('Chill');
    await pump(
      tester,
      Builder(
        builder: (context) => Column(children: [
          PlaylistArt(playlist: pl, size: 52),
          TextButton(onPressed: () => showPlaylistIconPicker(context, pl), child: const Text('change')),
        ]),
      ),
    );
    expect(find.byKey(const ValueKey('playlist-icon')), findsNothing); // the first song's cover

    await tester.tap(find.text('change'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('playlist-icon-reset')), findsNothing); // nothing to undo yet
    await tester.tap(find.byKey(const ValueKey('playlist-icon:spa')));
    await tester.tap(find.byKey(ValueKey('playlist-colour:${playlistColours[2]}')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('playlist-icon-save')));
    await tester.pumpAndSettle();
    expect((pl.iconName, pl.iconColour), ('spa', playlistColours[2]));
    expect(find.descendant(of: find.byKey(const ValueKey('playlist-icon')), matching: find.byIcon(Icons.spa)),
        findsOneWidget);

    // Back to the cover.
    await tester.tap(find.text('change'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('playlist-icon-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-icon-reset')));
    await tester.pumpAndSettle();
    expect(pl.hasOwnIcon, isFalse);
    expect(find.byKey(const ValueKey('playlist-icon')), findsNothing);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  });
}
