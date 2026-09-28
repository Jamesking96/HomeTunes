// Tests for release 0.1.21 (security review of 28 Sep 2026, see claude/06_SECURITY_REVIEW.md):
//  #3 paths from a restored backup are checked before HomeTunes opens, reads or writes them;
//  #2 server covers reach the media controls as downloaded files, never as the server address;
//  #4 plain http to a server on the internet needs the user's consent;
//  #7 size limits for lyrics files, backups and the tag parser.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// The tag parser's Buffer isn't exported; its size check is tested directly.
// ignore: implementation_imports
import 'package:audio_metadata_reader/src/utils/buffer.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/track_edit.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/local_lyrics.dart';
import 'package:hometunes/services/path_safety.dart';
import 'package:hometunes/services/secret_store.dart';
import 'package:hometunes/services/server_art_cache.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/subsonic_client.dart';
import 'package:hometunes/services/tag_writer.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'keep_and_backup_test.dart' show local;
import 'metadata_features_test.dart' show silentWav;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Directory music;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_sec');
    music = Directory(p.join(dir.path, 'music'))..createSync();
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('#3 path checks', () {
    test('only real files inside the library folders pass', () {
      final pdf = File(p.join(music.path, 'Book', 'extras.pdf'))
        ..createSync(recursive: true)
        ..writeAsStringSync('%PDF');
      final outside = File(p.join(dir.path, 'outside.pdf'))..writeAsStringSync('%PDF');
      final exe = File(p.join(music.path, 'Book', 'setup.exe'))..writeAsStringSync('MZ');
      final roots = [music.path];
      const ext = {'.pdf', '.epub'};

      expect(isUsableLocalFile(pdf.path, roots: roots, extensions: ext), isTrue);
      expect(isUsableLocalFile(outside.path, roots: roots, extensions: ext), isFalse);
      expect(isUsableLocalFile(exe.path, roots: roots, extensions: ext), isFalse);
      // A trip out of the folder with ".." is seen through.
      expect(isUsableLocalFile(p.join(music.path, 'Book', '..', '..', 'outside.pdf'), roots: roots, extensions: ext), isFalse);
      // A folder isn't a file; a missing file isn't usable; a relative path never is.
      expect(isUsableLocalFile(p.join(music.path, 'Book'), roots: roots), isFalse);
      expect(isUsableLocalFile(p.join(music.path, 'nope.pdf'), roots: roots, extensions: ext), isFalse);
      expect(isUsableLocalFile('Book/extras.pdf', roots: roots, extensions: ext), isFalse);
      // A folder with a similar name doesn't count as inside.
      expect(isInsideAny(p.join('${music.path}2', 'x.pdf'), roots), isFalse);
    });

    test('network paths only pass when a library folder is on that share', () {
      expect(isInsideAny(r'\\evil\share\x.pdf', [music.path]), isFalse);
      expect(isInsideAny('//evil/share/x.pdf', [music.path]), isFalse);
      if (Platform.isWindows) {
        expect(isInsideAny(r'\\nas\music\Book\x.pdf', [r'\\nas\music']), isTrue);
      }
    });

    test('a crafted backup can\'t aim a cover or a companion file anywhere', () async {
      final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      final root = storage.root.path;
      final secret = p.join(dir.path, 'secret.png');
      final json = {
        'format': AppBackup.format,
        'version': AppBackup.version,
        'files': {
          'edits.json': {
            'local:a': {'title': 'A', 'art': secret},
            'local:b': {'title': 'B', 'art': '${AppBackup.appPrefix}art/custom/abc.png'},
            'local:c': {'title': 'C', 'art': '${AppBackup.appPrefix}../../evil.png'},
          },
          'library.json': {
            'local': [
              {
                'id': 'local:x', 'source': 'local', 'title': 'X', 'artist': 'A', 'album': 'Al',
                'albumArtist': 'A', 'durationMs': 0, 'path': p.join(music.path, 'x.mp3'),
                'companions': [r'C:\Windows\System32\calc.exe', p.join(music.path, 'x.pdf'), r'\\evil\share\x.epub'],
              },
            ],
            'remote': [],
            'missing': [],
          },
        },
        'art': {},
      };
      final backup = AppBackup.read(gzip.encode(utf8.encode(jsonEncode(json))));
      await AppBackup.restore(storage, backup, merge: false);

      final edits = await storage.read('edits.json') as Map<String, dynamic>;
      expect((edits['local:a'] as Map).containsKey('art'), isFalse);
      expect((edits['local:b'] as Map)['art'], p.join(root, 'art', 'custom', 'abc.png'));
      expect((edits['local:c'] as Map)['art'], anyOf(isNull, ''));
      final lib = await storage.read('library.json') as Map<String, dynamic>;
      final companions = ((lib['local'] as List).single as Map)['companions'] as List;
      // Only PDFs and EPUBs survive; the EPUB on a share is still refused when opened (above).
      expect(companions, [p.join(music.path, 'x.pdf'), r'\\evil\share\x.epub']);
    });

    test('the tag writer refuses files and covers outside the library', () async {
      final song = File(p.join(music.path, 'a.wav'))..writeAsBytesSync(silentWav());
      final elsewhere = File(p.join(dir.path, 'b.wav'))..writeAsBytesSync(silentWav());
      final picture = File(p.join(dir.path, 'private.png'))..writeAsBytesSync(_png);

      final outsideFile = await writeTagsToFile(elsewhere.path, const TrackEdit(title: 'X'), libraryRoots: [music.path]);
      expect(outsideFile.ok, isFalse);
      expect(elsewhere.readAsBytesSync(), silentWav());

      final fine = await writeTagsToFile(song.path, const TrackEdit(title: 'Y'), libraryRoots: [music.path]);
      expect(fine.ok, isTrue, reason: fine.error);

      // .wav can't hold a cover, so use an MP3 fixture for the cover check.
      final mp3 = File(p.join('test', 'fixtures', 'tagged.mp3')).copySync(p.join(music.path, 'c.mp3'));
      final before = mp3.readAsBytesSync();
      final badCover = await writeTagsToFile(mp3.path, TrackEdit(art: picture.path),
          libraryRoots: [music.path], artRoots: [p.join(dir.path, 'data', 'art')]);
      expect(badCover.ok, isFalse);
      expect(mp3.readAsBytesSync(), before);
    });

    test('songs and covers outside the library folders aren\'t played or shown', () async {
      final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      Directory(storage.artDir).createSync();
      File(p.join(music.path, 'one.wav')).writeAsBytesSync(silentWav());
      final lib = LibraryModel(storage, secrets: MemorySecretStore());
      await lib.addFolder(music.path);
      final inside = lib.tracks.single;
      expect(lib.playableUri(inside), isNotNull);

      final stray = File(p.join(dir.path, 'stray.wav'))..writeAsBytesSync(silentWav());
      final strayTrack = local(stray.path);
      expect(lib.playableUri(strayTrack), isNull);

      final pic = File(p.join(dir.path, 'private.png'))..writeAsBytesSync(_png);
      final withArt = inside.copyWith(art: pic.path);
      expect(lib.artFor(withArt), isNull);
      expect(lib.artUriFor(withArt), isNull);
      final ownArt = File(p.join(storage.artDir, 'x.img'))..writeAsBytesSync(_png);
      expect(lib.artUriFor(inside.copyWith(art: ownArt.path)), Uri.file(ownArt.path));
    });
  });

  group('#2 server covers for the media controls', () {
    const config = ServerConfig(url: 'http://music.test', username: 'me', password: 'sesame');

    test('are downloaded once and handed over as a file', () async {
      var calls = 0;
      final mock = MockClient((req) async {
        calls++;
        expect(req.url.queryParameters['id'], 'al-1');
        return http.Response.bytes(_png, 200, headers: {'content-type': 'image/png'});
      });
      final cache = ServerArtCache(p.join(dir.path, 'art', 'server'), SubsonicClient(config), httpClient: mock);
      expect(cache.cachedFile('al-1'), isNull);
      final got = await Future.wait([cache.fetch('al-1'), cache.fetch('al-1')]);
      expect(calls, 1);
      expect(got[0], got[1]);
      expect(File(got[0]!).readAsBytesSync(), _png);
      expect(cache.cachedFile('al-1'), got[0]);
      expect(got[0], isNot(contains('sesame')));
      expect(await cache.fetch('al-1'), got[0]);
      expect(calls, 1);
    });

    test('a reply that isn\'t a picture is not kept, and isn\'t asked for again straight away', () async {
      var calls = 0;
      final mock = MockClient((req) async {
        calls++;
        return http.Response('{"subsonic-response":{"status":"failed"}}', 200, headers: {'content-type': 'application/json'});
      });
      final cache = ServerArtCache(p.join(dir.path, 'art', 'server'), SubsonicClient(config), httpClient: mock);
      expect(await cache.fetch('al-2'), isNull);
      expect(await cache.fetch('al-2'), isNull);
      expect(calls, 1);
      expect(Directory(p.join(dir.path, 'art', 'server')).existsSync() &&
          Directory(p.join(dir.path, 'art', 'server')).listSync().isNotEmpty, isFalse);
    });

    test('the media controls never get the server address (login token)', () async {
      final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      Directory(storage.artDir).createSync();
      // Port 9 on this computer refuses at once, so nothing is downloaded.
      await storage.write('settings.json', {
        'folders': [],
        'server': {'url': 'http://127.0.0.1:9', 'username': 'me', 'password': 'sesame'},
        'serverEnabled': true,
      });
      final lib = LibraryModel(storage, secrets: MemorySecretStore());
      await lib.load();
      const t = Track(
        id: 'server:1', source: TrackSource.server, title: 'S', artist: 'A', album: 'Al', albumArtist: 'A',
        remoteId: '1', art: 'al-1',
      );
      final uri = lib.artUriFor(t);
      expect(uri, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(lib.artUriFor(t)?.scheme, anyOf(isNull, 'file'));
    });

    test('backups leave downloaded server covers out', () async {
      final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      File(p.join(storage.artDir, 'server', 'a.img'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(_png);
      File(p.join(storage.artDir, 'custom', 'b.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(_png);
      final b = AppBackup.read(await AppBackup.create(storage));
      expect(b.art.keys, ['art/custom/b.png']);
    });
  });

  group('#4 plain http to the internet', () {
    test('an internet server that only answers over http needs consent', () async {
      final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      final lib = LibraryModel(storage, secrets: MemorySecretStore());
      await lib.load();
      // ".invalid" never resolves, so https fails as "not reachable".
      final r = await lib.connectServer(const ServerConfig(url: 'hometunes-test.invalid', username: 'me', password: 'x'));
      expect(r, LibraryModel.httpConsentNeeded);
      expect(lib.server.url, isEmpty);
      // With consent it tries http (which also fails here) and reports that instead.
      final again = await lib.connectServer(const ServerConfig(url: 'hometunes-test.invalid', username: 'me', password: 'x'),
          allowPlainHttp: true);
      expect(again, isNot(LibraryModel.httpConsentNeeded));
      expect(again, isNotNull);
    });

    test('home-network addresses still fall back to http without asking', () async {
      final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      final lib = LibraryModel(storage, secrets: MemorySecretStore());
      await lib.load();
      final r = await lib.connectServer(const ServerConfig(url: '127.0.0.1:9', username: 'me', password: 'x'));
      expect(r, isNot(LibraryModel.httpConsentNeeded));
      expect(r, isNotNull); // nothing is listening there
    });

    test('the answer is remembered in settings', () async {
      final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      await storage.write('settings.json', {'folders': [], 'httpAllowedHost': 'music.example.org'});
      final lib = LibraryModel(storage, secrets: MemorySecretStore());
      await lib.load();
      expect(lib.httpAllowedHost, 'music.example.org');
    });
  });

  group('#7 size limits', () {
    test('a huge .lrc file is ignored', () {
      final song = p.join(music.path, 'a.mp3');
      File(song).writeAsBytesSync([0]);
      File(p.join(music.path, 'a.lrc')).writeAsStringSync('[00:01.00]x\n' * 200000); // ~2.4 MB
      expect(readLocalLyricsNow(song).lrc, isNull);
      File(p.join(music.path, 'a.lrc')).writeAsStringSync('[00:01.00]hello');
      expect(readLocalLyricsNow(song).lrc, '[00:01.00]hello');
    });

    test('a backup that unpacks to far too much is refused', () {
      // 64 MB of zeros packs down to about 64 KB. The real limit is 512 MB; a small one keeps
      // the test quick, and the unpacking stops as soon as it's passed.
      final sink = _Collect();
      final enc = gzip.encoder.startChunkedConversion(sink);
      final zeros = Uint8List(1 << 20);
      for (var i = 0; i < 64; i++) {
        enc.add(zeros);
      }
      enc.close();
      final bomb = sink.bytes.takeBytes();
      expect(bomb.length, lessThan(1 << 20));
      expect(() => AppBackup.read(bomb, maxUnpacked: 8 << 20), throwsFormatException);
      expect(AppBackup.maxUnpackedBytes, 512 << 20);
    });

    test('the tag parser won\'t allocate for a block bigger than the file', () {
      final f = File(p.join(dir.path, 'x.bin'))..writeAsBytesSync(List.filled(100, 7));
      final raf = f.openSync();
      addTearDown(raf.closeSync);
      final b = Buffer(randomAccessFile: raf);
      expect(() => b.read(0x7FFFFFFF), throwsA(isA<MetadataParserException>()));
      expect(() => b.read(-1), throwsA(isA<MetadataParserException>()));
      // A little past the end still reads (the rest is zeros), as damaged files need.
      final raf2 = f.openSync();
      addTearDown(raf2.closeSync);
      expect(Buffer(randomAccessFile: raf2).read(20000).length, 20000);
    });
  });

  test('#10 the in-memory secret store is only for tests', () {
    expect(SecretStore.forPlatform(), isA<MemorySecretStore>());
  });
}

/// A 1×1 PNG.
final _png = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));

class _Collect implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> data) => bytes.add(data);
  @override
  void close() {}
}
