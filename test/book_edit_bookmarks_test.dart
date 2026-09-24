import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/book.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/track_edit.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/book_info.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/tag_writer.dart';
import 'package:hometunes/state/book_index.dart';
import 'package:hometunes/state/bookmarks_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:path/path.dart' as p;

import 'metadata_features_test.dart' show silentWav;

Track part(String path, {int minutes = 10, int? n, String? narrator, String? series, double? seriesIndex}) => Track(
      id: 'local:$path',
      source: TrackSource.local,
      title: p.basenameWithoutExtension(path),
      artist: 'Author',
      album: 'Album',
      albumArtist: 'Author',
      trackNumber: n,
      duration: Duration(minutes: minutes),
      path: path,
      narrator: narrator,
      series: series,
      seriesIndex: seriesIndex,
    );

void main() {
  group('Book details as edits', () {
    test('narrator and series survive JSON, merging and "back to the file"', () {
      const e = TrackEdit(narrator: 'Stephen Fry', series: 'Harry Potter', seriesIndex: 2);
      final again = TrackEdit.fromJson(e.toJson());
      expect(again.narrator, 'Stephen Fry');
      expect(again.seriesIndex, 2);
      expect(const TrackEdit(title: 'X').mergedWith(e).series, 'Harry Potter');
      final t = part(r'F:\B\1.mp3');
      expect(e.applyTo(t).narrator, 'Stephen Fry');
      expect(TrackEdit(narrator: t.narrator).normalizedAgainst(t).isEmpty, isTrue);
      expect(Track.fromJson(e.applyTo(t).toJson()).series, 'Harry Potter');
    });

    test('they always stay in HomeTunes when writing tags into files', () {
      final left = TagSupport.forPath('a.mp3').leftover(const TrackEdit(title: 'T', narrator: 'N', series: 'S'));
      expect(left.title, isNull);
      expect(left.narrator, 'N');
      expect(left.series, 'S');
    });

    test('edited details win over folder names; empty clears them', () {
      const dir = r'F:\HP Audio Books 1-7; Read by Stephen Fry\Book 02 - Chamber';
      final fromFolders = groupBooks([part('$dir\\01.mp3')]).single;
      expect(fromFolders.narrator, 'Stephen Fry');
      expect(fromFolders.seriesIndex, 2);

      final edited = groupBooks([
        part('$dir\\01.mp3', narrator: 'Jim Dale', series: 'Harry Potter', seriesIndex: 2.5),
      ]).single;
      expect(edited.narrator, 'Jim Dale');
      expect(edited.series, 'Harry Potter');
      expect(edited.seriesIndex, 2.5);

      final cleared = groupBooks([part('$dir\\01.mp3', narrator: '', series: '')]).single;
      expect(cleared.narrator, isNull);
      expect(cleared.series, isNull);
    });
  });

  group('Editing a book in the library', () {
    late Directory dir;
    late LibraryModel lib;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      dir = Directory.systemTemp.createTempSync('hometunes_editbook');
      final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      Directory(storage.artDir).createSync();
      final book = Directory(p.join(dir.path, 'books', 'A Story'))..createSync(recursive: true);
      File(p.join(book.path, '01.wav')).writeAsBytesSync(silentWav());
      File(p.join(book.path, '02.wav')).writeAsBytesSync(silentWav());
      lib = LibraryModel(storage);
      await lib.addAudiobookFolder(p.join(dir.path, 'books'));
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      dir.deleteSync(recursive: true);
    });

    test('title, author, narrator and cover apply to every file', () async {
      final b = lib.books.single;
      final ids = [for (final t in b.parts) t.id];
      final cover = await lib.importCoverBytes([0xFF, 0xD8, 0xFF, 0xE0, 9, 9]);
      await lib.editMany(
        ids,
        TrackEdit(album: 'The Real Title', artist: 'Real Author', albumArtist: 'Real Author', narrator: 'N', art: cover),
      );
      final now = lib.books.single;
      expect(now.title, 'The Real Title');
      expect(now.author, 'Real Author');
      expect(now.narrator, 'N');
      expect(now.parts.length, 2);
      expect(now.artTrack!.art, cover);
      expect(lib.bookOfTrack(ids.first)!.id, now.id); // how the page follows a renamed book
      expect(lib.searchBooks('real auth').single.id, now.id);

      await lib.resetEdits(ids);
      expect(lib.books.single.title, 'A Story');
    });
  });

  group('Bookmarks', () {
    late Directory dir;
    late BookmarksModel model;
    final book = Book(id: 'b', title: 'B', author: 'A', parts: [
      part(r'F:\B\1.mp3', minutes: 30),
      part(r'F:\B\2.mp3', minutes: 30),
    ]);

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('hometunes_bm');
      model = BookmarksModel(Storage.at(dir));
      await model.load();
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      dir.deleteSync(recursive: true);
    });

    test('added, listed in listening order, noted, deleted and saved', () async {
      final late = await model.add(book.parts[1].id, const Duration(minutes: 5), note: 'Twist!');
      final early = await model.add(book.parts[0].id, const Duration(minutes: 20));
      expect([for (final b in model.forBook(book)) b.id], [early.id, late.id]);
      await model.setNote(early, 'Start of the chase');
      final again = BookmarksModel(Storage.at(dir));
      await again.load();
      final list = again.forBook(book);
      expect(list.first.note, 'Start of the chase');
      expect(list.last.position, const Duration(minutes: 5));
      await model.remove(late);
      expect(model.forBook(book).length, 1);
    });

    test('follow moved files; forgotten files take their bookmarks with them', () async {
      final b = await model.add(book.parts[0].id, const Duration(minutes: 1));
      model.remapIds({book.parts[0].id: 'local:G:\\B\\1.mp3'});
      expect(model.referencedIds, {'local:G:\\B\\1.mp3'});
      model.removeIds({'local:G:\\B\\1.mp3'});
      expect(model.referencedIds, isEmpty);
      expect(b.note, '');
    });
  });

  group('Open Library', () {
    test('search query and results', () {
      final u = BookInfoSearch.buildQuery(title: 'The Hobbit', author: 'Tolkien');
      expect(u.host, 'openlibrary.org');
      expect(u.queryParameters['title'], 'The Hobbit');
      expect(u.queryParameters['author'], 'Tolkien');
      final r = BookInfoSearch.parse({
        'docs': [
          {'key': '/works/1', 'title': 'The Hobbit', 'author_name': ['J.R.R. Tolkien'], 'first_publish_year': 1937, 'cover_i': 42},
          {'key': '/works/1', 'title': 'duplicate'},
          {'key': '/works/2', 'title': 'No cover'},
        ],
      });
      expect(r.length, 2);
      expect(r.first.author, 'J.R.R. Tolkien');
      expect(r.first.year, 1937);
      expect(r.last.coverId, isNull);
      expect(BookInfoSearch.coverUrl(42, large: true).path, '/b/id/42-L.jpg');
    });
  });

  test('backups carry bookmarks, and merging keeps both sets', () async {
    final dir = Directory.systemTemp.createTempSync('hometunes_bmbackup');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = Storage.at(dir);
    await storage.write('bookmarks.json', {
      'bookmarks': [
        {'id': 'a', 'part': 'p', 'posMs': 1, 'created': 1},
      ],
    });
    final backup = AppBackup.read(await AppBackup.create(storage));
    expect(backup.bookmarkCount, 1);
    await storage.write('bookmarks.json', {
      'bookmarks': [
        {'id': 'b', 'part': 'p', 'posMs': 2, 'created': 2},
      ],
    });
    await AppBackup.restore(storage, backup, merge: true);
    final merged = await storage.read('bookmarks.json') as Map;
    expect([for (final b in merged['bookmarks'] as List) (b as Map)['id']], ['b', 'a']);
  });

  group('Search', () {
    final books = [
      _book('The Philosopher\'s Stone', 'J.K. Rowling', ['Chapter 01 - The Boy Who Lived', 'Chapter 05 - Diagon Alley'],
          series: 'Harry Potter'),
      _book('Stone Soup', 'Someone', ['One']),
      _book('The Hobbit', 'J.R.R. Tolkien', ['An Unexpected Party']),
    ];

    test('books by title, author or series; titles starting with the search first', () {
      expect([for (final b in searchBookList(books, 'stone')) b.title], ['Stone Soup', 'The Philosopher\'s Stone']);
      expect(searchBookList(books, 'tolkien').single.title, 'The Hobbit');
      expect(searchBookList(books, 'harry potter').single.title, 'The Philosopher\'s Stone');
      expect(searchBookList(books, '  '), isEmpty);
    });

    test('chapters by name', () {
      final hits = searchChapterList(books, 'diagon');
      expect(hits.single.book.title, 'The Philosopher\'s Stone');
      expect(hits.single.chapter, 1);
      expect(searchChapterList(books, 'boy lived').single.chapter, 0);
      expect(searchChapterList(books, 'dragon'), isEmpty);
    });
  });
}

// ---------------------------------------------------------------- search

Book _book(String title, String author, List<String> chapterTitles, {String? series}) => Book(
      id: 'book:$title',
      title: title,
      author: author,
      series: series,
      parts: [
        for (var i = 0; i < chapterTitles.length; i++)
          Track(
            id: 'local:F:\\$title\\$i.mp3',
            source: TrackSource.local,
            title: chapterTitles[i],
            artist: author,
            album: title,
            albumArtist: author,
            duration: const Duration(minutes: 20),
            path: 'F:\\$title\\$i.mp3',
          ),
      ],
    );
