// 0.2.7: audiobooks from an Audiobookshelf server. A pretend server (http's MockClient) answers
// the way the user's Audiobookshelf 2.37.2 did when it was checked with a test account (1 Nov):
// signing in with access and refresh tokens, libraries, items (brief lists, then full details in
// batches), covers, files and the user's places. Checks the client, ServerBooksModel (the Books
// tab gets the server's books with their chapters and covers, places both ways, nothing secret in
// files), playing and downloading from it, and Test connection signing in.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/download.dart';
import 'package:hometunes/services/abs_client.dart';
import 'package:hometunes/services/secret_store.dart';
import 'package:hometunes/services/server_probe.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/subsonic_client.dart' show hideSecrets;
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/state/remote_books.dart';
import 'package:hometunes/state/server_books.dart';
import 'package:hometunes/state/servers_model.dart';
import 'package:hometunes/state/source_filter.dart';
import 'package:http/http.dart' as http;
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/screens/settings/server_settings.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'fake_audio_engine.dart';

/// A JWT-looking token running out at [expMs] (only its payload is read).
String _jwt(String id, int expMs) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'id': id, 'type': 'access', 'exp': expMs ~/ 1000})}.sig';
}

/// A pretend Audiobookshelf server.
class FakeAbs {
  FakeAbs({this.password = 'sesame'});
  final String password;

  /// What its access tokens last.
  Duration accessFor = const Duration(hours: 1);

  /// The clock its tokens are made with.
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  final Set<String> access = {}, refresh = {};
  int signIns = 0, refreshes = 0, batches = 0, covers = 0;
  final List<String> requests = [];
  final List<Map<String, dynamic>> patches = [];
  bool up = true;
  bool batchRoute = true;

  /// The user's places, by item id.
  final Map<String, Map<String, dynamic>> progress = {
    'hhgttg': {
      'libraryItemId': 'hhgttg',
      'episodeId': null,
      'currentTime': 2000.0,
      'duration': 21101.69,
      'isFinished': false,
      'lastUpdate': 1793500000000,
    },
  };

  /// When each item last changed.
  final Map<String, int> updated = {'hhgttg': 100, 'dcc1': 200, 'broken': 300};

  Map<String, dynamic> get hhgttg => {
        'id': 'hhgttg',
        'mediaType': 'book',
        'addedAt': 1793570566393,
        'updatedAt': updated['hhgttg'],
        'media': {
          'coverPath': '/metadata/items/hhgttg/cover.jpg',
          'metadata': {
            'title': 'Hitchhiker\'s Guide to the Galaxy',
            'subtitle': 'the comedy sci-fi classic',
            'authors': [
              {'id': 'a1', 'name': 'Douglas Adams'},
            ],
            'narrators': ['Stephen Fry'],
            'series': [
              {'id': 's1', 'name': 'The Hitchhiker\'s Guide to the Galaxy', 'sequence': '1'},
            ],
            'genres': ['Science Fiction & Fantasy'],
            'publishedYear': '2012',
            'description': '<p><b>The comedy sci-fi classic.</b><br />Don\'t panic.</p>',
          },
          'chapters': [
            {'id': 0, 'start': 0, 'end': 291.29, 'title': 'Introduction'},
            {'id': 1, 'start': 291.29, 'end': 1845.43, 'title': 'Chapter 1'},
            {'id': 2, 'start': 1845.43, 'end': 21101.69, 'title': 'Chapter 2'},
          ],
          'audioFiles': [
            {
              'index': 1,
              'ino': '281474977132575',
              'duration': 21101.691066,
              'mimeType': 'audio/mp4',
              'exclude': false,
              'metadata': {'filename': 'Hitchhiker.m4b', 'ext': '.m4b', 'size': 335295342},
              'metaTags': {'tagTitle': 'Hitchhiker\'s Guide to the Galaxy'},
            },
          ],
        },
      };

