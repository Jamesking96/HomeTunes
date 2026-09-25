// The Details page's "where does this come from?" logic (services/media_details.dart): for
// each detail, is it from the file's tags, a book details file, the folder or file name, or
// the user's own edit? Also "why is this in Books?".

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/track_edit.dart';
import 'package:hometunes/services/book_sidecar.dart';
import 'package:hometunes/services/local_scanner.dart';
import 'package:hometunes/services/media_details.dart';
import 'package:hometunes/state/book_index.dart';
import 'package:path/path.dart' as p;

import 'metadata_features_test.dart' show silentWav;

void main() {
  late Directory dir;
  late String artDir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_details');
    artDir = Directory(p.join(dir.path, 'art')).path;
    Directory(artDir).createSync();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Track scan(String path) => readTrack(path, 0, artDir, sidecars: findSidecars(path, FolderCache()));
  DetailRow row(FileDetails d, String label) => d.rows.firstWhere((r) => r.label == label);

  test('tagged file: details come from its tags, and an edit shows what the file says', () {
    final path = p.join(dir.path, 'song.mp3');
    File('test/fixtures/tagged.mp3').copySync(path);
    final scanned = scan(path);
    final shown = const TrackEdit(title: 'My Title').applyTo(scanned);
    final d = inspectTrackNow(shown: shown, scanned: scanned, artDir: artDir);

    expect(d.exists, isTrue);
    expect(d.format, 'MP3');
    expect(d.fileName, 'song.mp3');
    expect(d.folder, dir.path);
    expect(row(d, 'Artist').source, DetailSource.tags);
    expect(row(d, 'Artist').shown, scanned.artist);
    expect(row(d, 'Title').source, DetailSource.edit);
    expect(row(d, 'Title').shown, 'My Title');
    expect(row(d, 'Title').inFile, scanned.title);
    expect(d.inFile.any((e) => e.$1 == 'Artist' && e.$2 == scanned.artist), isTrue);
  });

  test('untagged file: album from the folder name, title and number from the file name', () {
    final folder = Directory(p.join(dir.path, 'Road Trip'))..createSync();
    final path = p.join(folder.path, '03 - Open Road.wav');
    File(path).writeAsBytesSync(silentWav());
    final scanned = scan(path);
    final d = inspectTrackNow(shown: scanned, scanned: scanned, artDir: artDir);

    expect(row(d, 'Album').shown, 'Road Trip');
    expect(row(d, 'Album').source, DetailSource.folderName);
    expect(row(d, 'Title').shown, 'Open Road');
    expect(row(d, 'Title').source, DetailSource.fileName);
    expect(row(d, 'Track number').source, DetailSource.fileName);
    expect(row(d, 'Artist').source, DetailSource.standIn);
    expect(row(d, 'Genre').source, DetailSource.notSet);
    expect(row(d, 'Cover').source, DetailSource.notSet);
  });

  test('audiobook with a details file and a picture beside it', () {
    final folder = Directory(p.join(dir.path, 'Kettle'))..createSync();
    final path = p.join(folder.path, 'The Last Kettle.wav');
    File(path).writeAsBytesSync(silentWav());
    File(p.join(folder.path, 'The Last Kettle.metadata.json')).writeAsStringSync(jsonEncode({
      'title': 'The Last Kettle',
      'authors': [
        {'name': 'Jane Brewer'}
      ],
      'narrators': [
        {'name': 'Peter Pour'}
      ],
      'series': [
        {'sequence': '1', 'title': 'The Tea Saga'}
      ],
      'release_date': '2014-02-27',
    }));
    File(p.join(folder.path, 'The Last Kettle.jpg')).writeAsBytesSync([0xFF, 0xD8, 0xFF]);
    final scanned = scan(path);
    final d = inspectTrackNow(shown: scanned, scanned: scanned, artDir: artDir);

    for (final label in ['Artist', 'Album', 'Narrator', 'Series', 'Number in series', 'Year']) {
      expect(row(d, label).source, DetailSource.bookFile, reason: label);
      expect(row(d, label).from, 'The Last Kettle.metadata.json', reason: label);
    }
    expect(row(d, 'Cover').source, DetailSource.picture);
    expect(row(d, 'Cover').from, 'The Last Kettle.jpg');
    expect(d.besideIt.map((e) => e.$2), containsAll(['Book details', 'Cover picture']));

    final (isBook, why) = BookRules().why(scanned);
    expect(isBook, isTrue);
    expect(why, contains('book details file'));
  });

  test('why something is or isn\'t a book', () {
    Track t(String path, {String? genre}) => Track(
        id: 'local:$path', source: TrackSource.local, title: 't', artist: 'a', album: 'b', albumArtist: 'a',
        genre: genre, path: path);
    final rules = BookRules(bookFolders: ['/listen'], overrides: {'local:/m/x.mp3': true});
    expect(rules.why(t('/m/x.mp3')), (true, 'You moved it to Books'));
    expect(rules.why(t('/m/y.mp3', genre: 'Audiobook')).$2, contains('genre'));
    expect(rules.why(t('/m/z.m4b')).$2, contains('.m4b'));
    expect(rules.why(t('/Audio Books/z.mp3')).$2, contains('"Audio Books"'));
    expect(rules.why(t('/listen/z.mp3')).$2, contains('/listen'));
    expect(rules.why(t('/m/song.mp3')), (false, 'None of the audiobook rules apply'));
  });

  test('server songs say they come from the server', () {
    const t = Track(
        id: 'server:1', source: TrackSource.server, title: 'Song', artist: 'A', album: 'B', albumArtist: 'A',
        remoteId: '1');
    final d = inspectTrackNow(shown: t, scanned: t, artDir: artDir);
    expect(d.isServer, isTrue);
    expect(row(d, 'Title').source, DetailSource.server);
  });
}
