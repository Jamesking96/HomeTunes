// Tests for Settings: the settings search (ui/screens/settings/settings_catalog.dart), the
// "audiobooks from the music server" option in LibraryModel, and widget tests that build the
// real Settings screens to check every setting in the catalogue actually appears on its page,
// and that search results open the right page on both phone-sized and wide windows.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/equalizer_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/update_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/settings/settings_catalog.dart';
import 'package:hometunes/ui/screens/settings/settings_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

void main() {
  group('Settings search', () {
    // Ids are used as widget keys and for jumping to a setting, so duplicates would break that.
    test('every setting has its own id', () {
      final ids = [for (final s in settingsCatalog) s.id];
      expect(ids.toSet().length, ids.length);
    });

    // Search matches the setting's name, its page name and extra keywords ("moon" -> the sleep
    // timer button, "navidrome" -> the server setting), ignoring upper/lower case.
    test('finds settings by name, page and other words', () {
      List<String> ids(String q) => [for (final s in searchSettings(q)) s.id];
      expect(ids('lyrics'), ['online-lyrics']);
      expect(ids('moon'), ['sleep-button']);
      expect(ids('SLEEP'), containsAll(['sleep-button', 'sleep-music', 'sleep-books', 'sleep-fade']));
      expect(ids('skip back'), ['skip-back']);
      expect(ids('navidrome'), ['server']);
      expect(ids('  '), isEmpty);
      expect(ids('no such thing'), isEmpty);
    });
  });

  group('Audiobooks from the music server', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_serverbooks'));
    // Short wait so any save still in progress finishes before the folder is deleted.
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      dir.deleteSync(recursive: true);
    });

    /// A song from the server; the "Audiobook" genre is what makes a server song count as a book.
    Track remote(String id, {String? genre}) => Track(
          id: 'server:$id',
          source: TrackSource.server,
          title: id,
          artist: 'A',
          album: id,
          albumArtist: 'A',
          genre: genre,
          duration: const Duration(minutes: 3),
          remoteId: id,
        );

    // Start from saved files containing one server song and one server book, then turn the
    // option off: the book disappears, the song stays, and the choice is remembered after reload.
    test('can be left out of the Books tab without touching server music', () async {
      final storage = Storage.at(dir);
      await storage.write('settings.json', {
        'serverEnabled': true,
        'server': {'url': 'http://example.invalid', 'username': 'u', 'password': 'p'},
      });
      await storage.write('library.json', {
        'local': [],
        'remote': [remote('song').toJson(), remote('book', genre: 'Audiobook').toJson()],
        'missing': [],
      });
      final lib = LibraryModel(storage);
      await lib.load();
      expect(lib.serverBooks, isTrue);
      expect(lib.books.length, 1);
      expect(lib.tracks.map((t) => t.title), ['song']);

      await lib.setServerBooks(false);
      expect(lib.books, isEmpty);
      expect(lib.tracks.map((t) => t.title), ['song']);

      final again = LibraryModel(storage);
      await again.load();
      expect(again.serverBooks, isFalse);
    });
  });

  group('Settings pages', () {
    late LibraryModel lib;
    late AppNav nav;

    // The About page shows the app version, which normally comes from the platform; fake it.
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'HomeTunes',
        packageName: 'com.hometunes.hometunes',
        version: '9.9.9',
        buildNumber: '99',
        buildSignature: '',
      );
      // Note: this library points at the system temp folder itself, not a fresh sub-folder.
      lib = LibraryModel(Storage.at(Directory(Directory.systemTemp.path)));
      nav = AppNav();
    });

    /// Builds [child] with the providers the Settings screens need, in a window of [size]
    /// (default: very tall, so every setting is laid out without scrolling).
    Future<void> pump(WidgetTester tester, Widget child, {Size size = const Size(1400, 4000)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: nav),
          ChangeNotifierProvider(create: (_) => EqualizerModel(Storage.at(Directory.systemTemp))),
          // About has "Check for updates"; nothing here goes online unless it's pressed.
          ChangeNotifierProvider(
              create: (_) => UpdateModel(Storage.at(Directory.systemTemp), readVersion: () async => '9.9.9')),
        ],
        child: MaterialApp(home: child),
      ));
      await tester.pump();
    }

    // One test per Settings page: each setting listed for that page in the catalogue must be on it.
    for (final page in SettingsPage.values) {
      testWidgets('${page.title} shows all of its settings', (tester) async {
        await pump(tester, Scaffold(body: settingsPageBody(page)));
        for (final s in settingsCatalog.where((s) => s.page == page)) {
          expect(find.byKey(ValueKey('setting:${s.id}')), findsOneWidget, reason: s.id);
        }
      });
    }

    testWidgets('every page is listed', (tester) async {
      await pump(tester, const SettingsScreen());
      for (final page in SettingsPage.values) {
        expect(find.text(page.title), findsWidgets, reason: page.title);
      }
    });

    // 400 px wide = phone layout: tapping a result opens that page on its own, scrolled to it.
    testWidgets('on a phone, a search result opens its page at that setting', (tester) async {
      await pump(tester, const SettingsScreen(), size: const Size(400, 900));
      await tester.enterText(find.byKey(const ValueKey('settings-search')), 'moon');
      await tester.pump();
      await tester.tap(find.text('Show sleep timer button'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Sleep timer'), findsOneWidget);
      expect(find.byKey(const ValueKey('setting:sleep-button')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2)); // let the highlight fade
    });

    // 1200 px wide = two-pane layout: the page opens next to the list, so there's no Back button.
    testWidgets('on a wide window, a search result shows beside the list', (tester) async {
      await pump(tester, const SettingsScreen(), size: const Size(1200, 900));
      await tester.enterText(find.byKey(const ValueKey('settings-search')), 'lyrics');
      await tester.pump();
      await tester.tap(find.text('Find lyrics online').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('setting:online-lyrics')), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });

    // e.g. a "Set up book folders" link elsewhere in the app uses AppNav.openSettings.
    testWidgets('other screens can open a particular page', (tester) async {
      await pump(tester, const SettingsScreen(), size: const Size(1200, 900));
      nav.openSettings('audiobooks', setting: 'book-folders');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('setting:book-folders')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
