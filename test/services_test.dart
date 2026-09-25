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