  /// A book in three files, a chapter each, one left out on the server.
  Map<String, dynamic> get dcc1 => {
        'id': 'dcc1',
        'mediaType': 'book',
        'addedAt': 1793570000000,
        'updatedAt': updated['dcc1'],
        'media': {
          'coverPath': null,
          'metadata': {
            'title': 'Dungeon Crawler Carl',
            'authorName': 'Matt Dinniman',
            'narratorName': 'Jeff Hays',
            'seriesName': 'Dungeon Crawler Carl #1',
            'genres': <String>[],
            'publishedYear': '2020',
          },
          'chapters': [
            {'id': 0, 'start': 0, 'end': 600, 'title': 'One'},
            {'id': 1, 'start': 600, 'end': 1200, 'title': 'Two'},
          ],
          'audioFiles': [
            {'index': 2, 'ino': '22', 'duration': 600.0, 'metadata': {'filename': 'Part 02.mp3', 'ext': '.mp3'}, 'metaTags': {}},
            {'index': 1, 'ino': '11', 'duration': 600.0, 'metadata': {'filename': 'Part 01.mp3', 'ext': '.mp3'}, 'metaTags': {}},
            {'index': 3, 'ino': '33', 'duration': 5.0, 'exclude': true, 'metadata': {'filename': 'Credits.mp3', 'ext': '.mp3'}},
          ],
        },
      };

  /// An item with no files that can be played.
  Map<String, dynamic> get broken => {
        'id': 'broken',
        'mediaType': 'book',
        'updatedAt': updated['broken'],
        'media': {
          'metadata': {'title': 'Nothing here'},
          'audioFiles': <Object>[],
        },
      };

  Map<String, Map<String, dynamic>> get full => {'hhgttg': hhgttg, 'dcc1': dcc1, 'broken': broken};

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  Map<String, dynamic> _tokens(String user) {
    final a = _jwt('a${access.length + 1}', now() + accessFor.inMilliseconds);
    final r = 'refresh${refresh.length + refreshes + 1}';
    access.add(a);
    refresh.add(r);
    return {
      'user': {
        'id': 'user1',
        'username': user,
        'token': 'legacy-token',
        'accessToken': a,
        'refreshToken': r,
        'mediaProgress': const [],
      },
    };
  }

  String? _bearer(http.Request r) {
    final h = r.headers['Authorization'] ?? r.headers['authorization'];
    if (h != null && h.startsWith('Bearer ')) return h.substring(7);
    return r.url.queryParameters['token'];
  }

