// Phase 2 of the modular refactor (8 Oct 2026): the pieces the music and video sides now share.
// The sleep timers' shared countdown (SleepCountdown) is covered by the timers' own tests
// (listening_controls_test.dart, video_sleep_timer_test.dart), which pass unchanged.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/lyrics_model.dart';
import 'package:hometunes/state/media_folders.dart';
import 'package:hometunes/state/mixed_value.dart';
import 'package:hometunes/state/song_id_follower.dart';
import 'package:path/path.dart' as p;

class _Follower implements SongIdFollower {
  _Follower(this.referencedIds);
  @override
  final Set<String> referencedIds;
  final moves = <Map<String, String>>[];
  final removals = <Set<String>>[];
  @override
  void remapIds(Map<String, String> moved) => moves.add(moved);
  @override
  void removeIds(Set<String> ids) => removals.add(ids);
}

void main() {
  group('Folders (media_folders.dart)', () {
    test('a file\'s type is its extension in lower case', () {
      expect(fileFormatOf(r'C:\Music\Song.FLAC'), 'flac');
      expect(fileFormatOf('/m/a.b/track.m4a'), 'm4a');
      expect(fileFormatOf('/m/noext'), '');
    });

    test('the deepest folder holding a file owns it', () {
      final music = p.join('C:', 'Music');
      final books = p.join(music, 'Books');
      expect(owningFolder(p.join(books, 'Dune', '01.mp3'), [music, books]), books);
      expect(owningFolder(p.join(books, 'Dune', '01.mp3'), [books, music]), books);
      expect(owningFolder(p.join(music, 'a.mp3'), [music, books]), music);
      expect(owningFolder(p.join('D:', 'x.mp3'), [music, books]), isNull);
    });

    test('a folder\'s file types leave out files an inner folder owns', () {
      final music = p.join('C:', 'Music');
      final books = p.join(music, 'Books');
      final paths = [p.join(music, 'b.MP3'), p.join(music, 'a.flac'), p.join(music, 'c.mp3'), p.join(books, 'd.m4b')];
      expect(formatCounts(paths, music, [music, books]), {'flac': 1, 'mp3': 2});
      expect(formatCounts(paths, music, [music, books]).keys, ['flac', 'mp3']); // A–Z
      expect(formatCounts(paths, books, [music, books]), {'m4b': 1});
    });

    test('offline folders: unreachable ones, except those inside a reachable one', () async {
      final usb = p.join('E:', 'Music');
      final music = p.join('C:', 'Music');
      final gone = p.join(music, 'Deleted');
      final r = await checkFolders([music, usb, gone], (f) async => f == music);
      expect(r.reachable, [music]);
      expect(r.offline, [usb]); // the deleted folder's drive is there, so it has really gone
    });

    test('a folder that exists can be listed; a missing one can\'t', () async {
      final dir = Directory.systemTemp.createTempSync('hometunes_folders');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(await canListFolder(dir.path), isTrue);
      expect(await canListFolder(p.join(dir.path, 'nope')), isFalse);
    });

    test('LibraryModel.formatOf (used by Folder options) is the shared rule', () {
      expect(LibraryModel.formatOf(r'C:\Music\Song.FLAC'), fileFormatOf(r'C:\Music\Song.FLAC'));
    });
  });

  group('Editing several items (mixed_value.dart)', () {
    test('the shared value, or "differ"', () {
      expect(sharedValue(['Rock', 'Rock']), (differ: false, value: 'Rock'));
      expect(sharedValue(['Rock', 'Pop']), (differ: true, value: null));
      expect(sharedValue(<String?>[null, null]), (differ: false, value: null));
      expect(sharedValue(<String?>['Rock', null]), (differ: true, value: null));
      expect(sharedValue(<String>[]), (differ: false, value: null));
    });

    test('the marker is --:--', () => expect(differentMarker, '--:--'));
  });

  group('Song id followers (song_id_follower.dart)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_followers'));
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      dir.deleteSync(recursive: true);
    });

    test('each follower is asked, told about moves and told about forgotten songs', () {
      final library = LibraryModel(Storage.at(dir));
      final a = _Follower({'local:1', 'local:2'});
      final b = _Follower({'local:3'});
      connectSongIdFollowers(library, [a, b]);
      expect(library.otherReferencedIds!(), {'local:1', 'local:2', 'local:3'});
      library.onIdsRemapped!({'local:1': 'local:9'});
      library.onIdsForgotten!({'local:2'});
      for (final f in [a, b]) {
        expect(f.moves, [
          {'local:1': 'local:9'}
        ]);
        expect(f.removals, [
          {'local:2'}
        ]);
      }
    });

    test('lyrics found online don\'t keep a missing song', () {
      final storage = Storage.at(dir);
      final lyrics = LyricsModel(LibraryModel(storage), storage);
      expect(lyrics.referencedIds, isEmpty);
    });
  });
}
