// 0.1.74: the Audiobooks tab has sub-tabs like Your Library and Videos: Series · All ·
// In progress · Not started · Finished · Favourites. Each tab has its own filter bar (title box,
// Filter, Sort), All / Favourites chips with counts, and remembers its own choices.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/book.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/book_index.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/selection_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/books_screen.dart';
import 'package:provider/provider.dart';

Book book(String title, {String? series, double? index, String author = 'A. Writer'}) => Book(
      id: 'book:$title',
      title: title,
      author: author,
      series: series,
      seriesIndex: index,
      parts: [
        Track(
          id: 'local:/b/$title.m4b',
          source: TrackSource.local,
          title: title,
          artist: author,
          album: title,
          albumArtist: author,
          duration: const Duration(hours: 1),
        ),
      ],
    );

void main() {
  group('sortSeries', () {
    final one = book('Lantern Road', series: 'Lantern Saga', index: 1);
    final two = book('Salt Harbour', series: 'Lantern Saga', index: 2);
    final solo = book('Quiet Engines');
    final other = book('Brass Morning', series: 'Clockwork', index: 1, author: 'Z. Writer');
    List<String?> heads(List<(String?, List<Book>)> g) => [for (final (h, _) in g) h];

    test('a heading per series, books in their order, Not in a series last', () {
      final g = sortSeries([solo, two, other, one], SeriesSort.name);
      expect(heads(g), ['Clockwork', 'Lantern Saga', noSeries]);
      expect(g[1].$2, [one, two]);
    });
    test('the other way round keeps the reading order and Not in a series last', () {
      final g = sortSeries([solo, two, other, one], SeriesSort.name, reverse: true);
      expect(heads(g), ['Lantern Saga', 'Clockwork', noSeries]);
      expect(g.first.$2, [one, two]);
    });
    test('most books, then by name', () {
      expect(heads(sortSeries([other, one, two], SeriesSort.mostBooks)), ['Lantern Saga', 'Clockwork']);
    });
  });

  group('On screen', () {
    late Directory dir;
    late Storage storage;
    late LibraryModel lib;
    late ListeningModel listening;
    late PlaylistsModel playlists;
    late AppNav nav;
    // Invented books: two in a series (one part-way through, and a favourite), one finished,
    // one not started and not in a series.
    final started = book('Lantern Road', series: 'Lantern Saga', index: 1);
    final finished = book('Salt Harbour', series: 'Lantern Saga', index: 2);
    final fresh = book('Quiet Engines');

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('hometunes_books_tabs');
      storage = Storage.at(dir);
      lib = LibraryModel(storage)..books = [started, finished, fresh];
      listening = ListeningModel(storage)..now = () => 1000;
      await listening.record(started, started.parts.first.id, const Duration(minutes: 5));
      await listening.setFinished(finished, true);
      playlists = PlaylistsModel(storage)..setFavouriteBooks([started], true);
      nav = AppNav();
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: listening),
          ChangeNotifierProvider.value(value: playlists),
          ChangeNotifierProvider.value(value: nav),
          ChangeNotifierProvider(create: (_) => SelectionModel()),
        ],
        child: const MaterialApp(home: BooksScreen()),
      ));
      await tester.pumpAndSettle();
    }

    /// Which of the three books are on the page now.
    Set<Book> showing() => {
          for (final b in [started, finished, fresh])
            if (find.text(b.title).evaluate().isNotEmpty) b
        };

    Finder tabLabel(String label) =>
        find.descendant(of: find.byKey(const ValueKey('book-tabs')), matching: find.text(label));

    Future<void> openTab(WidgetTester tester, String label) async {
      await tester.tap(tabLabel(label));
      await tester.pumpAndSettle();
    }

    testWidgets('Series first, then the state tabs; each shows its own books', (tester) async {
      await pump(tester);
      final labels = ['Series', 'All', 'In progress', 'Not started', 'Finished', 'Favourites'];
      for (final label in labels) {
        expect(tabLabel(label), findsOneWidget);
      }
      // Series is first and open to start with: a heading per series, Not in a series last.
      final bar = tester.widget<TabBar>(find.byKey(const ValueKey('book-tabs')));
      expect(bar.controller!.index, 0);
      expect(find.byKey(const ValueKey('series-heading:Lantern Saga')), findsOneWidget);
      expect(find.textContaining('2 books'), findsOneWidget);
      expect(find.byKey(const ValueKey('series-heading:$noSeries')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('series-heading:Lantern Saga'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('series-heading:$noSeries'))).dy),
      );
      expect(showing(), {started, finished, fresh});

      await openTab(tester, 'All');
      expect(showing(), {started, finished, fresh});
      await openTab(tester, 'In progress');
      expect(showing(), {started});
      await openTab(tester, 'Not started');
      expect(showing(), {fresh});
      await openTab(tester, 'Finished');
      expect(showing(), {finished});
      await openTab(tester, 'Favourites');
      expect(showing(), {started});
      // No All / Favourites chips on the Favourites tab itself.
      expect(find.byKey(const ValueKey('books-favourites-chip')), findsNothing);
    });

    testWidgets('filter box and Favourites chip, like Your Library; each tab keeps its own', (tester) async {
      await pump(tester);
      await openTab(tester, 'All');
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Favourites (1)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('books-favourites-chip')));
      await tester.pumpAndSettle();
      expect(showing(), {started});
      await tester.tap(find.byKey(const ValueKey('books-all-chip')));
      await tester.pumpAndSettle();

      // The box matches title, author, narrator or series.
      await tester.enterText(find.byKey(const ValueKey('library-title-filter')), 'lantern saga');
      await tester.pumpAndSettle();
      expect(showing(), {started, finished});
      expect(find.text('All (2)'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('library-title-filter')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No books match.'), findsOneWidget);

      // Another tab has its own, empty box.
      await openTab(tester, 'Series');
      expect(showing(), {started, finished, fresh});
      expect(tester.widget<TextField>(find.byKey(const ValueKey('library-title-filter'))).controller!.text, '');

      // Back on All, it's still narrowed; Clear filters puts everything back.
      await openTab(tester, 'All');
      expect(find.text('No books match.'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(showing(), {started, finished, fresh});
    });

    testWidgets('an empty tab says so in plain words', (tester) async {
      playlists.setFavouriteBooks([started], false);
      await pump(tester);
      await openTab(tester, 'Favourites');
      expect(find.byKey(const ValueKey('books-empty-favourites')), findsOneWidget);
      expect(find.textContaining('No favourite books yet'), findsOneWidget);
    });

    testWidgets("the sidebar's Favourite audiobooks opens the Favourites tab", (tester) async {
      await pump(tester);
      nav.openView(AppNav.booksTab, AppNav.favouriteBooksView);
      await tester.pumpAndSettle();
      final bar = tester.widget<TabBar>(find.byKey(const ValueKey('book-tabs')));
      expect(bar.controller!.index, BookTab.favourites.index);
      expect(showing(), {started});
    });
  });
}