  late final MockClient client = MockClient((r) async {
    requests.add('${r.method} ${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''}');
    if (!up) throw const SocketException('connection refused');
    final path = r.url.path;
    if (path == '/status') return json({'app': 'audiobookshelf', 'serverVersion': '2.37.2', 'isInit': true});
    if (path == '/login') {
      final b = jsonDecode(r.body) as Map;
      if (b['username'] != 'test' || b['password'] != password) return http.Response('Unauthorized', 401);
      signIns++;
      return json(_tokens('test'));
    }
    if (path == '/auth/refresh') {
      final t = r.headers['x-refresh-token'];
      if (t == null || !refresh.remove(t)) return http.Response('Unauthorized', 401);
      refreshes++;
      return json(_tokens('test'));
    }
    if (path == '/logout') {
      final t = r.headers['x-refresh-token'];
      if (t != null) refresh.remove(t);
      return json({'redirect_url': null});
    }
    // Covers are open to all, as on the user's server.
    if (path.startsWith('/api/items/') && path.endsWith('/cover')) {
      covers++;
      return http.Response.bytes([0xFF, 0xD8, 0xFF, 1, 2, 3], 200, headers: {'content-type': 'image/jpeg'});
    }
    final token = _bearer(r);
    if (token == null || !access.contains(token)) return http.Response('Unauthorized', 401);
    // An access token past its time.
    final exp = AbsClient.expiryOf(token);
    if (exp != null && exp <= now()) return http.Response('Unauthorized', 401);
    if (path == '/api/libraries') {
      return json({
        'libraries': [
          {'id': 'books', 'name': 'Audiobooks', 'mediaType': 'book'},
          {'id': 'pods', 'name': 'Podcasts', 'mediaType': 'podcast'},
        ],
      });
    }
    if (path == '/api/libraries/books/items') {
      final q = r.url.queryParameters;
      final limit = int.parse(q['limit'] ?? '100'), page = int.parse(q['page'] ?? '0');
      final all = [
        for (final x in full.values) {'id': x['id'], 'updatedAt': x['updatedAt'], 'mediaType': 'book', 'media': {'metadata': x['media']['metadata']}},
      ];
      return json({'results': all.skip(page * limit).take(limit).toList(), 'total': all.length, 'limit': limit, 'page': page});
    }
    if (path == '/api/items/batch/get') {
      if (!batchRoute) return http.Response('Not found', 404);
      batches++;
      final ids = ((jsonDecode(r.body) as Map)['libraryItemIds'] as List).cast<String>();
      return json({'libraryItems': [for (final id in ids) ?full[id]]});
    }
    if (RegExp(r'^/api/items/[^/]+$').hasMatch(path)) {
      final x = full[path.split('/').last];
      return x == null ? http.Response('Not found', 404) : json(x);
    }
    if (path == '/api/me') {
      return json({'id': 'user1', 'mediaProgress': progress.values.toList()});
    }
    if (path.startsWith('/api/me/progress/') && r.method == 'PATCH') {
      final id = path.split('/').last;
      final b = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
      patches.add({'id': id, ...b});
      progress[id] = {'libraryItemId': id, 'episodeId': null, ...b, 'lastUpdate': now()};
      return http.Response('OK', 200);
    }
    if (path.contains('/file/')) {
      return http.Response.bytes(List.filled(100, 1), 200, headers: {'content-type': 'audio/mp4'});
    }
    return http.Response('Not found', 404);
  });
}

