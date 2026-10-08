// 0.1.75: audiobook series (the user: "allow for the favouriting and adding audiobook series to
// be connected to the sidebar"): a page per series, favourite series (saved, and kept by
// backups), and a series as a quick link in the sidebar.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/quick_link.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/book_index.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/series_screen.dart';
import 'package:provider/provider.dart';

import 'books_tabs_test.dart' show book;

void main() {
  late Directory dir;
  late Storage storage;
  setUp(() => storage = Storage.at(dir = Directory.systemTemp.createTempSync('hometunes_series')));
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // Invented books, numbered out of order on purpose.
  final two = book('Salt Harbour', series: 'Lantern Saga', index: 2);
  final one = book('Lantern Road', series: 'Lantern Saga', index: 1);
  final half = book('Between Tides', series: 'Lantern Saga', index: 1.5, author: 'B. Other');
  final solo = book('Quiet Engines');

  test('a series: its books in order, its authors, its cover', () {
    final s = seriesNamed([two, solo, half, one], 'Lantern Saga')!;
    expect(s.books, [one, half, two]);
    expect(s.authors, ['A. Writer', 'B. Other']);
    expect(seriesNamed([solo], 'Lantern Saga'), isNull);
    expect(SeriesScreen.numberOf(half), 'Book 1.5');
    expect(SeriesScreen.numberOf(solo), isNull);
  });

  test('favourite series are saved, and a backup keeps them', () async {
    final p = PlaylistsModel(storage)..setFavouriteSeries(['Lantern Saga'], true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final again = PlaylistsModel(storage);
    await again.load();
    expect(again.isFavouriteSeries('Lantern Saga'), isTrue);
    again.renameFavouriteSeries('Lantern Saga', 'The Lantern Saga');
    expect(again.favouriteSeries, {'The Lantern Saga'});
    p.setFavouriteSeries(['Lantern Saga'], false);

    final merged = AppBackup.mergePlaylists(
      {'favouriteSeries': ['A']},
      {'favouriteSeries': ['A', 'B']},
    );
    expect(merged['favouriteSeries'], ['A', 'B']);
  });

  test('a series quick link survives being saved', () {
    const link = QuickLink(QuickLinkKind.series, 'Lantern Saga', 'Lantern Saga');
    final back = QuickLink.fromJson(link.toJson())!;
    expect(back.kind, QuickLinkKind.series);
    expect(back.kindName, 'Series');
  });

  group('the series page', () {
    late LibraryModel lib;
    late ListeningModel listening;
    late PlaylistsModel playlists;

    Future<void> pump(WidgetTester tester, String name) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      lib = LibraryModel(storage)..books = [two, solo, one];
      listening = ListeningModel(storage)..now = () => 1000;
      playlists = PlaylistsModel(storage);
      await tester.runAsync(() => listening.record(one, one.parts.first.id, const Duration(minutes: 5)));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: listening),
          ChangeNotifierProvider.value(value: playlists),
          ChangeNotifierProvider(create: (_) => AppNav()),
          ChangeNotifierProvider(create: (_) => SelectionModel()),
        ],
        child: MaterialApp(home: SeriesScreen(name: name)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('books in order, Continue the one in progress, heart and sidebar', (tester) async {
      await pump(tester, 'Lantern Saga');
      expect(find.text('Lantern Saga'), findsWidgets);
      expect(find.text('2 books'), findsWidgets);
      expect(find.text('Continue Lantern Road'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(ValueKey('series-book:${one.id}'))).dy,
        lessThan(tester.getTopLeft(find.byKey(ValueKey('series-book:${two.id}'))).dy),
      );
      expect(find.text('Book 1 · 55 min left'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('series-favourite')));
      await tester.pump();
      expect(playlists.isFavouriteSeries('Lantern Saga'), isTrue);
      await tester.tap(find.byKey(const ValueKey('quick-link-button')));
      await tester.pump();
      expect(lib.isQuickLink(QuickLinkKind.series, 'Lantern Saga'), isTrue);
    });

    testWidgets('Mark all as finished', (tester) async {
      await pump(tester, 'Lantern Saga');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('series-mark-all')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(listening.stateOf(one), BookState.finished);
      expect(listening.stateOf(two), BookState.finished);
      expect(find.text('2 books · all finished'), findsOneWidget);
      expect(find.text('Mark all as not finished'), findsOneWidget);
    });

    testWidgets('a series that has gone says so', (tester) async {
      await pump(tester, 'Nobody\'s Saga');
      expect(find.text('Series not found'), findsOneWidget);
    });
  });
}
