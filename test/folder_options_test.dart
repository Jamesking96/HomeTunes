// Tests for 0.1.27: each music or audiobook folder's options (rescan just that folder, and
// switch the file types found in it on or off), and the speaker icon beside any volume slider
// being a quick mute / unmute. Scans use the small sample files in test/fixtures.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/ui/screens/settings/library_settings.dart';
import 'package:hometunes/ui/widgets/player_controls.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// Copies a sample file into [folder] as [name].
void put(String folder, String sample, String name) =>
    File(p.join('test', 'fixtures', sample)).copySync(p.join(folder, name));

/// Stands in for the player for the volume control.
class FakePlayer extends ChangeNotifier implements PlayerModel {
  @override
  double volume = 70;
  int muteToggles = 0;
  @override
  Future<void> toggleMute() async {
    muteToggles++;
    volume = volume > 0 ? 0 : 70;
    notifyListeners();
  }

  @override
  Future<void> setVolume(double v) async => volume = v;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late Directory dir;
  late String a, b;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_folder_opts');
    a = (Directory(p.join(dir.path, 'A'))..createSync()).path;
    b = (Directory(p.join(dir.path, 'B'))..createSync()).path;
    Directory(p.join(dir.path, 'data')).createSync(); // HomeTunes' own data folder
    put(a, 'tagged.mp3', 'one.mp3');
    put(a, 'tagged_v24.mp3', 'two.mp3');
    put(a, 'tagged.flac', 'three.flac');
    put(b, 'tagged.mp3', 'four.mp3');
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // A save started inside a widget test's pretend clock can still hold a file open; the
    // temp folder is then left for Windows to tidy away.
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException catch (_) {}
  });

  Future<LibraryModel> scanned() async {
    final lib = LibraryModel(Storage.at(Directory(p.join(dir.path, 'data'))));
    lib.folders = [a, b];
    await lib.scanLocal();
    return lib;
  }

  Set<String> names(LibraryModel lib) => {for (final t in lib.tracks) p.basename(t.path!)};

  test('file types are named from the extension', () {
    expect(LibraryModel.formatOf(r'C:\Music\Song.FLAC'), 'flac');
    expect(LibraryModel.formatOf('/m/a.b/track.m4a'), 'm4a');
    expect(LibraryModel.formatOf('/m/noext'), '');
  });

  test('each folder lists the file types found in it, with counts', () async {
    final lib = await scanned();
    expect(lib.formatsIn(a), {'flac': 1, 'mp3': 2});
    expect(lib.formatsIn(b), {'mp3': 1});
  });

  test('switching a type off in one folder leaves it out there only, and is remembered', () async {
    final lib = await scanned();
    await lib.setFormatShown(a, 'mp3', false);
    expect(names(lib), {'three.flac', 'four.mp3'}); // B's MP3 still shows
    expect(lib.formatShown(a, 'mp3'), isFalse);
    expect(lib.formatsIn(a), {'flac': 1, 'mp3': 2}); // still listed so it can be switched back

    final again = LibraryModel(Storage.at(Directory(p.join(dir.path, 'data'))));
    await again.load();
    expect(again.hiddenFormats, {a: ['mp3']});
    expect(names(again), {'three.flac', 'four.mp3'});

    await again.setFormatShown(a, 'mp3', true);
    expect(names(again), {'one.mp3', 'two.mp3', 'three.flac', 'four.mp3'});
    expect(again.hiddenFormats, isEmpty);
  });

  test('rescanning one folder picks up its changes and leaves the others alone', () async {
    final lib = await scanned();
    put(a, 'tagged.m4a', 'five.m4a');
    put(b, 'tagged.flac', 'six.flac');
    File(p.join(a, 'two.mp3')).deleteSync();
    await lib.scanFolder(a);
    expect(names(lib), {'one.mp3', 'three.flac', 'five.m4a', 'four.mp3'}); // not six.flac yet
    expect(lib.formatsIn(a), {'flac': 1, 'm4a': 1, 'mp3': 1});
    await lib.scanLocal();
    expect(names(lib), contains('six.flac'));
  });

  test('removing a folder forgets its file type choices', () async {
    final lib = await scanned();
    await lib.setFormatShown(b, 'mp3', false);
    await lib.removeFolder(b);
    expect(lib.hiddenFormats, isEmpty);
  });

  test('mute remembers the volume; unmuting after dragging to 0 goes to half', () {
    expect(PlayerModel.muteToggle(70, null), (0, 70));
    expect(PlayerModel.muteToggle(0, 70), (70, null));
    expect(PlayerModel.muteToggle(0, null), (50, null));
  });

  testWidgets('the options window: Rescan, and tick boxes for each file type', (tester) async {
    final lib = (await tester.runAsync(scanned))!;
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
        ChangeNotifierProvider(create: (_) => VideoLibraryModel(lib.storage, lib)),
      ],
      child: const MaterialApp(home: Scaffold(body: LibrarySettings())),
    ));
    await tester.tap(find.byKey(ValueKey('folder-options:$a')));
    await tester.pumpAndSettle();
    expect(find.text('Rescan this folder'), findsOneWidget);
    expect(find.byKey(const ValueKey('rescan-folder')), findsOneWidget);
    expect(find.text('All 2 included'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('format-filter'))); // open the drop-down
    await tester.pumpAndSettle();
    expect(find.text('MP3'), findsOneWidget);
    expect(find.text('FLAC'), findsOneWidget);
    expect(find.text('2 files'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('format:flac')));
    await tester.pump();
    expect(lib.formatShown(a, 'flac'), isFalse);
    expect(names(lib), isNot(contains('three.flac')));
    expect(find.textContaining('FLAC left out'), findsOneWidget);
  });

  testWidgets('the speaker icon beside the volume slider mutes and unmutes', (tester) async {
    final player = FakePlayer();
    await tester.pumpWidget(ChangeNotifierProvider<PlayerModel>.value(
      value: player,
      child: const MaterialApp(home: Scaffold(body: Center(child: VolumeControl()))),
    ));
    expect(find.byTooltip('Mute'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mute-toggle')));
    await tester.pump();
    expect(player.muteToggles, 1);
    expect(find.byTooltip('Unmute'), findsOneWidget);
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mute-toggle')));
    await tester.pump();
    expect(player.volume, 70);
  });
}
