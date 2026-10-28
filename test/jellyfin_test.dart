// 0.2.1: videos from a Jellyfin server. A pretend server (http's MockClient) answers like the
// user's Jellyfin 12.3 does: signing in, libraries, series and episodes and films with their
// places, pictures, and the playing reports. Checks the client, ServerVideosModel (the Videos tab
// gets the server's videos, places both ways, nothing secret saved in files), the video page
// playing from it, and Test connection signing in.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/jellyfin_client.dart';
import 'package:hometunes/services/secret_store.dart';
import 'package:hometunes/services/server_probe.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/state/remote_videos.dart';
import 'package:hometunes/state/server_videos.dart';
import 'package:hometunes/state/servers_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/state/video_session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'fake_audio_engine.dart';
import 'fake_video_engine.dart';

/// A pretend Jellyfin server.
class FakeJellyfin {
  final String password;
  FakeJellyfin({this.password = 'sesame'});

  /// Tokens it has handed out and still accepts.
  final Set<String> tokens = {};
  int signIns = 0;

  /// Every request: "METHOD /path?query", and the bodies of the POSTs.
  final List<String> requests = [];
  final List<Map<String, dynamic>> bodies = [];

  /// Whether it answers at all.
  bool up = true;

  /// The user's places on the server, by item id.
  final Map<String, Map<String, dynamic>> userData = {
    'ep2': {'PlaybackPositionTicks': 6000000000, 'Played': false, 'LastPlayedDate': '2026-10-20T20:00:00.0000000Z'},
    'film1': {'PlaybackPositionTicks': 0, 'Played': true, 'LastPlayedDate': '2026-10-01T20:00:00Z'},
  };

  Map<String, dynamic> episode(String id, int season, int ep, String name, {String? seasonName}) => {
        'Id': id,
        'Type': 'Episode',
        'Name': name,
        'SeriesName': 'Silo',
        'SeriesId': 'silo',
        'SeasonName': seasonName ?? 'Season $season',
        'ParentIndexNumber': season,
        'IndexNumber': ep,
        'RunTimeTicks': 30000000000, // 50 minutes
        'Overview': 'Episode $ep.',
        'Genres': ['Drama'],
        'DateCreated': '2026-10-24T10:00:00.0000000Z',
        'Width': 1920,
        'Height': 1080,
        'ImageTags': {'Primary': 'tag$id'},
        'SeriesPrimaryImageTag': 'silotag',
        'MediaSources': [
          {
            'Container': 'mkv',
            'Size': 1500000000,
            'MediaStreams': [
              {'Type': 'Subtitle', 'Index': 3, 'Codec': 'subrip', 'IsExternal': true, 'DisplayTitle': 'English', 'Language': 'eng'},
              {'Type': 'Subtitle', 'Index': 4, 'Codec': 'PGSSUB', 'IsExternal': true, 'DisplayTitle': 'Pictures'},
            ],
          }
        ],
        'UserData': userData[id] ?? {'PlaybackPositionTicks': 0, 'Played': false},
      };

  List<Map<String, dynamic>> get episodes => [
        episode('ep1', 1, 1, 'Freedom Day'),
        episode('ep2', 1, 2, 'Holston\'s Pick'),
        episode('ep3', 2, 1, 'The Engineer', seasonName: 'Outside'),
      ];

  List<Map<String, dynamic>> get films => [
        {
          'Id': 'film1',
          'Type': 'Movie',
          'Name': 'Dune',
          'ProductionYear': 2021,
          'RunTimeTicks': 93600000000,
          'Container': 'mp4',
          'ImageTags': {'Primary': 'p1', 'Thumb': 't1'},
          'MediaSources': [
            {'Container': 'mp4', 'Size': 4000000000},
          ],
          'UserData': userData['film1'],
        },
      ];

