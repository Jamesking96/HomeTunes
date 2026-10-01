// 0.1.40: video folders get the same Folder options as music and audiobook folders: Rescan this
// folder, and File types (switch a type off to leave it out of the Videos tab).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/screens/settings/library_settings.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;
  late VideoLibraryModel videos;
  late String a, b;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_video_folder_opts');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
    videos = VideoLibraryModel(storage, lib);
    a = (Directory(p.join(dir.path, 'A'))..createSync()).path;
    b = (Directory(p.join(dir.path, 'B'))..createSync()).path;
    for (final n in ['One.mkv', 'Two.mkv', 'Three.avi']) {
      File(p.join(a, n)).writeAsBytesSync([1]);
    }
    File(p.join(b, 'Film.mp4')).writeAsBytesSync([1]);
  });
  tearDown(() async {
    await videos.settle();
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        // try again
      }
    }
  });

  Future<void> addBoth() async {
    await lib.addVideoFolder(a);
    await lib.addVideoFolder(b);
    await videos.settle();
    await videos.scan();
  }

  test('file types per video folder: counted, switched off at once, kept in settings.json', () async {
    await addBoth();
    expect(videos.videos, hasLength(4));
    expect(videos.formatsIn(a), {'avi': 1, 'mkv': 2});
    expect(videos.formatsIn(b), {'mp4': 1});

    await lib.setFormatShown(a, 'mkv', false);
    expect([for (final v in videos.videos) v.title]..sort(), ['Film', 'Three']);
    // Still counted, so it can be ticked again.
    expect(videos.formatsIn(a), {'avi': 1, 'mkv': 2});

    final again = LibraryModel(storage);
    await again.load();
    expect(again.formatShown(a, 'mkv'), isFalse);

    await lib.setFormatShown(a, 'mkv', true);
    expect(videos.videos, hasLength(4));

    // Removing the folder forgets its choices.
    await lib.setFormatShown(a, 'avi', false);
    await lib.removeVideoFolder(a);
    expect(lib.hiddenFormats.containsKey(a), isFalse);
  });

  test('rescan one video folder: finds its new and removed videos, leaves the others alone', () async {
    await addBoth();
    File(p.join(a, 'Four.webm')).writeAsBytesSync([1]);
    File(p.join(a, 'One.mkv')).deleteSync();
    File(p.join(b, 'Second film.mp4')).writeAsBytesSync([1]); // not looked for
    await videos.scanFolder(a);
    expect([for (final v in videos.videos) v.title]..sort(), ['Film', 'Four', 'Three', 'Two']);
  });

  testWidgets('Settings: each video folder has Folder options with Rescan and File types', (tester) async {
    await tester.runAsync(addBoth);
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
        ChangeNotifierProvider.value(value: videos),
      ],
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: VideoFoldersSection()))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('folder-options:$b')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('folder-options:$a')));
    await tester.pumpAndSettle();
    expect(find.text('Rescan this folder'), findsOneWidget);
    expect(find.textContaining('removed videos in this folder only'), findsOneWidget);
    expect(find.text('All 2 included'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('format-filter')));
    await tester.pumpAndSettle();
    expect(find.text('2 videos'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('format:avi')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('AVI left out'), findsOneWidget);
    expect(videos.videos.any((v) => v.title == 'Three'), isFalse);
  });
}
