// Safety nets for the modular refactor (Phase 0 of the "HomeTunes Modular Refactor Plan", 8 Oct
// 2026). They pin down what the app saves today, so moving code around can't quietly change the
// data files or backups people already have:
// - settings.json: loading a file with every setting changed and saving it again gives back the
//   same file, the fixture really does change every setting, and a file from an older version
//   loads to the same values as before.
// - Backups: a backup holding every data file, restored ("replace") into an empty app folder,
//   gives back the same files and cover images, with app paths moved to the new folder.
// If one of these fails after a refactor, the refactor changed saved data: fix the code, not the
// test. If a new setting is added on purpose, add it to test/fixtures/settings_full.json.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:path/path.dart' as p;

Map<String, dynamic> readJson(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_refactor'));
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100)); // saves finish in the background
    dir.deleteSync(recursive: true);
  });

  // Loads [settings] (or nothing) into a fresh LibraryModel, saves it unchanged, and returns
  // what was written.
  Future<(LibraryModel, Map<String, dynamic>)> loadAndSave(Map<String, dynamic>? settings, String name) async {
    final data = Directory(p.join(dir.path, name))..createSync();
    if (settings != null) File(p.join(data.path, 'settings.json')).writeAsStringSync(jsonEncode(settings));
    final lib = LibraryModel(Storage.at(data));
    await lib.load();
    await lib.setArtistsGrid(lib.artistsGrid); // saves settings.json without changing anything
    return (lib, readJson(p.join(data.path, 'settings.json')));
  }

  group('settings.json', () {
    final full = readJson('test/fixtures/settings_full.json');

    test('a file with every setting changed is saved back exactly as it was', () async {
      final (_, saved) = await loadAndSave(full, 'full');
      expect(saved, equals(full));
    });

    test('the fixture changes every setting and leaves none out', () async {
      final (_, defaults) = await loadAndSave(null, 'defaults');
      for (final key in defaults.keys) {
        expect(full.containsKey(key), isTrue, reason: '"$key" is missing from settings_full.json');
        expect(full[key], isNot(equals(defaults[key])), reason: '"$key" has its default value in settings_full.json');
      }
    });

    test('a file from an older version loads to the same values as before', () async {
      // The shape of settings.json around 0.1.20, with the server password still in it.
      final old = {
        'folders': ['C:/Music'],
        'server': {'url': 'http://192.168.1.20:4533', 'username': 'james', 'password': 'secret'},
        'serverEnabled': true,
        'onlineCovers': false,
        'onlineDetails': true,
        'onlineLyrics': false,
        'serverBooks': true,
        'gaplessPlayback': false,
        'replayGain': 'track',
        'audiobookFolders': ['C:/Books'],
        'bookGenres': ['Audiobook'],
        'skipBackSeconds': 20,
        'skipForwardSeconds': 60,
        'rewindOnResume': false,
        'defaultBookSpeed': 1.1,
        'sleepBookMinutes': 0,
        'sleepMusicMinutes': 15,
        'sleepFadeSeconds': 5,
        'bookOverrides': {'local:C:/Music/talk.mp3': true},
      };
      final (_, defaults) = await loadAndSave(null, 'defaults');
      final (lib, saved) = await loadAndSave(old, 'old');
      expect(saved, equals({
        ...defaults,
        ...old,
        'server': {'url': 'http://192.168.1.20:4533', 'username': 'james'}, // the password moved out
      }));
      expect(lib.server.password, 'secret'); // into protected storage
    });
  });

  group('Backups', () {
    // Every app path inside [from] becomes the same path inside [to].
    Object? moveRoot(Object? j, String from, String to) => switch (j) {
          String s => s.startsWith(from) ? to + s.substring(from.length) : s,
          List l => [for (final x in l) moveRoot(x, from, to)],
          Map m => {for (final e in m.entries) moveRoot(e.key, from, to): moveRoot(e.value, from, to)},
          _ => j,
        };

    test('replace: every data file and cover comes back the same in a new app folder', () async {
      final music = Directory(p.join(dir.path, 'music'))..createSync();
      final books = Directory(p.join(dir.path, 'books'))..createSync();
      final videos = Directory(p.join(dir.path, 'videos'))..createSync();
      final a = Storage.at(Directory(p.join(dir.path, 'a'))..createSync());
      final b = Storage.at(Directory(p.join(dir.path, 'b'))..createSync());
      final rootA = a.root.path, rootB = b.root.path;
      final custom = p.join(a.artDir, 'custom', 'cover.jpg');
      final cached = p.join(a.artDir, 'ab12cd.jpg');
      File(custom)
        ..createSync(recursive: true)
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      File(cached).writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 4, 5, 6]);
      File(p.join(a.artDir, 'server', 'skip.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);
      final song = 'local:${p.join(music.path, 'a.mp3')}';

      final settings = {
        ...readJson('test/fixtures/settings_full.json'),
        'folders': [music.path],
        'audiobookFolders': [books.path],
        'videoFolders': [videos.path],
        'hiddenFormats': {music.path: ['wav']},
        // A chosen artist picture lives in art/custom (one elsewhere is dropped on restore, 0.1.21).
        'artistPictures': {'Muse': 'album:muse|absolution', 'Air': custom},
      };
      final files = <String, Map<String, dynamic>>{
        'settings.json': settings,
        'edits.json': {
          song: {'title': 'Edited', 'art': custom},
        },
        'playlists.json': {
          'playlists': [
            {'id': 'p1', 'name': 'Road trip', 'trackIds': [song]},
          ],
          'liked': [song],
          'favouriteAlbums': [song],
          'favouriteBooks': <String>[],
          'favouriteSeries': ['Discworld'],
        },
        'library.json': {
          'local': [
            {'id': song, 'source': 'local', 'title': 'A', 'artist': 'X', 'album': 'Y', 'albumArtist': 'X', 'path': p.join(music.path, 'a.mp3'), 'durationMs': 1000, 'art': cached},
          ],
          'remote': <Object>[],
          'missing': <Object>[],
        },
        'listening.json': {
          'books': {'book:1': {'part': 1, 'positionMs': 5000, 'finished': false, 'speed': 1.2, 'updatedMs': 1}},
        },
        'bookmarks.json': {
          'bookmarks': [
            {'id': 'bm1', 'bookId': 'book:1', 'part': 0, 'positionMs': 1000, 'note': 'Good bit'},
          ],
        },
        'lyrics.json': {
          'found': {song: {'synced': '[00:01.00]La'}},
          'none': {'local:x': 1},
        },
        'equalizer.json': {
          'on': true,
          'music': 'rock',
          'custom': [
            {'id': 'mine', 'name': 'Mine', 'gains': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 'level': -2.0},
          ],
        },
        'videos.json': {
          'videos': <Object>[],
          'edits': {'v1': {'title': 'Pilot'}},
          'places': {'v1': {'positionMs': 1000, 'lengthMs': 2000, 'watched': false, 'updatedMs': 5}},
          'favourites': ['silo'],
        },
        'history.json': {
          'played': [
            {'kind': 'album', 'key': 'x|y', 'title': 'Y', 'at': 100},
          ],
        },
        'servers.json': {
          'servers': [
            {'id': 's1', 'type': 'jellyfin', 'name': 'Den', 'url': 'http://den:8096', 'username': 'james', 'use': ['videos']},
          ],
        },
      };
      expect(files.keys.toSet(), AppBackup.dataFiles.toSet(), reason: 'a data file was added: add it here too');
      for (final e in files.entries) {
        await a.write(e.key, e.value);
      }

      final backup = AppBackup.read(await AppBackup.create(a));
      await AppBackup.restore(b, backup, merge: false);

      for (final name in AppBackup.dataFiles) {
        expect(await b.read(name), equals(moveRoot(files[name], rootA, rootB)), reason: name);
      }
      final custom2 = p.join(b.artDir, 'custom', 'cover.jpg');
      expect(File(custom2).readAsBytesSync(), File(custom).readAsBytesSync());
      expect(File(p.join(b.artDir, 'ab12cd.jpg')).readAsBytesSync(), File(cached).readAsBytesSync());
      expect(File(p.join(b.artDir, 'server', 'skip.jpg')).existsSync(), isFalse);
    });
  });
}
