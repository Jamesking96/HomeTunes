// 0.1.48: Esc cancels a selection (EscapeCancels on every selection bar), but only when that
// page is in front: with a dialog open, Esc closes the dialog and the selection stays.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/video_collection_screen.dart';
import 'package:hometunes/ui/widgets/escape_cancels.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  testWidgets('EscapeCancels: Esc cancels while in front, not under a dialog or another page', (tester) async {
    var cancelled = 0;
    late BuildContext inside;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EscapeCancels(
          onCancel: () => cancelled++,
          child: Builder(builder: (c) {
            inside = c;
            return const Text('bar');
          }),
        ),
      ),
    ));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(cancelled, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA); // other keys do nothing
    expect(cancelled, 1);

    // A dialog in front: Esc closes it and leaves the selection alone.
    showDialog<void>(context: inside, builder: (_) => const AlertDialog(content: Text('hello')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsNothing);
    expect(cancelled, 1);

    // Another page pushed over it.
    Navigator.of(inside).push(MaterialPageRoute<void>(builder: (_) => const Text('page')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(cancelled, 1);
    Navigator.of(inside).pop();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(cancelled, 2);
  });

  group('Videos', () {
    late Directory dir;
    late LibraryModel lib;
    late VideoLibraryModel videos;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_escape_select');
      final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      lib = LibraryModel(storage);
      videos = VideoLibraryModel(storage, lib);
    });
    tearDown(() async {
      await videos.settle();
      dir.deleteSync(recursive: true);
    });

    testWidgets('Esc clears the ticked episodes on a collection\'s page', (tester) async {
      final season = Directory(p.join(dir.path, 'vids', 'TV', 'Silo', 'Season 1'))..createSync(recursive: true);
      for (var e = 1; e <= 3; e++) {
        File(p.join(season.path, 'Silo S01E0$e.mkv')).writeAsBytesSync([1]);
      }
      await tester.runAsync(() async {
        await lib.addVideoFolder(p.join(dir.path, 'vids'));
        await videos.scan();
      });
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: videos),
          ChangeNotifierProvider(create: (_) => AppNav()),
        ],
        child: const MaterialApp(home: VideoCollectionScreen(name: 'Silo')),
      ));
      await tester.pumpAndSettle();
      Finder row(String label) =>
          find.descendant(of: find.byType(EpisodeRow), matching: find.textContaining(label, findRichText: true));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(row('S1 E1'));
      await tester.pumpAndSettle();
      await tester.tap(row('S1 E3'));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(find.text('3 selected'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('video-selection-bar')), findsNothing);
      expect(find.textContaining('selected'), findsNothing);
    });
  });
}
