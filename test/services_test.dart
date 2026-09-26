// Tests for two services: Storage (the JSON files the app saves its data in) and the Subsonic
// server sync (services/subsonic_client.dart). The server is faked with http's MockClient, so
// no network is needed.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/subsonic_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Storage', () {
    late Directory dir;
    late Storage storage;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_test');
      storage = Storage.at(dir);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    // 25 saves fired at once: Storage queues writes per file, so none clash and the last
    // one sticks.
    test('many quick saves to the same file all succeed and the last one wins', () async {
      final results = await Future.wait([
        for (var i = 0; i < 25; i++) storage.write('playlists.json', {'n': i}),
      ]);
      expect(results, everyElement(isTrue));
      expect(await storage.read('playlists.json'), {'n': 24});
    });

    // A damaged file mustn't crash the app; it's treated as "no saved data".
    test('missing or corrupt files read as null', () async {
      expect(await storage.read('nope.json'), isNull);
      File('${dir.path}/bad.json').writeAsStringSync('{not json');
      expect(await storage.read('bad.json'), isNull);
    });

    // A damaged file is set aside (never overwritten by the next save) and reported.
    test('a damaged file is kept as a .corrupt copy and reported', () async {
      File('${dir.path}/playlists.json').writeAsStringSync('{"playlists": [ {"na');
      expect(await storage.read('playlists.json'), isNull);
      final kept = dir.listSync().whereType<File>().where((f) => f.path.contains('playlists.corrupt-')).toList();
      expect(kept, hasLength(1));
      expect(kept.single.readAsStringSync(), '{"playlists": [ {"na');
      expect(storage.problems.single, contains('playlists and Liked Songs'));
      // The next save makes a fresh file and leaves the kept copy alone.
      expect(await storage.write('playlists.json', {'playlists': []}), isTrue);
      expect(kept.single.existsSync(), isTrue);
    });

    // An empty file (what an interrupted write can leave) counts as damaged too.
    test('an empty file counts as damaged', () async {
      File('${dir.path}/edits.json').writeAsStringSync('');
      expect(await storage.read('edits.json'), isNull);
      expect(storage.problems, hasLength(1));
    });

    // A crash between writing the temp file and renaming it: the temp file is complete, so
    // it's used (whether the main file is missing or half-written).
    test('an unfinished save is recovered from the temp file', () async {
      File('${dir.path}/listening.json.tmp').writeAsStringSync('{"books": {"b": 1}}');
      expect(await storage.read('listening.json'), {'books': {'b': 1}});
      expect(File('${dir.path}/listening.json').existsSync(), isTrue);
      expect(File('${dir.path}/listening.json.tmp').existsSync(), isFalse);
      expect(storage.problems.single, contains('recovered'));

      File('${dir.path}/bookmarks.json').writeAsStringSync('{"bookm');
      File('${dir.path}/bookmarks.json.tmp').writeAsStringSync('{"bookmarks": []}');
      expect(await storage.read('bookmarks.json'), {'bookmarks': []});
    });

    // A half-written temp file next to a good main file: the main file wins.
    test('a half-written temp file is ignored when the main file is fine', () async {
      File('${dir.path}/settings.json').writeAsStringSync('{"folders": []}');
      File('${dir.path}/settings.json.tmp').writeAsStringSync('{"fold');
      expect(await storage.read('settings.json'), {'folders': []});
      expect(storage.problems, isEmpty);
    });

    // Saving replaces the old file in one step (no delete first), and leaves no temp file.
    test('saving over an existing file replaces it and leaves no temp file', () async {
      await storage.write('settings.json', {'v': 1});
      await storage.write('settings.json', {'v': 2});
      expect(await storage.read('settings.json'), {'v': 2});
      expect(File('${dir.path}/settings.json.tmp').existsSync(), isFalse);
    });

    // Only the newest few damaged copies are kept.
    test('old damaged copies are tidied away', () async {
      for (var i = 0; i < Storage.keepCorruptCopies + 2; i++) {
        File('${dir.path}/lyrics.corrupt-2026-01-0${i + 1}T00-00-00.json').writeAsStringSync('x');
      }
      File('${dir.path}/lyrics.json').writeAsStringSync('nope');
      await storage.read('lyrics.json');
      final copies = dir.listSync().where((f) => f.path.contains('lyrics.corrupt-'));
      expect(copies, hasLength(Storage.keepCorruptCopies));
    });
  });

  group('Subsonic sync', () {
    const cfg = ServerConfig(url: 'http://music.test', username: 'me', password: 'pw');

    /// A fake successful Subsonic reply wrapping [body].
    http.Response ok(Map<String, dynamic> body) => http.Response(
          jsonEncode({
            'subsonic-response': {'status': 'ok', ...body}
          }),
          200,
        );

    // The fake server lists two albums; the second one errors. The sync should keep the songs of
    // the first and count one failed album.
    test('a broken album is skipped, not fatal', () async {
      final mock = MockClient((req) async {
        final method = req.url.pathSegments.last;
        if (method == 'getAlbumList2') {
          return ok({
            'albumList2': {
              'album': [
                {'id': 'a1'},
                {'id': 'a2'},
              ]
            }
          });
        }
        if (method == 'getAlbum' && req.url.queryParameters['id'] == 'a1') {
          return ok({
            'album': {
              'artist': 'Band',
              'song': [
                {'id': 's1', 'title': 'One', 'album': 'Rec', 'duration': 60},
                {'id': 's2', 'title': 'Two', 'album': 'Rec', 'duration': 61},
              ]
            }
          });
        }
        return http.Response('boom', 500); // a2 fails
      });

      final client = SubsonicClient(cfg, httpClient: mock);
      final result = await client.fetchAllTracks();
      expect(result.tracks.map((t) => t.title), ['One', 'Two']);
      expect(result.failedAlbums, 1);
    });

    // If nothing at all could be fetched, that's an error for the user, not an empty library.
    test('every album failing is reported as an error', () async {
      final mock = MockClient((req) async {
        if (req.url.pathSegments.last == 'getAlbumList2') {
          return ok({
            'albumList2': {
              'album': [
                {'id': 'a1'}
              ]
            }
          });
        }
        return http.Response('down', 503);
      });
      final client = SubsonicClient(cfg, httpClient: mock);
      expect(client.fetchAllTracks(), throwsA(isA<SubsonicException>()));
    });

    // The server's own error text should reach the user unchanged.
    test('bad login message comes through', () async {
      final mock = MockClient((_) async => http.Response(
            jsonEncode({
              'subsonic-response': {
                'status': 'failed',
                'error': {'code': 40, 'message': 'Wrong username or password'}
              }
            }),
            200,
          ));
      final client = SubsonicClient(cfg, httpClient: mock);
      expect(
        client.ping(),
        throwsA(isA<SubsonicException>().having((e) => e.message, 'message', 'Wrong username or password')),
      );
    });
  });
}
