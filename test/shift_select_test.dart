// 0.1.47: holding Shift while clicking ticks everything between the last item clicked and this
// one, in every select mode (songs, albums, audiobooks, videos and collections).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/range_select.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/video_collection_screen.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  const order = ['a', 'b', 'c', 'd', 'e'];

  group('idsBetween', () {
    test('either direction, both ends included', () {
      expect(idsBetween(order, 'b', 'd'), ['b', 'c', 'd']);
      expect(idsBetween(order, 'd', 'b'), ['b', 'c', 'd']);
      expect(idsBetween(order, 'c', 'c'), ['c']);
    });
    test('null when either end is not in the list', () {
      expect(idsBetween(order, 'x', 'b'), isNull);
      expect(idsBetween(order, 'b', 'x'), isNull);
    });
  });

  group('RangePicker and SelectionModel.pick', () {
    tearDown(() async {
      await HardwareKeyboard.instance.syncKeyboardState();
    });

    testWidgets('a plain click toggles; Shift + click fills the gap', (tester) async {
      final picker = RangePicker();
      final picked = <String>{};
      picker.pick(picked, 'b', order);
      expect(picked, {'b'});
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      picker.pick(picked, 'e', order);
      expect(picked, {'b', 'c', 'd', 'e'});
      // Backwards from the new anchor (e) to a.
      picker.pick(picked, 'a', order);
      expect(picked, order.toSet());
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      picker.pick(picked, 'c', order);
      expect(picked, {'a', 'b', 'd', 'e'});
    });

    testWidgets('Shift with nothing ticked yet just ticks the one item', (tester) async {
      final picker = RangePicker()..anchor = 'a'; // left over from an earlier selection
      final picked = <String>{};
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      picker.pick(picked, 'd', order);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(picked, {'d'});
    });

    testWidgets('SelectionModel: albums range, then cleared starts afresh', (tester) async {
      final s = SelectionModel();
      s.pick('b', order, kind: SelectKind.albums);
      expect(s.selecting(SelectKind.albums), isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      s.pick('d', order, kind: SelectKind.albums);
      expect(s.ids, {'b', 'c', 'd'});
      s.clear();
      s.pick('e', order, kind: SelectKind.albums);
      expect(s.ids, {'e'});
      // Switching kind starts a new selection too.
      s.pick('a', order);
      expect(s.kind, SelectKind.songs);
      expect(s.ids, {'a'});
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });
  });

  group('Videos', () {
    late Directory dir;
    late LibraryModel lib;
    late VideoLibraryModel videos;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_shift_select');
      final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      lib = LibraryModel(storage);
      videos = VideoLibraryModel(storage, lib);
    });
    tearDown(() async {
      await videos.settle();
      dir.deleteSync(recursive: true);
    });

    testWidgets('Shift + click on episodes ticks the ones between, across seasons', (tester) async {
      for (var s = 1; s <= 2; s++) {
        final season = Directory(p.join(dir.path, 'vids', 'TV', 'Silo', 'Season $s'))..createSync(recursive: true);
        for (var e = 1; e <= 3; e++) {
          File(p.join(season.path, 'Silo S0${s}E0$e.mkv')).writeAsBytesSync([1]);
        }
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

      // Shift + click starts selecting without opening the video, then a second one fills the gap.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(row('S1 E2'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(row('S2 E2'));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(find.text('4 selected'), findsOneWidget); // S1 E2, S1 E3, S2 E1, S2 E2

      // A plain click still unticks just one.
      await tester.tap(row('S1 E3'));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
    });
  });
}