  bool authorised(http.Request r) {
    final auth = r.headers['Authorization'] ?? '';
    final m = RegExp(r'Token="([^"]+)"').firstMatch(auth);
    return m != null && tokens.contains(m.group(1));
  }

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  late final MockClient client = MockClient((r) async {
    requests.add('${r.method} ${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''}');
    if (r.body.isNotEmpty) {
      try {
        bodies.add(Map<String, dynamic>.from(jsonDecode(r.body) as Map));
      } catch (_) {}
    }
    if (!up) throw const SocketException('connection refused');
    final path = r.url.path;
    if (path == '/System/Info/Public') {
      return json({'ServerName': 'DESKTOP', 'Version': '12.3.0', 'ProductName': 'Jellyfin Server', 'Id': 'srv'});
    }
    if (path == '/Users/AuthenticateByName') {
      final b = jsonDecode(r.body) as Map;
      if (b['Username'] != 'james' || b['Pw'] != password) return http.Response('', 401);
      signIns++;
      final t = 'token${tokens.length + 1}';
      tokens.add(t);
      return json({'AccessToken': t, 'User': {'Id': 'user1'}, 'ServerId': 'srv'});
    }
    if (!authorised(r)) return http.Response('', 401);
    if (path == '/Sessions/Logout') {
      tokens.removeWhere((t) => (r.headers['Authorization'] ?? '').contains(t));
      return http.Response('', 204);
    }
    if (path == '/UserViews') {
      return json({
        'Items': [
          {'Id': 'tv', 'Name': 'TV Shows', 'CollectionType': 'tvshows'},
          {'Id': 'films', 'Name': 'Films', 'CollectionType': 'movies'},
          {'Id': 'music', 'Name': 'Music', 'CollectionType': 'music'},
        ],
      });
    }
    if (path == '/Items') {
      final q = r.url.queryParameters;
      final types = q['includeItemTypes'] ?? '';
      List<Map<String, dynamic>> all;
      if (types == 'Series') {
        all = q['parentId'] == 'tv'
            ? [
                {'Id': 'silo', 'Name': 'Silo', 'Overview': 'People live underground.', 'Genres': ['Sci-Fi'], 'ProductionYear': 2023},
              ]
            : [];
      } else {
        all = switch (q['parentId']) { 'tv' => episodes, 'films' => films, _ => [] };
      }
      final start = int.parse(q['startIndex'] ?? '0'), limit = int.parse(q['limit'] ?? '100');
      final page = all.skip(start).take(limit).toList();
      return json({'Items': page, 'TotalRecordCount': all.length});
    }
    if (path.startsWith('/Items/') && path.contains('/Images/')) {
      return http.Response.bytes([0xFF, 0xD8, 0xFF, 1, 2, 3], 200, headers: {'content-type': 'image/jpeg'});
    }
    if (path.startsWith('/Sessions/Playing') || path.startsWith('/UserPlayedItems/') || path.startsWith('/UserItems/')) {
      return http.Response('', 204);
    }
    return http.Response('', 404);
  });
}

