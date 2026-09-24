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

    test('many quick saves to the same file all succeed and the last one wins', () async {
      final results = await Future.wait([
        for (var i = 0; i < 25; i++) storage.write('playlists.json', {'n': i}),
      ]);
      expect(results, everyElement(isTrue));
      expect(await storage.read('playlists.json'), {'n': 24});
    });

    test('missing or corrupt files read as null', () async {
      expect(await storage.read('nope.json'), isNull);
      File('${dir.path}/bad.json').writeAsStringSync('{not json');
      expect(await storage.read('bad.json'), isNull);
    });
  });

  group('Subsonic sync', () {
    const cfg = ServerConfig(url: 'http://music.test', username: 'me', password: 'pw');

    http.Response ok(Map<String, dynamic> body) => http.Response(
          jsonEncode({
            'subsonic-response': {'status': 'ok', ...body}
          }),
          200,
        );

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
