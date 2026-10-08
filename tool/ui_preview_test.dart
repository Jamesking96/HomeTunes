// Draws the 0.1.26 changes off-screen and saves pictures to C:\Temp\ht\preview (nothing is
// shown on screen): an artist page with an album's songs open in place and the hover play
// button showing, the queue drawer over a page, and Settings › Folders & scanning with the tabs
// in A–Z order. Uses Windows' Segoe UI so the text is readable. Invented titles only.
//   flutter test tool/ui_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/equalizer_model.dart';
import 'package:hometunes/state/library_index.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/state/update_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/artist_screen.dart';
import 'package:hometunes/ui/screens/queue_screen.dart';
import 'package:hometunes/ui/screens/settings/settings_screen.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class _Player extends ChangeNotifier implements PlayerModel {
  @override
  Track? get current => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Track _t(String title, String album, int no, int year) => Track(
      id: 'local:/m/The Lanterns/$album/$title.mp3',
      source: TrackSource.local,
      title: title,
      artist: 'The Lanterns',
      album: album,
      albumArtist: 'The Lanterns',
      year: year,
      trackNumber: no,
      duration: Duration(minutes: 3, seconds: no * 7),
      path: '/m/The Lanterns/$album/$title.mp3',
    );

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: r'C:\Temp\ht\preview');

  testWidgets('0.1.26 previews', (tester) async {
    await tester.runAsync(() async {
      for (final f in [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\segoeuib.ttf']) {
        final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
        await loader.load();
      }
    });
    // ignore: invalid_use_of_visible_for_testing_member
    PackageInfo.setMockInitialValues(
        appName: 'HomeTunes', packageName: 'x', version: '0.1.26', buildNumber: '26', buildSignature: '');
    Directory(out).createSync(recursive: true);
    final dir = freshPreviewFolder('hometunes_ui_preview');
    final songs = [
      _t('Paper Lanterns', 'First Light', 1, 2001),
      _t('Harbour Wall', 'First Light', 2, 2001),
      _t('Salt and Smoke', 'First Light', 3, 2001),
      _t('Slow Engines', 'Second Wind', 1, 2004),
      _t('Copper Sky', 'Second Wind', 2, 2004),
      _t('Night Ferry', 'Second Wind', 3, 2004),
      _t('Lamplight', 'Third Coast', 1, 2008),
      _t('Low Tide', 'Fourth Wall', 1, 2012),
      _t('Signal Fire', 'Fifth Season', 1, 2015),
    ];
    final albums = groupAlbums(songs);
    final lib = LibraryModel(Storage.at(dir))
      ..tracks = songs
      ..albums = albums
      ..artists = groupArtists(albums);
    final nav = AppNav();
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();

    Future<void> show(Widget home) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: nav),
          ChangeNotifierProvider(create: (_) => PlaylistsModel(Storage.at(dir))),
          ChangeNotifierProvider<PlayerModel>.value(value: _Player()),
          ChangeNotifierProvider(create: (_) => SelectionModel()),
          ChangeNotifierProvider(create: (_) => EqualizerModel(Storage.at(dir))),
          ChangeNotifierProvider(create: (_) => VideoLibraryModel(Storage.at(dir), lib)),
          ChangeNotifierProvider(create: (_) => UpdateModel(Storage.at(dir), readVersion: () async => '0.1.26')),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: home),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> shoot(String name) => tester.runAsync(() async {
          final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final png = await (await b.toImage()).toByteData(format: ui.ImageByteFormat.png);
          File('$out\\$name.png').writeAsBytesSync(png!.buffer.asUint8List());
        });

    // 1. Artist page: "Second Wind" open in place, the mouse over "Third Coast".
    await show(const ArtistScreen(name: 'The Lanterns'));
    await tester.tap(find.text('Second Wind').first);
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(ValueKey('hover-play:${albums.firstWhere((a) => a.title == 'Third Coast').key}'))));
    await tester.pumpAndSettle();
    await shoot('ui-artist');
    await mouse.removePointer();

    // 2. The queue drawer over a page.
    await show(const ArtistScreen(name: 'The Lanterns'));
    openQueueDrawer(key.currentContext!.findAncestorStateOfType<NavigatorState>()?.context ??
        tester.element(find.byType(ArtistScreen)));
    await tester.pumpAndSettle();
    await shoot('ui-queue');

    // 3. Settings › Folders & scanning.
    await show(const SettingsScreen());
    nav.openSettings('library');
    await tester.pumpAndSettle();
    await shoot('ui-settings');

    // 4. A folder's options (0.1.27), for a real folder of sample files, with FLAC switched off.
    final music = Directory('${dir.path}\\Music')..createSync();
    for (final (from, to) in [
      ('tagged.mp3', 'a.mp3'), ('tagged_v24.mp3', 'b.mp3'), ('tagged.flac', 'c.flac'), ('tagged.m4a', 'd.m4a'),
    ]) {
      File('test\\fixtures\\$from').copySync('${music.path}\\$to');
    }
    Directory('${dir.path}\\data').createSync();
    final real = LibraryModel(Storage.at(Directory('${dir.path}\\data')))..folders = [music.path];
    await tester.runAsync(real.scanLocal);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: real),
        ChangeNotifierProvider.value(value: nav),
        ChangeNotifierProvider(create: (_) => PlaylistsModel(Storage.at(dir))),
        ChangeNotifierProvider<PlayerModel>.value(value: _Player()),
        ChangeNotifierProvider(create: (_) => SelectionModel()),
        ChangeNotifierProvider(create: (_) => EqualizerModel(Storage.at(dir))),
        ChangeNotifierProvider(create: (_) => VideoLibraryModel(Storage.at(dir), real)),
        ChangeNotifierProvider(create: (_) => UpdateModel(Storage.at(dir), readVersion: () async => '0.1.27')),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: const SettingsScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    nav.openSettings('library');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Folder options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('File types'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FLAC'));
    await tester.pumpAndSettle();
    await shoot('ui-folder-options');
  });
}

// A fixed folder (emptied first), so the same path shows in the pictures every run and
// tool\compare_previews.ps1 can compare them byte for byte (8 Oct 2026).
Directory freshPreviewFolder(String name) {
  final d = Directory('C:\\Temp\\ht\\preview-data\\$name');
  if (d.existsSync()) d.deleteSync(recursive: true);
  return d..createSync(recursive: true);
}
