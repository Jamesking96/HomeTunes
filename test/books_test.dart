import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/book.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/book_index.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:path/path.dart' as p;

import 'metadata_features_test.dart' show silentWav;

const hp = r'F:\AudioBooks\Harry Potter Audio Books 1-7; Read by Stephen Fry [MP3]';

Track file(
  String path, {
  String title = 'T',
  String artist = 'J.K. Rowling',
  String? albumArtist,
  String album = 'Album',
  String? genre = 'Audio Book',
  int? n,
  int minutes = 30,
  List<Chapter> chapters = const [],
}) =>
    Track(
      id: 'local:$path',
      source: TrackSource.local,
      title: title,
      artist: artist,
      album: album,
      albumArtist: albumArtist ?? artist,
      trackNumber: n,
      genre: genre,
      duration: Duration(minutes: minutes),
      path: path,
      chapters: chapters,
    );

void main() {
  group('Which files are audiobooks', () {
    final rules = BookRules(bookFolders: [r'E:\Listen']);

    test('genre, in any spelling', () {
      expect(rules.isBook(file(r'F:\Music\a.mp3', genre: 'Audio Book')), isTrue);
      expect(rules.isBook(file(r'F:\Music\a.mp3', genre: 'audiobooks')), isTrue);
      expect(rules.isBook(file(r'F:\Music\a.mp3', genre: 'Spoken-Word')), isTrue);
      expect(rules.isBook(file(r'F:\Music\a.mp3', genre: 'Rock')), isFalse);
    });

    test('.m4b files, "Audiobooks" folders and chosen audiobook folders', () {
      expect(rules.isBook(file(r'F:\Music\book.m4b', genre: null)), isTrue);
      expect(rules.isBook(file(r'F:\AudioBooks\x\01.mp3', genre: null)), isTrue);
      expect(rules.isBook(file(r'F:\Music\Audio Books\01.mp3', genre: null)), isTrue);
      expect(rules.isBook(file(r'e:\listen\Some Book\01.mp3', genre: null)), isTrue);
      expect(rules.isBook(file(r'F:\Music\Band\01 audiobook.mp3', genre: null)), isFalse); // file name only
      expect(rules.isBook(file(r'F:\Music\Band\01.mp3', genre: null)), isFalse);
    });

    test('Move to Books / Move to Music win over the rules', () {
      final r = BookRules(overrides: {'local:F:\\Music\\a.mp3': true, 'local:F:\\Music\\b.m4b': false});
      expect(r.isBook(file(r'F:\Music\a.mp3', genre: 'Rock')), isTrue);
      expect(r.isBook(file(r'F:\Music\b.m4b', genre: null)), isFalse);
    });
  });

  group('Grouping into books', () {
    test('your Harry Potter layout: one book per folder, with series and narrator', () {
      final dir1 = "$hp\\Book 01 - Harry Potter and the Philosopher's Stone";
      final dir7 = '$hp\\Book 07 - Harry Potter and the Deathly Hallows';
      final books = groupBooks([
        file('$dir1\\Chapter 02 - The Vanishing Glass.mp3', title: 'Chapter 02', album: 'Harry Potter and the Philosophers Stone', n: 2),
        file('$dir1\\Chapter 01 - The Boy Who Lived.mp3', title: 'Chapter 01', album: 'Harry Potter and the Philosophers Stone', n: 1),
        file('$dir7\\Chapter 01 - The Dark Lord Ascending.mp3', album: 'Harry Potter and the Deathly Hallows', n: 1),
      ]);
      expect(books.length, 2);
      expect(books.first.title, 'Harry Potter and the Deathly Hallows'); // sorted by title
      expect(books.first.seriesIndex, 7);
      final stone = books.firstWhere((x) => x.title.contains('Stone'));
      expect(stone.author, 'J.K. Rowling');
      expect(stone.series, 'Harry Potter');
      expect(stone.seriesIndex, 1);
      expect(stone.seriesLabel, 'Harry Potter 1');
      expect(stone.narrator, 'Stephen Fry');
      expect([for (final t in stone.parts) t.title], ['Chapter 01', 'Chapter 02']);
      expect(stone.duration, const Duration(hours: 1));
    });

    test('each .m4b is its own book; MP3 books sharing a folder stay apart', () {
      final books = groupBooks([
        file(r'F:\Books\One.m4b', album: 'Same'),
        file(r'F:\Books\Two.m4b', album: 'Same'),
        file(r'F:\Books\a1.mp3', album: 'Alpha', n: 1),
        file(r'F:\Books\b1.mp3', album: 'Beta', n: 1),
        file(r'F:\Books\a2.mp3', album: 'Alpha', n: 2),
      ]);
      expect(books.length, 4);
      expect(books.firstWhere((b) => b.title == 'Alpha').parts.length, 2);
    });

    test('one differently-spelled author doesn\'t split a book', () {
      final books = groupBooks([
        file(r'F:\HP6\29.mp3', album: 'Half Blood Prince', n: 29),
        file(r'F:\HP6\30.mp3', album: 'Half Blood Prince', artist: 'J. K. Rowling', n: 30),
        file(r'F:\HP6\01.mp3', album: 'Half Blood Prince', n: 1),
      ]);
      expect(books.single.parts.length, 3);
      expect(books.single.author, 'J.K. Rowling');
    });

    test('parts without track numbers sort naturally', () {
      final books = groupBooks([
        file(r'F:\B\Part 10.mp3'),
        file(r'F:\B\Part 2.mp3'),
        file(r'F:\B\Part 1.mp3'),
      ]);
      expect([for (final t in books.single.parts) t.path!.split('\\').last], ['Part 1.mp3', 'Part 2.mp3', 'Part 10.mp3']);
    });

    test('a book with no album tag takes its folder name, minus "Book 03 - "', () {
      final b = groupBooks([file(r'F:\The Expanse Series\Book 03 - The Third\01.mp3', album: 'Book 03 - The Third')]).single;
      expect(b.title, 'The Third');
      expect(b.series, 'The Expanse');
      expect(b.seriesIndex, 3);
    });

    test('series names from folder names', () {
      expect(seriesFromFolder('Harry Potter Audio Books 1-7; Read by Stephen Fry [MP3]'), 'Harry Potter');
      expect(seriesFromFolder('The Lord of the Rings Complete Audiobook Collection'), 'The Lord of the Rings');
      expect(seriesFromFolder('AudioBooks'), isNull);
    });

    test('chapters: markers inside files, otherwise one per file', () {
      final b = Book(id: 'b', title: 'T', author: 'A', parts: [
        file(r'F:\B\1.mp3', title: 'Opening', minutes: 10),
        file(r'F:\B\2.m4b', minutes: 60, chapters: const [
          Chapter(Duration.zero, 'Two'),
          Chapter(Duration(minutes: 20), 'Three'),
        ]),
      ]);
      final ch = b.chapters;
      expect([for (final c in ch) c.title], ['Opening', 'Two', 'Three']);
      expect(ch[2].part, 1);
      expect(ch[2].start, const Duration(minutes: 20));
      expect(ch[2].offset, const Duration(minutes: 30));
      expect(b.offsetOf(1, const Duration(minutes: 5)), const Duration(minutes: 15));
    });
  });

  group('Remembering the place in a book', () {
    late Directory dir;
    late ListeningModel l;
    late Book book;
    var clock = 1000;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('hometunes_listen');
      l = ListeningModel(Storage.at(dir))..now = () => clock;
      await l.load();
      book = Book(id: 'book:x', title: 'X', author: 'A', parts: [
        file(r'F:\X\1.mp3', minutes: 30),
        file(r'F:\X\2.mp3', minutes: 30),
      ]);
    });
    tearDown(() async {
      // Let saves that were started in the background finish first.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      dir.deleteSync(recursive: true);
    });

    test('progress, time left and state', () async {
      expect(l.stateOf(book), BookState.notStarted);
      await l.record(book, book.parts[1].id, const Duration(minutes: 15));
      expect(l.stateOf(book), BookState.inProgress);
      expect(l.fractionDone(book), closeTo(0.75, 0.001));
      expect(l.timeLeft(book), const Duration(minutes: 15));
      await l.setFinished(book, true);
      expect(l.stateOf(book), BookState.finished);
      expect(l.inProgress([book]), isEmpty);
    });

    test('saved to disk and read back', () async {
      await l.record(book, book.parts[0].id, const Duration(minutes: 7));
      final again = ListeningModel(Storage.at(dir));
      await again.load();
      expect(again.progressFor(book)!.position, const Duration(minutes: 7));
    });

    test('a book that moved (new id) keeps its place through its files', () async {
      await l.record(book, book.parts[1].id, const Duration(minutes: 3));
      l.remapIds({book.parts[1].id: 'local:G:\\X\\2.mp3'});
      final moved = Book(id: 'book:moved', title: 'X', author: 'A', parts: [
        file(r'G:\X\1.mp3', minutes: 30),
        file(r'G:\X\2.mp3', minutes: 30),
      ]);
      expect(l.progressFor(moved)!.position, const Duration(minutes: 3));
      expect(l.stateOf(moved), BookState.inProgress);
    });

    test('rewind on resume grows with the break', () {
      expect(PlayerModel.resumeRewind(const Duration(seconds: 20)), const Duration(seconds: 2));
      expect(PlayerModel.resumeRewind(const Duration(minutes: 20)), const Duration(seconds: 10));
      expect(PlayerModel.resumeRewind(const Duration(days: 2)), const Duration(seconds: 30));
    });

    test('backup merge keeps the most recent place per book', () {
      final merged = AppBackup.mergeListening(
        {
          'a': {'part': 'p1', 'posMs': 1, 'updated': 10},
          'b': {'part': 'p2', 'posMs': 2, 'updated': 50},
        },
        {
          'a': {'part': 'p1', 'posMs': 9, 'updated': 20},
          'b': {'part': 'p2', 'posMs': 8, 'updated': 40},
          'c': {'part': 'p3', 'posMs': 3, 'updated': 1},
        },
      );
      expect((merged['a'] as Map)['posMs'], 9);
      expect((merged['b'] as Map)['posMs'], 2);
      expect(merged.containsKey('c'), isTrue);
    });
  });

  group('Library with an audiobook folder', () {
    late Directory dir;
    late LibraryModel lib;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      dir = Directory.systemTemp.createTempSync('hometunes_books');
      final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      Directory(storage.artDir).createSync();
      final music = Directory(p.join(dir.path, 'music'))..createSync();
      File(p.join(music.path, 'song.wav')).writeAsBytesSync(silentWav());
      final books = Directory(p.join(dir.path, 'listen', 'Book 01 - A Story'))..createSync(recursive: true);
      File(p.join(books.path, '01.wav')).writeAsBytesSync(silentWav());
      File(p.join(books.path, '02.wav')).writeAsBytesSync(silentWav());
      lib = LibraryModel(storage);
      await lib.addFolder(music.path);
      await lib.addAudiobookFolder(p.join(dir.path, 'listen'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('books are kept out of the music', () {
      expect(lib.tracks.length, 1);
      expect(lib.books.length, 1);
      expect(lib.books.single.parts.length, 2);
      expect(lib.books.single.title, 'A Story');
      expect(lib.albums.length, 1);
    });

    test('Move to Books and back', () async {
      final song = lib.tracks.single;
      await lib.setIsBook([song.id], true);
      expect(lib.tracks, isEmpty);
      expect(lib.books.length, 2);
      await lib.setIsBook([song.id], null);
      expect(lib.tracks.length, 1);
      final bookFiles = [for (final t in lib.books.single.parts) t.id];
      await lib.setIsBook(bookFiles, false);
      expect(lib.books, isEmpty);
      expect(lib.tracks.length, 3);
    });
  });
}
