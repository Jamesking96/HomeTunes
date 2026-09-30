// Settings › Music (0.1.32): music videos on or off, and whether they start by themselves.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/ui/screens/settings/music_settings.dart';
import 'package:hometunes/ui/screens/settings/settings_catalog.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_music_settings');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
  });
  tearDown(() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        // a settings write still finishing
      }
    }
  });

  test('auto-play is on unless turned off, and is saved', () async {
    expect((lib.showMusicVideos, lib.autoPlayMusicVideos), (true, true));
    await lib.updatePlaybackSettings(autoPlayMusicVideos: false);
    final again = LibraryModel(storage);
    await again.load();
    expect((again.showMusicVideos, again.autoPlayMusicVideos), (true, false));
  });

  test('the Music page is listed (in A–Z order) and holds the music video settings', () {
    final titles = [for (final pg in SettingsPage.values) pg.title];
    expect(titles.indexOf('Music'), titles.indexOf('Folders & scanning') + 1);
    expect([for (final s in settingsCatalog) if (s.page == SettingsPage.music) s.id],
        ['music-videos', 'music-video-autoplay']);
  });

  testWidgets('the switches change the settings; auto-play waits while videos are off', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: lib,
      child: const MaterialApp(home: Scaffold(body: MusicSettings())),
    ));
    await tester.tap(find.byKey(const ValueKey('music-video-autoplay')));
    await tester.pumpAndSettle();
    expect(lib.autoPlayMusicVideos, isFalse);
    expect(find.textContaining('press the video button'), findsOneWidget);

    await tester.tap(find.text('Show music videos'));
    await tester.pumpAndSettle();
    expect(lib.showMusicVideos, isFalse);
    final autoplay = tester.widget<SwitchListTile>(find.byKey(const ValueKey('music-video-autoplay')));
    expect(autoplay.onChanged, isNull);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  });
}
