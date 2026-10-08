// 0.1.76: Edit series (the user: "We might need a method to edit series like how we do with video
// collections"): rename, author, order, add / take out books, description and picture. Saved as
// edits on the books' files, like Edit book.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/book.dart';
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
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'metadata_features_test.dart' show silentWav;

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;

  // Invented books: two in a series folder, one on its own.
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('hometunes_edit_series');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    Directory(storage.artDir).createSync();
    for (final rel in [
      p.join('Lantern Saga', 'Book 01 - Lantern Road'),
      p.join('Lantern Saga', 'Book 02 - Salt Harbour'),
      'Quiet Engines',
    ]) {
      final d = Directory(p.join(dir.path, 'listen', rel))..createSync(recursive: true);
      File(p.join(d.path, '01.wav')).writeAsBytesSync(silentWav());
    }
    lib = LibraryModel(storage);
    await lib.addAudiobookFolder(p.join(dir.path, 'listen'));
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Book named(String word) => lib.books.firstWhere((b) => b.title.contains(word));
  BookSeries saga([String name = 'Lantern Saga']) => seriesNamed(lib.books, name)!;
  List<String> titles(BookSeries s) => [for (final b in s.books) b.title];

  test('the books found: a series of two and one on its own', () {
    expect(titles(saga()), [named('Lantern').title, named('Salt').title]);
    expect(named('Quiet').series, isNull);
  });

  test('rename: every book, and the details, sidebar link come along', () async {
    await lib.setSeriesDescription('Lantern Saga', 'Two books by the sea.');
    await lib.addQuickLink(const QuickLink(QuickLinkKind.series, 'Lantern Saga', 'Lantern Saga'));
    await lib.editSeries(saga(), name: 'The Lantern Saga');
    expect(seriesNamed(lib.books, 'Lantern Saga'), isNull);
    expect(saga('The Lantern Saga').books, hasLength(2));
    expect(lib.seriesDescription('The Lantern Saga'), 'Two books by the sea.');
    expect(lib.isQuickLink(QuickLinkKind.series, 'The Lantern Saga'), isTrue);
    expect(lib.isQuickLink(QuickLinkKind.series, 'Lantern Saga'), isFalse);
  });

  test('order: the books numbered 1, 2… as dragged', () async {
    final s = saga();
    await lib.editSeries(s, order: s.books.reversed.toList());
    expect(titles(saga()), [named('Salt').title, named('Lantern').title]);
    expect(named('Salt').seriesIndex, 1);
    expect(named('Lantern').seriesIndex, 2);
  });

  test('add a book after the last, take one out, and change the author', () async {
    await lib.editSeries(saga(), add: [named('Quiet')], remove: [named('Salt')], author: 'C. Writer');
    expect(titles(saga()), [named('Lantern').title, named('Quiet').title]);
    expect(named('Quiet').seriesIndex, 2); // after the last book left in it
    expect(named('Salt').series, isNull);
    expect(named('Salt').seriesIndex, isNull);
    expect(saga().authors, ['C. Writer']);
    expect(named('Salt').author, isNot('C. Writer'));
  });

  test('picture: one of its books, or a file kept by settings and backups', () async {
    final s = saga();
    await lib.setSeriesPicture(s.name, book: s.books.last);
    expect(lib.seriesCoverBook(saga()).id, s.books.last.id);
    expect(lib.seriesPictureFile(s.name), isNull);

    final copy = await lib.importCoverBytes([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    await lib.setSeriesPicture(s.name, file: copy);
    expect(lib.seriesPictureFile(s.name), copy);
    final again = LibraryModel(storage);
    await again.load();
    expect(again.seriesPictureFile(s.name), copy);

    final cleaned = AppBackup.sanitize('settings.json', {
      'seriesInfo': {
        'Inside': {'picture': copy},
        'Book': {'picture': 'book:abc'},
        'Outside': {'picture': p.join(dir.path, '..', 'secret.jpg'), 'description': 'kept'},
      },
    }, p.join(dir.path, 'data'));
    expect(cleaned['seriesInfo'], {
      'Inside': {'picture': copy},
      'Book': {'picture': 'book:abc'},
      'Outside': {'description': 'kept'},
    });

    await lib.setSeriesPicture(s.name);
    expect(lib.hasSeriesPicture(s.name), isFalse);
  });

  group('on screen', () {
    late PlaylistsModel playlists;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      playlists = PlaylistsModel(storage)..setFavouriteSeries(['Lantern Saga'], true);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: ListeningModel(storage)),
          ChangeNotifierProvider.value(value: playlists),
          ChangeNotifierProvider(create: (_) => AppNav()),
          ChangeNotifierProvider(create: (_) => SelectionModel()),
        ],
        child: const MaterialApp(home: SeriesScreen(name: 'Lantern Saga')),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('series-edit-save')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('Edit series: rename, description; the page and the favourite follow', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('series-edit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('series-edit-name')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('series-edit-name')), 'The Lantern Saga');
      await tester.enterText(find.byKey(const ValueKey('series-edit-description')), 'By the sea.');
      await save(tester);
      expect(find.text('The Lantern Saga'), findsWidgets);
      expect(find.byKey(const ValueKey('series-description')), findsOneWidget);
      expect(find.text('Series not found'), findsNothing);
      expect(playlists.isFavouriteSeries('The Lantern Saga'), isTrue);
      expect(saga('The Lantern Saga').books, hasLength(2));
    });

    testWidgets('Edit series: take one out and add another', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('series-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('series-edit-remove:${named('Salt').id}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Taking out:'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('series-edit-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('series-add-book:${named('Quiet').id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('series-add-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Adding · ${named('Quiet').author}'), findsOneWidget);
      await save(tester);
      expect(titles(saga()), [named('Lantern').title, named('Quiet').title]);
      expect(named('Salt').series, isNull);
    });

    testWidgets('the menu has Edit series and Change picture', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('series-menu-edit')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('series-menu-picture')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('series-picture-book')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('series-picture-book')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(ValueKey('series-cover-pick:${named('Salt').id}')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(lib.seriesCoverBook(saga()).id, named('Salt').id);
    });
  });
}