void main() {
  group('reading an item', () {
    test('one .m4b with chapters: one book file, its details and its chapters', () {
      final made = bookFromAbs(FakeAbs().hhgttg, serverKey: 's1')!;
      expect(made.itemId, 'hhgttg');
      expect(made.hasCover, isTrue);
      expect(made.ext, {'281474977132575': 'm4b'});
      final t = made.tracks.single;
      expect(t.id, 'abs:s1:hhgttg:281474977132575');
      expect(t.title, 'Hitchhiker\'s Guide to the Galaxy');
      expect(t.album, 'Hitchhiker\'s Guide to the Galaxy');
      expect(t.artist, 'Douglas Adams');
      expect(t.narrator, 'Stephen Fry');
      expect(t.series, 'The Hitchhiker\'s Guide to the Galaxy');
      expect(t.seriesIndex, 1);
      expect(t.year, 2012);
      expect(t.description, contains('The comedy sci-fi classic.'));
      expect(t.description, isNot(contains('<')));
      expect(t.duration, const Duration(milliseconds: 21101691));
      expect(t.chapters.map((c) => c.title), ['Introduction', 'Chapter 1', 'Chapter 2']);
      expect(t.chapters[1].start, const Duration(milliseconds: 291290));
      expect(t.path, isNull);
      expect(t.isLocal, isFalse);
    });

    test('several files: in the server\'s order, left-out ones skipped, the series from its name', () {
      final made = bookFromAbs(FakeAbs().dcc1, serverKey: 's1')!;
      expect(made.tracks.map((t) => t.title), ['Part 01', 'Part 02']);
      expect(made.tracks.map((t) => t.trackNumber), [1, 2]);
      expect(made.tracks.first.series, 'Dungeon Crawler Carl');
      expect(made.tracks.first.seriesIndex, 1);
      expect(made.tracks.first.artist, 'Matt Dinniman');
      expect(made.tracks.first.narrator, 'Jeff Hays');
      // A chapter per file: the files are the chapters.
      expect(made.tracks.every((t) => t.chapters.isEmpty), isTrue);
      expect(made.hasCover, isFalse);
      expect(bookFromAbs(FakeAbs().broken, serverKey: 's1'), isNull);
    });

    test('ids', () {
      expect(remoteBookParts('abs:s1:item:123'), (server: 's1', item: 'item', ino: '123'));
      expect(remoteBookParts('server:123'), isNull);
      expect(remoteBookKey('abs:s1:item:123'), 'abs:s1:item');
      expect(remoteBookId('s1', 'item'), 'book:abs:s1:item');
    });
  });

  group('the client', () {
    test('signs in for an access and a refresh token, renews them, and keeps the token out of errors', () async {
      final server = FakeAbs();
      final c = AbsClient(baseUrl: 'http://192.168.1.81:13378/', httpClient: server.client);
      final r = await c.signIn('test', 'sesame');
      expect(r.userId, 'user1');
      expect(r.refreshToken, 'refresh1');
      expect(r.expiresMs, isNotNull);
      expect(r.expiresMs! - DateTime.now().millisecondsSinceEpoch, closeTo(3600 * 1000, 5000));
      expect(c.mediaHeaders['Authorization'], 'Bearer ${r.accessToken}');
      expect((await c.libraries()).where((l) => l.holdsBooks).map((l) => l.name), ['Audiobooks']);
      final again = await c.refresh(r.refreshToken!);
      expect(again.refreshToken, isNot(r.refreshToken));
      await expectLater(c.refresh(r.refreshToken!), throwsA(isA<AbsException>())); // spent
      final stream = c.streamUri('hhgttg', '1').toString();
      expect(stream, contains('token=${again.accessToken}'));
      expect(hideSecrets('Failed to open $stream'), isNot(contains(again.accessToken)));
      expect(c.downloadUri('hhgttg', '1').toString(), isNot(contains('token')));
      c.close();
    });

    test('a wrong password says so', () async {
      final c = AbsClient(baseUrl: 'http://x:13378', httpClient: FakeAbs().client);
      await expectLater(
        c.signIn('test', 'nope'),
        throwsA(isA<AbsException>().having((e) => e.message, 'message', contains('user name or password'))),
      );
    });

    test('items a page at a time; full details in batches, one by one without the batch route', () async {
      final server = FakeAbs();
      final c = AbsClient(baseUrl: 'http://x:13378', httpClient: server.client);
      await c.signIn('test', 'sesame');
      final pages = <(int, int)>[];
      final brief = await c.items('books', onProgress: (d, t) => pages.add((d, t)));
      expect(brief.map((x) => x['id']), ['hhgttg', 'dcc1', 'broken']);
      expect(server.requests.any((r) => r.contains('minified=1')), isTrue);
      expect((await c.fullItems(['hhgttg', 'dcc1'])).map((x) => x['id']), ['hhgttg', 'dcc1']);
      expect(server.batches, 1);
      server.batchRoute = false;
      expect((await c.fullItems(['dcc1'])).single['media'], isNotNull);
      expect(server.requests.last, 'GET /api/items/dcc1?expanded=1');
      expect((await c.progress()).single.currentTime, 2000);
    });
  });

  group('the Books tab', () {
    late Directory dir;
    late Storage storage;
    late MemorySecretStore secrets;
    late LibraryModel lib;
    late ListeningModel listening;
    late ServersModel servers;
    late FakeAbs server;
    late ServerBooksModel model;
    late ServerEntry entry;
    var clock = 1793600000000;

    Future<ServerBooksModel> makeModel() async {
      final m = ServerBooksModel(
        storage: storage,
        servers: servers,
        library: lib,
        listening: listening,
        secrets: secrets,
        httpClient: () => server.client,
      )..now = () => clock;
      await m.load();
      return m;
    }

    setUp(() async {
      clock = 1793600000000;
      dir = Directory.systemTemp.createTempSync('hometunes_abs');
      storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      secrets = MemorySecretStore();
      lib = LibraryModel(storage, secrets: secrets);
      listening = ListeningModel(storage)..now = () => clock;
      servers = ServersModel(storage, lib);
      server = FakeAbs()..now = () => clock;
      entry = await servers.add(
        type: ServerType.audiobookshelf,
        name: 'Shelf',
        url: 'http://192.168.1.81:13378',
        username: 'test',
        password: 'sesame',
        uses: {MediaKind.audiobooks},
      );
      model = await makeModel();
    });

    tearDown(() async {
      model.dispose();
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

    test('Audiobookshelf plays audiobooks now', () {
      expect(ServerType.audiobookshelf.playsKind(MediaKind.audiobooks), isTrue);
    });

    test('a sync brings the server\'s books in, with chapters, covers and the server\'s place', () async {
      await model.sync(entry);
      expect(lib.books.map((b) => b.title), ['Dungeon Crawler Carl', 'Hitchhiker\'s Guide to the Galaxy']);
      final h = lib.bookById(remoteBookId(entry.id, 'hhgttg'))!;
      expect(h.author, 'Douglas Adams');
      expect(h.narrator, 'Stephen Fry');
      expect(h.series, 'The Hitchhiker\'s Guide to the Galaxy');
      expect(h.seriesIndex, 1);
      expect(h.chapters.map((c) => c.title), ['Introduction', 'Chapter 1', 'Chapter 2']);
      final d = lib.bookById(remoteBookId(entry.id, 'dcc1'))!;
      expect(d.parts.length, 2);
      expect(d.chapters.length, 2);
      // Not music; streamed.
      expect(lib.tracks, isEmpty);
      expect(sourcesOfTracks(h.parts), {MediaSource.streamed});
      expect(lib.bookRules.why(h.parts.single).$2, contains('Audiobookshelf'));
      // The podcasts library isn't read.
      expect(server.requests.any((r) => r.contains('/api/libraries/pods')), isFalse);
      // The server's place: 2000 s in.
      final place = listening.progressFor(h)!;
      expect(place.position, const Duration(seconds: 2000));
      expect(listening.stateOf(h).name, 'inProgress');
      expect(model.statusFor(entry), contains('2 books'));
      expect(model.okFor(entry), isTrue);
      // The cover, downloaded into HomeTunes' pictures.
      await until(() => lib.bookById(h.id)?.parts.single.art != null);
      final art = lib.bookById(h.id)!.parts.single.art!;
      expect(File(art).existsSync(), isTrue);
      expect(p.isWithin(storage.artDir, art), isTrue);
      expect(lib.coverSource(lib.bookById(h.id)!.parts.single)?.file, art);
    });

    test('nothing secret in the files: the refresh token is in protected storage', () async {
      await model.sync(entry);
      final saved = jsonEncode(await storage.read(ServerBooksModel.fileName));
      expect(saved, isNot(contains('refresh')));
      expect(saved, isNot(contains('sesame')));
      for (final a in server.access) {
        expect(saved, isNot(contains(a)));
      }
      expect(await secrets.read(ServerBooksModel.refreshKey(entry)), startsWith('refresh'));
      final libFile = jsonEncode(await storage.read('library.json'));
      expect(libFile, isNot(contains('abs:')));
    });

    test('what was read shows at once next time, and only changed books are read again', () async {
      await model.sync(entry);
      await until(() => server.covers >= 1);
      model.dispose();
      lib.removeServerBookTracks(entry.id);
      expect(lib.books, isEmpty);
      model = await makeModel();
      expect(lib.books.length, 2);
      final before = server.batches;
      server.updated['dcc1'] = 201;
      await model.sync(entry);
      expect(server.batches, before + 1);
      expect(server.requests.where((r) => r.startsWith('POST /api/items/batch/get')).length, 2);
      // A restart renews the sign-in with the refresh token rather than the password.
      expect(server.signIns, 1);
      expect(server.refreshes, 1);
    });

    test('playing a server book opens its file from the server, with a fresh sign-in', () async {
      await model.sync(entry);
      final engine = FakeAudioEngine();
      final player = PlayerModel(lib, listening: listening, engine: engine);
      addTearDown(player.dispose);
      final d = lib.bookById(remoteBookId(entry.id, 'dcc1'))!;
      await player.playBook(d, fromStart: true);
      final uri = engine.items.first.uri;
      expect(uri, startsWith('http://192.168.1.81:13378/api/items/dcc1/file/11?token='));
      // An hour later the sign-in has run out: opening the next file renews it first.
      clock += const Duration(minutes: 55).inMilliseconds;
      await player.goToPart(1, Duration.zero);
      final next = engine.items.first.uri;
      expect(next, contains('/api/items/dcc1/file/22?token='));
      expect(server.refreshes, 1);
      final token = Uri.parse(next).queryParameters['token']!;
      expect(AbsClient.expiryOf(token)! > clock + const Duration(minutes: 30).inMilliseconds, isTrue);
    });

    test('listening here goes to the server; a place that couldn\'t be sent goes at the next sync', () async {
      await model.sync(entry);
      final h = lib.bookById(remoteBookId(entry.id, 'hhgttg'))!;
      clock += 60000;
      await listening.record(h, h.parts.single.id, const Duration(seconds: 2500));
      await until(() => server.patches.isNotEmpty);
      expect(server.patches.last['id'], 'hhgttg');
      expect(server.patches.last['currentTime'], 2500);
      expect(server.patches.last['isFinished'], false);
      // A few seconds on: not sent yet (every 15 s at most)…
      clock += 5000;
      await listening.record(h, h.parts.single.id, const Duration(seconds: 2505));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.patches.length, 1);
      // …but finishing is sent at once.
      await listening.setFinished(h, true);
      await until(() => server.patches.length == 2);
      expect(server.patches.last['isFinished'], true);

      // The server is off: the place waits, and goes at the next sync.
      server.up = false;
      clock += 60000;
      await listening.setFinished(h, false);
      for (var i = 0; i < 200 && !jsonEncode(await storage.read(ServerBooksModel.fileName)).contains('pending'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(jsonEncode(await storage.read(ServerBooksModel.fileName)), contains('pending'));
      server.up = true;
      clock += 60000;
      await model.sync(entry);
      expect(server.patches.last['isFinished'], false);
      expect(server.patches.last['currentTime'], 0);
      // …and the server's older place didn't bring the book back.
      expect(listening.progressFor(lib.bookById(h.id)!), isNull);
    });

    test('a place from another device that\'s newer wins; an older one doesn\'t', () async {
      await model.sync(entry);
      final h = lib.bookById(remoteBookId(entry.id, 'hhgttg'))!;
      clock += 60000;
      await listening.record(h, h.parts.single.id, const Duration(seconds: 3000));
      await until(() => server.patches.isNotEmpty);
      // Elsewhere, later: 4000 s.
      server.progress['hhgttg'] = {
        'libraryItemId': 'hhgttg',
        'currentTime': 4000.0,
        'duration': 21101.69,
        'isFinished': false,
        'lastUpdate': clock + 1000,
      };
      await model.sync(entry);
      expect(listening.progressFor(lib.bookById(h.id)!)!.position, const Duration(seconds: 4000));
      // Older than what's here: kept.
      clock += 60000;
      await listening.record(lib.bookById(h.id)!, h.parts.single.id, const Duration(seconds: 4100));
      server.progress['hhgttg'] = {...server.progress['hhgttg']!, 'currentTime': 10.0, 'lastUpdate': clock - 30000};
      await model.sync(entry);
      expect(listening.progressFor(lib.bookById(h.id)!)!.position, const Duration(seconds: 4100));
    });

    test('a place in the second file of a book is sent as time through the whole book', () async {
      await model.sync(entry);
      final d = lib.bookById(remoteBookId(entry.id, 'dcc1'))!;
      await listening.record(d, d.parts[1].id, const Duration(seconds: 30));
      await until(() => server.patches.isNotEmpty);
      expect(server.patches.last['currentTime'], 630);
      expect(server.patches.last['duration'], 1200);
      // And back: 900 s through is 300 s into the second file.
      expect(listening.applyServerPlace(d, offset: const Duration(seconds: 900), finished: false, updatedMs: clock + 99999), isTrue);
      expect(listening.progressFor(d)!.partId, d.parts[1].id);
      expect(listening.progressFor(d)!.position, const Duration(seconds: 300));
    });

    test('downloads take the original file with the sign-in in a header', () async {
      await model.sync(entry);
      final t = lib.bookById(remoteBookId(entry.id, 'dcc1'))!.parts.first;
      final r = await model.downloadRequest(t);
      expect(r!.url, 'http://192.168.1.81:13378/api/items/dcc1/file/11/download');
      expect(r.headers['Authorization'], startsWith('Bearer '));
      expect(r.ext, 'mp3');
      expect(const DownloadQuality.original().isOriginal, isTrue);
    });

    test('switched off, or removed: its books leave the Books tab', () async {
      await model.sync(entry);
      expect(lib.books.length, 2);
      await servers.setUse(entry, MediaKind.audiobooks, false);
      await until(() => lib.books.isEmpty);
      expect(model.statusFor(servers.byId(entry.id)!), contains('Switch it on'));
      await servers.setUse(servers.byId(entry.id)!, MediaKind.audiobooks, true);
      await until(() => lib.books.length == 2);
      await servers.remove(servers.byId(entry.id)!);
      await until(() => lib.books.isEmpty);
      expect(await secrets.read(ServerBooksModel.refreshKey(entry)), isNull);
      // Signed out on the server too.
      expect(server.requests.any((r) => r.startsWith('POST /logout')), isTrue);
    });

    test('a sign-in the server stopped accepting: signs in again once with the password', () async {
      await model.sync(entry);
      server.access.clear();
      server.refresh.clear();
      await model.sync(entry);
      expect(server.signIns, 2);
      expect(model.okFor(entry), isTrue);
    });

    testWidgets('Settings › Servers: the card says how it went; Sync now, Libraries… and Sign out', (tester) async {
      await tester.runAsync(() => model.sync(entry));
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ...libraryProviders(lib),
          ChangeNotifierProvider.value(value: servers),
          ChangeNotifierProvider<ServerBooksModel>.value(value: model),
        ],
        child: const MaterialApp(home: Scaffold(body: ServerSettings())),
      ));
      await tester.pumpAndSettle();
      final card = find.byKey(ValueKey('server-${entry.id}-audiobooks'));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining('2 books')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Coming later')), findsNothing);
      await tester.tap(find.byKey(ValueKey('server-menu-${entry.id}-audiobooks')));
      await tester.pumpAndSettle();
      expect(find.text('Sync now'), findsOneWidget);
      expect(find.text('Sign out on this device'), findsOneWidget);
      await tester.tap(find.text('Libraries…'));
      await tester.pumpAndSettle();
      expect(find.text('Shelf: libraries'), findsOneWidget);
      expect(find.text('Audiobooks'), findsWidgets);
      expect(find.text('Podcasts'), findsNothing); // only book libraries
      expect(find.textContaining('out of the Books tab'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });

    test('a wrong password shows on the card', () async {
      final wrong = await servers.add(
        type: ServerType.audiobookshelf,
        name: 'Other',
        url: 'http://192.168.1.82:13378',
        username: 'test',
        password: 'nope',
        uses: {MediaKind.audiobooks},
      );
      await model.sync(wrong);
      expect(model.okFor(wrong), isFalse);
      expect(model.statusFor(wrong), contains('user name or password'));
    });
  });

  test('Test connection signs in to Audiobookshelf, then out again', () async {
    final server = FakeAbs();
    final ok = await probeServer(ServerType.audiobookshelf, 'http://192.168.1.81:13378',
        username: 'test', password: 'sesame', client: server.client);
    expect(ok.ok, isTrue);
    expect(ok.message, contains('Signed in to an Audiobookshelf server, version 2.37.2'));
    expect(server.requests.any((r) => r.startsWith('POST /logout')), isTrue);
    final bad = await probeServer(ServerType.audiobookshelf, 'http://192.168.1.81:13378',
        username: 'test', password: 'nope', client: server.client);
    expect(bad.ok, isFalse);
    expect(bad.message, contains('couldn\'t sign in'));
  });
}
