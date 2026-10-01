// 0.1.41: titles you can highlight and copy, Search finding videos and video collections, and the
// app shrinking a little in a small window (with a switch in Settings › Appearance).
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/search_screen.dart';
import 'package:hometunes/ui/widgets/selectable_title.dart';
import 'package:hometunes/ui/widgets/window_scale.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  group('shrink to fit small windows', () {
    test('full size in a big window, down to 80 % in a small one, in between gradually', () {
      expect(WindowScale.factorFor(const Size(1600, 1000)), 1.0);
      expect(WindowScale.factorFor(const Size(1200, 760)), 1.0);
      expect(WindowScale.factorFor(const Size(700, 900)), WindowScale.smallest);
      expect(WindowScale.factorFor(const Size(1400, 400)), WindowScale.smallest); // short counts too
      final middle = WindowScale.factorFor(const Size(980, 900));
      expect(middle, closeTo(0.9, 0.001));
    });

    Future<Size> layoutSize(WidgetTester tester, {required bool enabled, bool desktop = true}) async {
      late Size seen;
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => WindowScale(enabled: enabled, desktop: desktop, child: child!),
        home: Builder(builder: (context) {
          seen = MediaQuery.sizeOf(context);
          return Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: TextButton(key: const ValueKey('corner'), onPressed: () => taps++, child: const Text('Corner')),
            ),
          );
        }),
      ));
      // A click still lands on the button where it's drawn.
      await tester.tap(find.byKey(const ValueKey('corner')));
      expect(taps, 1);
      return seen;
    }

    testWidgets('a small window lays the app out bigger and draws it smaller; the switch turns it off',
        (tester) async {
      tester.view.physicalSize = const Size(800, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final factor = WindowScale.factorFor(const Size(800, 560));
      expect(factor, lessThan(0.9));

      final scaled = await layoutSize(tester, enabled: true);
      expect(scaled.width, closeTo(800 / factor, 0.01));
      expect(find.byKey(const ValueKey('window-scale')), findsOneWidget);
      // Drawn inside the window: the bottom-right button is still on screen.
      final corner = tester.getBottomRight(find.byKey(const ValueKey('corner')));
      expect(corner.dx, lessThanOrEqualTo(800.5));
      expect(corner.dy, lessThanOrEqualTo(560.5));

      expect(await layoutSize(tester, enabled: false), const Size(800, 560));
      expect(await layoutSize(tester, enabled: true, desktop: false), const Size(800, 560)); // phones
    });

    test('the switch is saved in settings.json, on by default', () async {
      final dir = Directory.systemTemp.createTempSync('hometunes_scale');
      addTearDown(() => dir.deleteSync(recursive: true));
      final storage = Storage.at(dir);
      final lib = LibraryModel(storage);
      expect(lib.scaleWithWindow, isTrue);
      await lib.setScaleWithWindow(false);
      final again = LibraryModel(storage);
      await again.load();
      expect(again.scaleWithWindow, isFalse);
    });
  });

  group('titles you can copy', () {
    late List<String> clipboard;
    setUp(() {
      clipboard = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.setData') clipboard.add((call.arguments as Map)['text'] as String);
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    testWidgets('a page title can be selected', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SelectableTitle('Holston\'s Pick', maxLines: 1))));
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.text('Holston\'s Pick'), findsOneWidget);
    });

    testWidgets('"Copy title" puts it on the clipboard and says so', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => copyTitle(context, 'Silo'), child: const Text('go')),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(clipboard, ['Silo']);
      expect(find.text('Copied "Silo"'), findsOneWidget);
    });
  });

  group('Search finds videos and collections', () {
    late Directory dir;
    late Storage storage;
    late LibraryModel lib;
    late VideoLibraryModel videos;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_search_videos');
      storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      lib = LibraryModel(storage);
      videos = VideoLibraryModel(storage, lib);
      final season = Directory(p.join(dir.path, 'vids', 'TV', 'Silo', 'Season 1'))..createSync(recursive: true);
      File(p.join(season.path, 'Silo S01E01 Freedom Day.mkv')).writeAsBytesSync([1]);
      File(p.join(season.path, 'Silo S01E02 Holston\'s Pick.mkv')).writeAsBytesSync([1]);
      final films = Directory(p.join(dir.path, 'vids', 'Films', 'Arrival'))..createSync(recursive: true);
      File(p.join(films.path, 'Arrival.mp4')).writeAsBytesSync([1]);
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

    testWidgets('shelves for video collections and videos; a video\'s menu has Copy title', (tester) async {
      await tester.runAsync(() async {
        await lib.addVideoFolder(p.join(dir.path, 'vids'));
        await videos.settle();
        await videos.scan();
      });
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final nav = AppNav();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: videos),
          ChangeNotifierProvider.value(value: nav),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ));
      await tester.enterText(find.byType(TextField), 'silo');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-collections')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-videos')), findsOneWidget);
      expect(find.text('Video collections'), findsOneWidget);
      expect(find.text('Holston\'s Pick'), findsOneWidget);
      expect(find.text('Arrival'), findsNothing);

      await tester.enterText(find.byType(TextField), 'films arrival');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-collections')), findsOneWidget); // category "Films"

      await tester.enterText(find.byType(TextField), 'holston');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-collections')), findsNothing);
      await tester.tap(find.text('Holston\'s Pick'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('copy-title')), findsOneWidget);
      expect(find.text('Select'), findsNothing); // nothing to select in Search
    });
  });
}