void main() {
  late Directory dir;
  late Storage storage;
  late MemorySecretStore secrets;
  late LibraryModel lib;
  late ServersModel servers;
  late VideoLibraryModel videos;
  late FakeJellyfin server;
  late ServerVideosModel model;
  late ServerEntry entry;

  Future<ServerVideosModel> makeModel() async {
    final m = ServerVideosModel(
      storage: storage,
      servers: servers,
      videos: videos,
      secrets: secrets,
      appVersion: '0.2.1',
      httpClient: () => server.client,
      deviceName: 'Test PC',
    );
    await m.load();
    return m;
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('hometunes_jellyfin');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    secrets = MemorySecretStore();
    lib = LibraryModel(storage, secrets: secrets);
    servers = ServersModel(storage, lib);
    videos = VideoLibraryModel(storage, lib);
    server = FakeJellyfin();
    entry = await servers.add(
      type: ServerType.jellyfin,
      name: 'Den',
      url: 'http://192.168.1.81:8096',
      username: 'james',
      password: 'sesame',
      uses: {MediaKind.videos},
    );
    model = await makeModel();
  });

  tearDown(() async {
    model.dispose();
    await videos.settle();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> until(bool Function() ok) async {
    for (var i = 0; i < 400 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ok(), isTrue);
  }

  group('the client', () {
    test('signs in with the password once, then sends only the token, never in an address', () async {
      final c = JellyfinClient(baseUrl: 'http://192.168.1.81:8096/', deviceId: 'dev1', httpClient: server.client);
      final r = await c.signIn('james', 'sesame');
      expect(r.token, 'token1');
      expect(r.userId, 'user1');
      expect(c.authorization, contains('Token="token1"'));
      expect(c.authorization, contains('DeviceId="dev1"'));
      final views = await c.views();
      expect(views.map((v) => v.name), ['TV Shows', 'Films', 'Music']);
      expect(views.where((v) => v.holdsVideos).map((v) => v.id), ['tv', 'films']);
      // Addresses for the player, downloads and pictures carry no token.
      for (final u in [c.streamUri('ep1', container: 'mkv'), c.convertedUri('ep1', maxHeight: 720), c.downloadUri('ep1'),
          c.imageUri('ep1', 'Primary')]) {
        expect(u.toString(), isNot(contains('token1')));
        expect(u.toString(), isNot(contains('api_key')));
      }
      expect(c.mediaHeaders['Authorization'], contains('token1'));
      expect(server.requests.every((r) => !r.contains('token1') && !r.contains('sesame')), isTrue);
    });

    test('a wrong password says so', () async {
      final c = JellyfinClient(baseUrl: 'http://192.168.1.81:8096', deviceId: 'd', httpClient: server.client);
      await expectLater(
        c.signIn('james', 'nope'),
        throwsA(isA<JellyfinException>().having((e) => e.message, 'message', contains('user name or password'))),
      );
    });

    test('long lists are read a page at a time', () async {
      final c = JellyfinClient(baseUrl: 'http://192.168.1.81:8096', deviceId: 'd', httpClient: server.client);
      await c.signIn('james', 'sesame');
      final pages = <(int, int)>[];
      final items = await c.items(parentId: 'tv', types: const ['Episode'], pageSize: 2, onProgress: (d, t) => pages.add((d, t)));
      expect(items.map((x) => x['Id']), ['ep1', 'ep2', 'ep3']);
      expect(pages, [(2, 3), (3, 3)]);
    });

    test('converted copies carry on from a place, keeping the original\'s clock', () {
      final c = JellyfinClient(baseUrl: 'http://x:8096', deviceId: 'd');
      final u = c.convertedUri('ep1', maxHeight: 720, start: const Duration(minutes: 10));
      expect(u.path, '/Videos/ep1/stream.mkv');
      expect(u.queryParameters['startTimeTicks'], '${const Duration(minutes: 10).inMicroseconds * 10}');
      expect(u.queryParameters['copyTimestamps'], 'true');
      expect(u.queryParameters['videoBitRate'], '4000000');
      expect(u.queryParameters['static'], 'false');
      c.close();
    });
  });

  group('the Videos tab', () {
    test('a sync brings the server\'s series and films in as collections, with seasons and places', () async {
      await model.sync(entry);
      final ids = videos.videos.map((v) => v.id).toSet();
      expect(ids, {'jf:${entry.id}:ep1', 'jf:${entry.id}:ep2', 'jf:${entry.id}:ep3', 'jf:${entry.id}:film1'});
      // The music library isn't read for videos.
      expect(server.requests.any((r) => r.contains('parentId=music')), isFalse);

      final silo = videos.collectionNamed('Silo')!;
      expect(silo.category, 'TV');
      expect(silo.description, 'People live underground.');
      expect(silo.videos.map((v) => v.episodeLabel), ['S1 E1', 'S1 E2', 'S2 E1']);
      expect(videos.groupLabel(silo, 'Season 2', [silo.videos[2]]), 'Season 2 – Outside');
      final ep1 = videos.byId('jf:${entry.id}:ep1')!;
      expect(ep1.format, 'MKV');
      expect(ep1.duration, const Duration(minutes: 50));
      expect(ep1.resolution, '1920×1080');
      expect(ep1.genre, 'Drama');
      // The subtitle file it keeps beside it (a picture subtitle can't be fetched on its own).
      expect(ep1.subtitles.length, 1);
      expect(serverSubtitle(ep1.subtitles.single)!.format, 'srt');

      final dune = videos.collectionNamed('Dune')!;
      expect(dune.category, 'Films');
      expect(dune.year, 2021);

      // Where you got to on the server.
      expect(videos.placeOf('jf:${entry.id}:ep2')!.position, const Duration(minutes: 10));
      expect(videos.placeOf('jf:${entry.id}:film1')!.watched, isTrue);
      expect(videos.continueWatching.map((v) => v.id), ['jf:${entry.id}:ep2']);
      expect(videos.serverNameOf(ep1), 'Den');
      expect(model.statusFor(entry), contains('4 videos'));
      expect(model.okFor(entry), isTrue);
    });

    test('pictures are downloaded, and the collection gets the series\' poster', () async {
      await model.sync(entry);
      await until(() => videos.byId('jf:${entry.id}:ep1')?.thumb != null);
      final ep1 = videos.byId('jf:${entry.id}:ep1')!;
      expect(File(ep1.thumb!).existsSync(), isTrue);
      expect(p.isWithin(storage.artDir, ep1.thumb!), isTrue);
      expect(videos.thumbFile(ep1), ep1.thumb);
      await until(() => videos.coverFile(videos.collectionNamed('Silo')!)?.contains('silo-Primary') ?? false);
    });

    test('nothing secret goes in the files: the token is in protected storage', () async {
      await model.sync(entry);
      final saved = jsonEncode(await storage.read(ServerVideosModel.fileName));
      expect(saved, isNot(contains('token1')));
      expect(saved, isNot(contains('sesame')));
      expect(await secrets.read(ServerVideosModel.tokenKey(entry)), 'token1');
      final videosFile = jsonEncode(await storage.read(VideoLibraryModel.fileName));
      expect(videosFile, isNot(contains('token1')));
    });

    test('what was read shows straight away next time, before the server answers', () async {
      await model.sync(entry);
      await videos.settle();
      model.dispose();
      final videos2 = VideoLibraryModel(storage, lib);
      await videos2.load();
      final again = ServerVideosModel(storage: storage, servers: servers, videos: videos2, secrets: secrets,
          httpClient: () => server.client);
      server.up = false;
      await again.load();
      expect(videos2.collectionNamed('Silo')!.videos.length, 3);
      expect(videos2.placeOf('jf:${entry.id}:ep2')!.position, const Duration(minutes: 10));
      // The server is off: the card says so.
      await again.sync(entry);
      expect(again.okFor(entry), isFalse);
      expect(again.statusFor(entry), contains('Couldn\'t read it'));
      expect(videos2.collectionNamed('Silo')!.videos.length, 3); // still shown
      again.dispose();
      await videos2.settle();
      model = await makeModel(); // for tearDown
    });

    test('the saved token is used, and when the server stops taking it HomeTunes signs in again', () async {
      await model.sync(entry);
      expect(server.signIns, 1);
      await model.sync(entry);
      expect(server.signIns, 1); // the token was kept
      server.tokens.clear(); // signed out on the server
      await model.sync(entry);
      expect(server.signIns, 2);
      expect(model.okFor(entry), isTrue);
    });

    test('a scan of the video folders leaves server videos and their places alone', () async {
      await model.sync(entry);
      final folder = Directory(p.join(dir.path, 'vids'))..createSync();
      File(p.join(folder.path, 'Home.mkv')).writeAsBytesSync([1]);
      await lib.addVideoFolder(folder.path);
      await videos.scan();
      expect(videos.videos.length, 5);
      expect(videos.placeOf('jf:${entry.id}:ep2'), isNotNull);
    });

    test('switching the server off for videos takes them away; removing it forgets them', () async {
      await model.sync(entry);
      await servers.setUse(servers.byId(entry.id)!, MediaKind.videos, false);
      expect(videos.videos, isEmpty);
      expect(videos.placeOf('jf:${entry.id}:ep2'), isNotNull); // kept for switching back
      await servers.setUse(servers.byId(entry.id)!, MediaKind.videos, true);
      await until(() => videos.videos.length == 4);
      await servers.remove(servers.byId(entry.id)!);
      await until(() => videos.videos.isEmpty && videos.placeOf('jf:${entry.id}:ep2') == null);
      await until(() => secrets.values.isEmpty);
    });

    test('a library can be left out', () async {
      await model.sync(entry);
      expect(model.librariesOf(entry).map((v) => v.name), ['TV Shows', 'Films']);
      await model.setLibraryShown(entry, 'films', false);
      expect(videos.collectionNamed('Dune'), isNull);
      expect(videos.collectionNamed('Silo'), isNotNull);
      expect(model.statusFor(entry), contains('1 library left out'));
    });

    test('a newer place here wins over the server\'s, and is sent to it', () async {
      await model.sync(entry);
      final id = 'jf:${entry.id}:ep2';
      server.up = false;
      videos.savePlace(id, const Duration(minutes: 30), const Duration(minutes: 50));
      // Stopping while the server is off: kept to send later.
      model.stopped(videos.byId(id)!, const Duration(minutes: 30), const Duration(minutes: 50));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      server.up = true;
      server.requests.clear();
      await model.sync(entry);
      expect(server.requests.any((r) => r.startsWith('POST /UserItems/ep2/UserData')), isTrue);
      final sent = server.bodies.lastWhere((b) => b.containsKey('PlaybackPositionTicks'));
      expect(sent['PlaybackPositionTicks'], const Duration(minutes: 30).inMicroseconds * 10);
      // The server's older place didn't overwrite this one.
      expect(videos.placeOf(id)!.position, const Duration(minutes: 30));
    });

    test('marking watched tells the server', () async {
      await model.sync(entry);
      server.requests.clear();
      await videos.setWatched(['jf:${entry.id}:ep1'], true);
      await until(() => server.requests.contains('POST /UserPlayedItems/ep1?userId=user1'));
      await videos.setWatched(['jf:${entry.id}:ep1'], false);
      await until(() => server.requests.contains('DELETE /UserPlayedItems/ep1?userId=user1'));
    });
  });

  group('playing', () {
    late FakeVideoEngine engine;
    late PlayerModel music;
    VideoSession? session;

    setUp(() async {
      await model.sync(entry);
      engine = FakeVideoEngine();
      music = PlayerModel(lib, engine: FakeAudioEngine());
      session = null;
    });
    tearDown(() async {
      session?.dispose();
      music.dispose();
      await pumpEventQueue();
    });

    VideoSession start(String item) => session = VideoSession(
          engine: engine,
          videos: videos,
          music: music,
          videoId: 'jf:${entry.id}:$item',
          upNextTick: const Duration(milliseconds: 1),
          tracksSettle: Duration.zero,
          openingTimeout: const Duration(seconds: 1),
        );

    test('plays the original from the server with the sign-in in headers, and reports to it', () async {
      final s = start('ep1');
      await until(() => engine.openPath != null);
      expect(engine.openPath, startsWith('http://192.168.1.81:8096/Videos/ep1/stream.mkv?static=true'));
      expect(engine.openPath, isNot(contains('token')));
      expect(engine.openHeaders!['Authorization'], contains('Token="token1"'));
      expect(s.address!.remote, isTrue);
      expect(s.file, isNull); // no seek preview for a stream
      await until(() => server.requests.contains('POST /Sessions/Playing'));
      // The server's subtitle file is added to the choices.
      engine.loaded(length: const Duration(minutes: 50));
      await until(() => engine.calls.any((c) => c.startsWith('sub-add http://192.168.1.81:8096/Videos/ep1/ep1/Subtitles/3/Stream.srt')));
      engine.moveTo(const Duration(minutes: 4));
      engine.setPlaying(false); // paused: where it got to is sent
      await until(() => server.requests.contains('POST /Sessions/Playing/Progress'));
      s.dispose();
      session = null;
      await until(() => server.requests.contains('POST /Sessions/Playing/Stopped'));
      final stopped = server.bodies.lastWhere((b) => b['ItemId'] == 'ep1' && b.length <= 4);
      expect(stopped['PositionTicks'], const Duration(minutes: 4).inMicroseconds * 10);
    });

    test('a video that won\'t play as it is is asked for again as a converted copy', () async {
      final s = start('ep1');
      await until(() => engine.openPath != null);
      engine.fail('unsupported codec');
      await until(() => engine.openPath!.contains('stream.mkv?static=false'));
      expect(s.address!.converted, isTrue);
      expect(s.problem, isNull);
      // A second failure is reported.
      engine.fail('still no');
      expect(s.problem, contains('Can\'t play this video'));
    });

    test('a server that can\'t be signed in to says why', () async {
      await secrets.delete(ServerVideosModel.tokenKey(entry));
      await model.signOut(entry);
      server.up = false;
      final s = start('ep2');
      await until(() => s.problem != null);
      expect(s.problem, contains('Den'));
    });

    test('carries on from the server\'s place', () async {
      start('ep2');
      await until(() => engine.openPath != null);
      expect(engine.calls.first, startsWith('open stream at'));
      expect(isRemoteVideoId('jf:${entry.id}:ep2'), isTrue);
    });
  });

  test('Test connection signs in to a Jellyfin server, then signs out', () async {
    final ok = await probeServer(ServerType.jellyfin, 'http://192.168.1.81:8096',
        username: 'james', password: 'sesame', client: server.client);
    expect(ok.ok, isTrue);
    expect(ok.message, contains('Signed in to a Jellyfin server called "DESKTOP"'));
    expect(server.tokens, isEmpty); // signed straight out
    final bad = await probeServer(ServerType.jellyfin, 'http://192.168.1.81:8096',
        username: 'james', password: 'wrong', client: server.client);
    expect(bad.ok, isFalse);
    expect(bad.message, contains('couldn\'t sign in'));
  });

  test('a Jellyfin item becomes a video, a picture-less one too', () {
    final made = videoFromJellyfin(
      {'Id': 'v9', 'Type': 'Video', 'Name': 'Birthday', 'Container': 'mov,mp4'},
      serverKey: 's1',
      view: const JellyfinView('home', 'Home videos', 'homevideos'),
      pictureDir: dir.path,
    )!;
    expect(made.video.id, 'jf:s1:v9');
    expect(made.video.collection, 'Home videos');
    expect(made.video.format, 'MOV');
    expect(made.video.category, isNull);
    expect(made.pictures, isEmpty);
    expect(remoteServerOf(made.video.id), 's1');
    expect(remoteItemOf(made.video.id), 'v9');
    expect(videoFromJellyfin({'Id': 'x', 'Type': 'Series'}, serverKey: 's1', view: const JellyfinView('a', 'A', null), pictureDir: dir.path),
        isNull);
    final place = placeFromJellyfin({'PlaybackPositionTicks': 0, 'Played': false});
    expect(place, isNull);
    expect(VideoPlace(position: Duration.zero, updatedMs: 1).watched, isFalse);
  });
}
