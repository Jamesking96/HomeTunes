// Tests for release 0.1.16 (code review release C): music folders that can't be reached keep
// their songs, failed saves are reported, emptied details can be cleared, the song editor keeps
// audiobook details, the "Audiobooks folder" rule only looks below the scanned folder, lyrics
// follow moved files, a just-imported cover survives other saves, learned song lengths are
// gathered instead of rewriting the library each time, and book places follow moved books.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/book.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/track_edit.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/book_index.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/lyrics_model.dart';
import 'package:path/path.dart' as p;

import 'metadata_features_test.dart' show silentWav;

/// A made-up local file at [path].
Track file(String path, {int? year, String? genre, double? seriesIndex, String? narrator, int minutes = 0}) => Track(
      id: 'local:$path',
      source: TrackSource.local,
      title: p.basenameWithoutExtension(path),
      artist: 'A',
      album: 'Al',
      albumArtist: 'A',
      year: year,
      genre: genre,
      seriesIndex: seriesIndex,
      narrator: narrator,
      duration: Duration(minutes: minutes),
      path: path,
    );

void main() {
  // Importing a cover clears Flutter's image cache, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Storage storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_c');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    Directory(storage.artDir).createSync();
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100)); // background saves
    dir.deleteSync(recursive: true);
  });

  group('A music folder that can\'t be reached', () {
    late LibraryModel lib;
    late Directory music;
    late Directory other;
    var reachable = true;

    setUp(() async {
      music = Directory(p.join(dir.path, 'usb', 'Music', 'Album'))..createSync(recursive: true);
      other = Directory(p.join(dir.path, 'local', 'Album'))..createSync(recursive: true);
      for (final n in ['one', 'two', 'three']) {
        File(p.join(music.path, '$n.wav')).writeAsBytesSync(silentWav());
      }
      File(p.join(other.path, 'here.wav')).writeAsBytesSync(silentWav());
      reachable = true;
      lib = LibraryModel(storage);
      final usb = p.join(dir.path, 'usb', 'Music');
      lib.folderReachable = (f) async => f == usb ? reachable : Directory(f).existsSync();
      lib.folders = [usb, p.join(dir.path, 'local')];
      await lib.scanLocal();
    });

    test('keeps its songs (and their covers) while it\'s away, and says so', () async {
      expect(lib.tracks, hasLength(4));
      reachable = false; // the drive is unplugged
      await lib.scanLocal();
      expect(lib.tracks, hasLength(4));
      expect(lib.missingTracks, isEmpty);
      expect(lib.offlineFolders, [p.join(dir.path, 'usb', 'Music')]);
      expect(lib.error, contains('right now'));
      // Back again: nothing lost, nothing reported.
      reachable = true;
      await lib.scanLocal();
      expect(lib.tracks, hasLength(4));
      expect(lib.offlineFolders, isEmpty);
      expect(lib.error, isNull);
    });

    test('a missing folder inside one that can be reached has really gone', () async {
      // An audiobook folder inside the (reachable) USB music folder is deleted: its drive is
      // clearly there, so its songs are dropped as usual rather than kept as "offline".
      final books = Directory(p.join(dir.path, 'usb', 'Music', 'Books'))..createSync();
      File(p.join(books.path, 'b.wav')).writeAsBytesSync(silentWav());
      await lib.addAudiobookFolder(books.path);
      expect(lib.books, isNotEmpty);
      books.deleteSync(recursive: true);
      await lib.scanLocal();
      expect(lib.books, isEmpty);
      expect(lib.offlineFolders, isEmpty);
    });

    test('removing an offline folder drops its songs', () async {
      reachable = false;
      await lib.scanLocal();
      await lib.removeFolder(p.join(dir.path, 'usb', 'Music'));
      expect(lib.tracks, hasLength(1));
    });

    test('the real check: a missing folder isn\'t reachable, an existing one is', () async {
      final real = LibraryModel(storage);
      expect(await real.folderReachable(music.path), isTrue);
      expect(await real.folderReachable(p.join(dir.path, 'nope')), isFalse);
    });
  });

  group('Failed saves', () {
    test('are reported once per file and cleared when the file saves again', () async {
      final lib = LibraryModel(storage);
      var notified = 0;
      lib.addListener(() => notified++);
      // A folder where the temp file should go makes the save fail.
      final blocker = Directory(p.join(storage.root.path, 'playlists.json.tmp'))..createSync();
      expect(await storage.write('playlists.json', {'x': 1}), isFalse);
      expect(await storage.write('playlists.json', {'x': 2}), isFalse);
      expect(lib.dataProblem, contains('couldn\'t save your playlists'));
      expect(storage.messages, hasLength(1));
      expect(notified, greaterThan(0));
      blocker.deleteSync();
      expect(await storage.write('playlists.json', {'x': 3}), isTrue);
      expect(lib.dataProblem, isNull);
    });

    test('a restore that can\'t save a file fails instead of reporting success', () async {
      await storage.write('settings.json', {'folders': []});
      final backup = AppBackup.read(await AppBackup.create(storage));
      Directory(p.join(storage.root.path, 'edits.json.tmp')).createSync();
      await expectLater(AppBackup.restore(storage, backup, merge: false), throwsA(isA<FileSystemException>()));
    });
  });

  group('Clearing a detail', () {
    final original = file('/m/a.mp3', year: 1999, genre: 'Rock', seriesIndex: 2);

    test('an emptied year hides the file\'s year, and survives saving and loading', () {
      const e = TrackEdit(cleared: {'year'});
      final shown = e.normalizedAgainst(original).applyTo(original);
      expect(shown.year, isNull);
      expect(shown.genre, 'Rock');
      final again = TrackEdit.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
      expect(again.cleared, {'year'});
      expect(again.applyTo(original).year, isNull);
    });

    test('clearing something the file doesn\'t have leaves no edit', () {
      final bare = file('/m/b.mp3');
      expect(const TrackEdit(cleared: {'year', 'seriesIndex'}).normalizedAgainst(bare).isEmpty, isTrue);
    });

    test('merging: a later value replaces a clear, and a later clear replaces a value', () {
      const cleared = TrackEdit(cleared: {'year'});
      final set = cleared.mergedWith(const TrackEdit(year: 2001));
      expect(set.year, 2001);
      expect(set.cleared, isEmpty);
      final clearedAgain = set.mergedWith(const TrackEdit(cleared: {'year'}));
      expect(clearedAgain.year, isNull);
      expect(clearedAgain.cleared, {'year'});
      // Untouched fields keep their values through a merge.
      expect(const TrackEdit(genre: 'Jazz').mergedWith(cleared).genre, 'Jazz');
    });

    test('unknown names in edits.json are ignored', () {
      final e = TrackEdit.fromJson({
        'cleared': ['year', 'title', 42],
      });
      expect(e.cleared, {'year'});
    });

    test('an album edit can clear the year on every song', () async {
      final lib = LibraryModel(storage);
      final music = Directory(p.join(dir.path, 'music'))..createSync();
      File(p.join(music.path, 'x.wav')).writeAsBytesSync(silentWav());
      lib.folders = [music.path];
      await lib.scanLocal();
      final id = lib.tracks.single.id;
      await lib.editMany([id], const TrackEdit(year: 2001));
      expect(lib.byId(id)!.year, 2001);
      await lib.editMany([id], const TrackEdit(cleared: {'year'}));
      // The file has no year, so clearing just removes the edit.
      expect(lib.byId(id)!.year, isNull);
      expect(lib.isEdited(id), isFalse);
    });
  });

  test('saving a book file in the song editor keeps its narrator and series', () async {
    final lib = LibraryModel(storage);
    final music = Directory(p.join(dir.path, 'books', 'Some Book'))..createSync(recursive: true);
    File(p.join(music.path, 'part.wav')).writeAsBytesSync(silentWav());
    lib.folders = [p.join(dir.path, 'books')];
    await lib.scanLocal();
    final id = lib.byId('local:${p.join(music.path, 'part.wav')}')!.id;
    await lib.editMany([id], const TrackEdit(narrator: 'Ann Reader', series: 'Saga', seriesIndex: 3));
    // The song editor replaces the edit with what's in its boxes (no book fields there).
    await lib.setEdit(id, const TrackEdit(title: 'Renamed'));
    final t = lib.byId(id)!;
    expect(t.title, 'Renamed');
    expect(t.narrator, 'Ann Reader');
    expect(t.series, 'Saga');
    expect(t.seriesIndex, 3);
  });

  group('The "Audiobooks folder" rule', () {
    test('only looks from the scanned folder down', () {
      final rules = BookRules(roots: [r'D:\Audiobooks and more\Music', r'F:\AudioBooks']);
      // A folder called Audiobooks above the music folder doesn't count...
      expect(rules.isBook(file(r'D:\Audiobooks and more\Music\Band\01.mp3')), isFalse);
      // ...but the scanned folder's own name does, and so do folders inside it.
      expect(rules.isBook(file(r'F:\AudioBooks\Dune\01.mp3')), isTrue);
      final music = BookRules(roots: [r'F:\Music']);
      expect(music.isBook(file(r'F:\Music\Audio Books\Dune\01.mp3')), isTrue);
      expect(music.isBook(file(r'F:\Music\Band\01.mp3')), isFalse);
    });

    test('checks the whole path when no scanned folder holds the file', () {
      expect(BookRules(roots: [r'F:\Music']).isBook(file(r'G:\Audiobooks\x\01.mp3')), isTrue);
    });
  });

  test('lyrics found online follow a moved file', () async {
    final lib = LibraryModel(storage);
    await storage.write('lyrics.json', {
      'found': {
        'local:/old/a.mp3': {'text': 'la la', 'source': 'lrclib'}
      },
      'none': {'local:/old/b.mp3': 123},
    });
    final lyrics = LyricsModel(lib, storage);
    await lyrics.load();
    lyrics.remapIds({'local:/old/a.mp3': 'local:/new/a.mp3', 'local:/old/b.mp3': 'local:/new/b.mp3'});
    final saved = await storage.read('lyrics.json') as Map<String, dynamic>;
    expect((saved['found'] as Map).keys, ['local:/new/a.mp3']);
    expect((saved['none'] as Map).keys, ['local:/new/b.mp3']);
  });

  test('a cover just imported isn\'t deleted by another save before the editor uses it', () async {
    final lib = LibraryModel(storage);
    final cover = await lib.importCoverBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 9]));
    // Some other edit is saved (this tidies unused covers) before the editor saves its own.
    await lib.setLyrics('local:/m/other.mp3', 'words');
    expect(File(cover).existsSync(), isTrue);
    // (Once an edit uses it, the usual rule applies again: see the backup round trip test in
    // keep_and_backup_test.dart, where a used-then-reset cover is tidied away.)
  });

  test('learned song lengths are gathered, then applied and saved together', () async {
    final lib = LibraryModel(storage);
    final music = Directory(p.join(dir.path, 'music'))..createSync();
    File(p.join(music.path, 'a.wav')).writeAsBytesSync(silentWav());
    File(p.join(music.path, 'b.wav')).writeAsBytesSync(silentWav());
    lib.folders = [music.path];
    await lib.scanLocal();
    final ids = [for (final t in lib.tracks) t.id];
    await lib.learnDuration(ids[0], const Duration(minutes: 3));
    await lib.learnDuration(ids[1], const Duration(minutes: 4));
    // Not applied straight away...
    expect(lib.byId(ids[0])!.duration, isNot(const Duration(minutes: 3)));
    // ...but after a moment, both at once.
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    expect(lib.byId(ids[0])!.duration, const Duration(minutes: 3));
    expect(lib.byId(ids[1])!.duration, const Duration(minutes: 4));
    // Saved when the app goes to the background.
    await lib.flushPendingSaves();
    final saved = await storage.read('library.json') as Map<String, dynamic>;
    final durations = {for (final t in saved['local'] as List) (t as Map)['id']: t['durationMs']};
    expect(durations[ids[1]], const Duration(minutes: 4).inMilliseconds);
  });

  group('Book places', () {
    final book = Book(id: 'book:old', title: 'X', author: 'A', parts: [
      file(r'F:\X\1.mp3', minutes: 30),
      file(r'F:\X\2.mp3', minutes: 30),
    ]);

    test('looking one up never changes or saves anything', () async {
      final l = ListeningModel(storage);
      await l.record(book, book.parts[1].id, const Duration(minutes: 3));
      final moved = Book(id: 'book:new', title: 'X', author: 'A', parts: book.parts);
      final file = File(p.join(storage.root.path, ListeningModel.fileName));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final before = file.readAsStringSync();
      expect(l.progressFor(moved)!.position, const Duration(minutes: 3));
      expect(l.stateOf(moved), BookState.inProgress);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(file.readAsStringSync(), before);
    });

    test('a book with a new id gets its place moved over after a rebuild', () async {
      final l = ListeningModel(storage);
      await l.record(book, book.parts[1].id, const Duration(minutes: 3));
      final moved = Book(id: 'book:new', title: 'X', author: 'A', parts: book.parts);
      expect(l.adoptMoved([moved]), isTrue);
      expect(l.adoptMoved([moved]), isFalse); // nothing left to move
      final saved = await storage.read(ListeningModel.fileName) as Map<String, dynamic>;
      expect((saved['books'] as Map).keys, ['book:new']);
      // Playing it keeps just the one entry.
      await l.record(moved, moved.parts[0].id, Duration.zero);
      expect(l.inProgress([moved]), isEmpty); // back at the very start = not started
    });

    test('recording a place for a moved book before the rebuild leaves one entry', () async {
      final l = ListeningModel(storage);
      await l.record(book, book.parts[1].id, const Duration(minutes: 3));
      final moved = Book(id: 'book:new', title: 'X', author: 'A', parts: book.parts);
      await l.record(moved, moved.parts[1].id, const Duration(minutes: 9));
      final saved = await storage.read(ListeningModel.fileName) as Map<String, dynamic>;
      expect((saved['books'] as Map).keys, ['book:new']);
    });
  });
}
