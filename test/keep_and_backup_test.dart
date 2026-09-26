// Tests for keeping the user's work safe when files come and go, and for backups:
// reading WAV lengths and "unknown length" songs, matching songs that moved or were renamed
// (services/track_matching.dart), keeping edits, likes and playlist places for songs that are
// temporarily missing or have moved (LibraryModel + PlaylistsModel on a real temp folder),
// forgetting missing songs, and backup files (services/app_backup.dart): full round trip,
// portable paths, leaving out the server password, and merging playlists.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/track_edit.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/local_scanner.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/track_matching.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:path/path.dart' as p;

import 'metadata_features_test.dart' show silentWav;

/// A made-up local song at [path]; [ms] is its length (0 = unknown).
Track local(String path, {String title = 'T', String artist = 'A', String album = 'Al', int? n, int ms = 0}) =>
    Track(
      id: 'local:$path',
      source: TrackSource.local,
      title: title,
      artist: artist,
      album: album,
      albumArtist: artist,
      trackNumber: n,
      duration: Duration(milliseconds: ms),
      path: path,
    );

void main() {
  // Saving a cover clears Flutter's image cache, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Song length', () {
    test('WAV length is read from the header', () {
      final dir = Directory.systemTemp.createTempSync('hometunes_len');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File(p.join(dir.path, 'a.wav'))..writeAsBytesSync(silentWav());
      expect(wavDuration(f), const Duration(milliseconds: 100));
      final notWav = File(p.join(dir.path, 'b.wav'))..writeAsBytesSync([1, 2, 3]);
      expect(wavDuration(notWav), isNull);
    });

    test('unknown lengths', () {
      expect(local('/a.mp3').hasDuration, isFalse);
      expect(local('/a.mp3', ms: 1000).hasDuration, isTrue);
      expect(local('/a.mp3').copyWith(duration: const Duration(seconds: 5)).duration, const Duration(seconds: 5));
    });
  });

  group('Finding songs that moved', () {
    // Same "Artist/Album/file" ending on a phone as on a Windows drive counts as the same song;
    // a file that only shares the file name doesn't.
    test('by the end of the path, even on another drive or device', () {
      final gone = [local(r'D:\Music\Radiohead\OK Computer\01 Airbag.mp3')];
      final added = [
        local('/storage/emulated/0/Music/Radiohead/OK Computer/01 Airbag.mp3'),
        local('/storage/emulated/0/Music/Other/Album/01 Airbag.mp3'),
      ];
      expect(matchMovedTracks(gone, added), {gone.single.id: added.first.id});
    });

    // A renamed file is matched by title, track number and a similar length (within a couple of
    // seconds). "Dupe" could be either new file, so it isn't matched at all rather than guessing.
    test('by details when the file was renamed; ambiguous matches are left alone', () {
      final gone = [
        local('/m/x/old name.mp3', title: 'Song', n: 1, ms: 200000),
        local('/m/x/dupe.mp3', title: 'Dupe'),
      ];
      final added = [
        local('/m/y/new name.flac', title: 'Song', n: 1, ms: 201000),
        local('/m/y/d1.mp3', title: 'Dupe'),
        local('/m/y/d2.mp3', title: 'Dupe'),
      ];
      expect(matchMovedTracks(gone, added), {gone.first.id: added.first.id});
    });

    test('different lengths don\'t match', () {
      final m = matchMovedTracks(
        [local('/a/1.mp3', title: 'S', ms: 100000)],
        [local('/b/2.mp3', title: 'S', ms: 300000)],
      );
      expect(m, isEmpty);
    });

    // A whole library moving to a new drive letter: 20,000 songs must be matched quickly (this
    // runs on the UI thread). Before 0.1.15 it compared every pair, about 400 million times.
    test('a whole library moving drive is matched quickly', () {
      const count = 20000;
      String rel(int i) => 'Artist ${i % 400}\\Album ${i % 1600}\\${(i % 12) + 1} Track $i.mp3';
      final gone = [for (var i = 0; i < count; i++) local('D:\\Music\\${rel(i)}', title: 'Track $i')];
      final added = [for (var i = 0; i < count; i++) local('E:\\Music\\${rel(i)}', title: 'Track $i')];
      final watch = Stopwatch()..start();
      final m = matchMovedTracks(gone, added);
      watch.stop();
      expect(m.length, count);
      expect(m[gone[123].id], added[123].id);
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });

    // The faster matching must give exactly the same answers as the old compare-everything way,
    // including ties, renamed files and songs that are already taken.
    test('gives the same results as comparing every pair', () {
      // The pre-0.1.15 algorithm, kept here as the reference.
      Map<String, String> reference(List<Track> gone, List<Track> added) {
        int shared(List<String> a, List<String> b) {
          var n = 0;
          while (n < a.length && n < b.length && a[a.length - 1 - n] == b[b.length - 1 - n]) {
            n++;
          }
          return n;
        }

        bool close(Track a, Track b) =>
            !a.hasDuration || !b.hasDuration || (a.duration - b.duration).abs() <= const Duration(seconds: 2);
        final taken = <String>{};
        final result = <String, String>{};
        for (final old in gone) {
          var best = 0;
          final ids = <String>[];
          for (final t in added) {
            if (taken.contains(t.id)) continue;
            final n = shared(pathParts(old.path!), pathParts(t.path!));
            if (n < 2) continue;
            if (n > best) {
              best = n;
              ids
                ..clear()
                ..add(t.id);
            } else if (n == best) {
              ids.add(t.id);
            }
          }
          if (ids.length == 1) {
            result[old.id] = ids.single;
            taken.add(ids.single);
            continue;
          }
          final same = [
            for (final t in added)
              if (!taken.contains(t.id) && signature(t) == signature(old) && close(old, t)) t.id
          ];
          if (same.length == 1) {
            result[old.id] = same.single;
            taken.add(same.single);
          }
        }
        return result;
      }

      // A deliberately messy mix: repeated folder/file names, copies of the same album, renames,
      // files with no folder, and a few lengths.
      final gone = <Track>[];
      final added = <Track>[];
      for (var i = 0; i < 300; i++) {
        final title = 'Song ${i % 37}';
        final ms = (i % 5) * 60000;
        gone.add(local('/old/${i % 7}/Album ${i % 11}/${i % 13}.mp3', title: title, n: i % 4, ms: ms));
        added.add(local('/new/${i % 3}/Album ${i % 11}/${i % 13}.mp3', title: title, n: i % 4, ms: ms + (i % 3) * 1000));
        if (i % 9 == 0) added.add(local('/renamed/r$i.flac', title: title, n: i % 4, ms: ms));
        if (i % 17 == 0) added.add(local('lonely$i.mp3', title: title, n: i % 4));
      }
      expect(matchMovedTracks(gone, added), reference(gone, added));
    });
  });

  // A real temp library with two tiny WAVs, wired to PlaylistsModel the same way main.dart does:
  // the library asks which songs playlists use, and tells playlists when ids move or are dropped.
  group('Songs that aren\'t on the device', () {
    late Directory dir;
    late Storage storage;
    late LibraryModel lib;
    late PlaylistsModel pl;
    late Directory music;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('hometunes_keep');
      storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      Directory(storage.artDir).createSync();
      music = Directory(p.join(dir.path, 'music', 'Album'))..createSync(recursive: true);
      File(p.join(music.path, 'one.wav')).writeAsBytesSync(silentWav());
      File(p.join(music.path, 'two.wav')).writeAsBytesSync(silentWav());
      lib = LibraryModel(storage);
      pl = PlaylistsModel(storage);
      lib
        ..otherReferencedIds = (() => pl.referencedIds)
        ..onIdsRemapped = pl.remapIds
        ..onIdsForgotten = pl.removeIds;
      await lib.addFolder(p.join(dir.path, 'music'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    String id(String name) => 'local:${p.join(music.path, name)}';

    // Move a file out of the music folder and rescan: it becomes "missing" (still listed with its
    // edit and like, but not playable); put it back and it returns with everything intact.
    test('edits and likes are kept while a file is gone, and come back with it', () async {
      expect(lib.tracks.length, 2);
      await lib.editMany([id('one.wav')], const TrackEdit(title: 'Kept title'));
      pl.toggleLike(lib.byId(id('one.wav'))!);

      final moved = File(p.join(dir.path, 'elsewhere.wav'));
      File(p.join(music.path, 'one.wav')).renameSync(moved.path);
      await lib.scanLocal();
      expect(lib.tracks.length, 1);
      expect(lib.missingTracks.single.title, 'Kept title');
      expect(pl.liked, [id('one.wav')]);
      expect(lib.playableUri(local(p.join(music.path, 'one.wav'))), isNull);

      moved.renameSync(p.join(music.path, 'one.wav'));
      await lib.scanLocal();
      expect(lib.missingTracks, isEmpty);
      expect(lib.byId(id('one.wav'))!.title, 'Kept title');
    });

    // Moved within the music folder: the rescan spots it and moves its edits and playlist entry
    // over to the new id, so nothing shows as missing.
    test('a moved file keeps its edits and playlist places', () async {
      await lib.editMany([id('two.wav')], const TrackEdit(title: 'Mine'));
      final list = pl.create('Mix');
      pl.addTracks(list, [lib.byId(id('two.wav'))!]);

      final newFolder = Directory(p.join(dir.path, 'music', 'New', 'Album'))..createSync(recursive: true);
      File(p.join(music.path, 'two.wav')).renameSync(p.join(newFolder.path, 'two.wav'));
      await lib.scanLocal();

      final newId = 'local:${p.join(newFolder.path, 'two.wav')}';
      expect(lib.byId(newId)!.title, 'Mine');
      expect(pl.byId(list.id)!.trackIds, [newId]);
      expect(lib.missingTracks, isEmpty);
    });

    test('forgetting missing songs clears their data', () async {
      await lib.editMany([id('one.wav')], const TrackEdit(title: 'X'));
      pl.toggleLike(lib.byId(id('one.wav'))!);
      File(p.join(music.path, 'one.wav')).deleteSync();
      await lib.scanLocal();
      await lib.forgetMissing();
      expect(lib.missingTracks, isEmpty);
      expect(lib.isEdited(id('one.wav')), isFalse);
      expect(pl.liked, isEmpty);
    });

    // Make an edit, a custom cover and a playlist, back up, wipe it all, then restore in
    // "replace" mode (merge: false). A safety copy of the data before the restore is also kept.
    test('backup round trip: replace restores everything', () async {
      await lib.editMany([id('one.wav')], const TrackEdit(title: 'Backed up'));
      final cover = await lib.importCoverBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]));
      await lib.editMany([id('two.wav')], TrackEdit(art: cover));
      pl.addTracks(pl.create('Road trip'), [lib.byId(id('two.wav'))!]);
      await Future<void>.delayed(const Duration(milliseconds: 50)); // let playlists save

      final bytes = await lib.createBackup();

      // Wipe the data, then restore.
      await lib.resetEdits([id('one.wav'), id('two.wav')]);
      pl.delete(pl.playlists.single);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(File(cover).existsSync(), isFalse); // unused covers are cleaned up

      final backup = AppBackup.read(bytes);
      expect(backup.editCount, 2);
      expect(backup.playlistCount, 1);
      await lib.restoreBackup(backup, merge: false, reloadOthers: pl.load);

      expect(lib.byId(id('one.wav'))!.title, 'Backed up');
      expect(lib.byId(id('two.wav'))!.art, cover);
      expect(File(cover).existsSync(), isTrue);
      expect(pl.playlists.single.name, 'Road trip');
      expect(File(lib.beforeRestorePath).existsSync(), isTrue);
    });
  });

  group('Backup file', () {
    // A crafted backup mustn't be able to write, or point covers, outside the app's art folder.
    // "\" counts as a separator on Windows, which the old check missed (0.1.15).
    test('cover images and app paths from a backup stay inside the app folder', () {
      final root = p.join(Directory.systemTemp.path, 'ht');
      final art = p.join(root, 'art');
      expect(AppBackup.safeArtDestination(root, 'art/abc.img')!.path, p.join(art, 'abc.img'));
      expect(AppBackup.safeArtDestination(root, 'art/custom/x.png')!.path, p.join(art, 'custom', 'x.png'));
      for (final bad in [
        'art/..\\..\\evil.exe',
        'art/..\\evil.exe',
        'art/../evil.exe',
        'art\\..\\evil.exe',
        'art/C:evil.exe',
        'art/C:\\Windows\\evil.exe',
        '/art/x.img',
        'art//x.img',
        'art/./x.img',
        'settings.json',
        'art',
      ]) {
        expect(AppBackup.safeArtDestination(root, bad), isNull, reason: bad);
      }
      final ok = AppBackup.fromPortable({'art': '@app/art/custom/x.jpg'}, root) as Map;
      expect(ok['art'], p.join(root, 'art', 'custom', 'x.jpg'));
      final crafted = AppBackup.fromPortable({'a': '@app/../../evil.jpg', 'b': '@app/art\\..\\..\\x'}, root) as Map;
      expect(crafted['a'], '');
      expect(crafted['b'], '');
    });

    // App-folder paths become "@app/..." so a backup can be restored on another computer or
    // phone where the app folder is somewhere else. Song ids are left as they are.
    test('paths in the app folder are stored relative to it', () {
      final root = p.join(Directory.systemTemp.path, 'ht');
      final json = {
        'art': p.join(root, 'art', 'custom', 'x.jpg'),
        'id': 'local:/music/a.mp3',
        'list': [p.join(root, 'art', 'y.img')],
      };
      final portable = AppBackup.toPortable(json, root) as Map;
      expect(portable['art'], '@app/art/custom/x.jpg');
      expect(portable['id'], 'local:/music/a.mp3');
      expect((portable['list'] as List).single, '@app/art/y.img');
      final other = p.join(Directory.systemTemp.path, 'other');
      expect((AppBackup.fromPortable(portable, other) as Map)['art'], p.join(other, 'art', 'custom', 'x.jpg'));
    });

    test('rejects files that aren\'t backups', () {
      expect(() => AppBackup.read([1, 2, 3]), throwsFormatException);
    });

    test('the server password is left out unless asked for', () async {
      final dir = Directory.systemTemp.createTempSync('hometunes_pw');
      addTearDown(() => dir.deleteSync(recursive: true));
      final storage = Storage.at(dir);
      await storage.write('settings.json', {
        'folders': [],
        'server': {'url': 'http://s', 'username': 'u', 'password': 'secret'},
      });
      expect(AppBackup.read(await AppBackup.create(storage)).hasPassword, isFalse);
      expect(AppBackup.read(await AppBackup.create(storage, includePassword: true)).hasPassword, isTrue);
    });

    // The same playlist in both: songs are combined without repeats; new playlists are added.
    test('merging playlists combines songs and likes', () {
      final merged = AppBackup.mergePlaylists(
        {
          'playlists': [
            {'id': '1', 'name': 'A', 'trackIds': ['x', 'y']}
          ],
          'liked': ['x'],
        },
        {
          'playlists': [
            {'id': '1', 'name': 'A', 'trackIds': ['y', 'z']},
            {'id': '2', 'name': 'B', 'trackIds': ['q']},
          ],
          'liked': ['z', 'x'],
        },
      );
      final lists = merged['playlists'] as List;
      expect(lists.length, 2);
      expect((lists.first as Map)['trackIds'], ['x', 'y', 'z']);
      expect(merged['liked'], ['x', 'z']);
    });
  });
}
