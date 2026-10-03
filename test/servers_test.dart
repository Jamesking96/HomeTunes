// 0.1.46: Settings › Servers as a framework for several servers per kind (music, audiobooks,
// videos): the server list (ServersModel), the main music server shown in it, testing a server
// (server_probe.dart, no network: a fake http client), and the page itself.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/secret_store.dart';
import 'package:hometunes/services/server_probe.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/servers_model.dart';
import 'package:hometunes/ui/screens/settings/server_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late Storage storage;
  late MemorySecretStore secrets;
  late LibraryModel lib;
  late ServersModel servers;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_servers');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    secrets = MemorySecretStore();
    lib = LibraryModel(storage, secrets: secrets);
    servers = ServersModel(storage, lib);
    var t = 1000;
    servers.now = () => t++;
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    dir.deleteSync(recursive: true);
  });

  test('a server is saved without its password, which goes to protected storage', () async {
    final s = await servers.add(
      type: ServerType.jellyfin,
      name: '',
      url: 'http://192.168.1.20:8096',
      username: 'me',
      password: 'sesame',
      uses: {MediaKind.videos, MediaKind.music},
    );
    expect(s.name, '192.168.1.20'); // a name from the address when none is given
    final saved = jsonEncode(await storage.read(ServersModel.file));
    expect(saved, isNot(contains('sesame')));
    expect(await secrets.read(SecretStore.serverPasswordKey(s.url, 'me')), 'sesame');
    expect(await servers.passwordOf(s), 'sesame');

    // Read back.
    final again = ServersModel(storage, lib);
    await again.load();
    expect(again.all.single.type, ServerType.jellyfin);
    expect(again.all.single.uses, {MediaKind.videos, MediaKind.music});

    // It shows in every section whose kind it can hold, used or not.
    expect(servers.serversFor(MediaKind.videos).single.id, s.id);
    expect(servers.serversFor(MediaKind.audiobooks).single.id, s.id);

    // Switch audiobooks on, music off.
    await servers.setUse(servers.byId(s.id)!, MediaKind.audiobooks, true);
    await servers.setUse(servers.byId(s.id)!, MediaKind.music, false);
    expect(servers.byId(s.id)!.uses, {MediaKind.videos, MediaKind.audiobooks});

    // A kind it can't hold is never kept (Audiobookshelf: audiobooks only).
    final abs = await servers.add(
      type: ServerType.audiobookshelf,
      name: 'Books',
      url: 'abs.local',
      uses: {MediaKind.videos, MediaKind.audiobooks},
    );
    expect(abs.uses, {MediaKind.audiobooks});
    expect(servers.serversFor(MediaKind.videos).map((x) => x.id), [s.id]);

    // Removing forgets its password.
    await servers.remove(servers.byId(s.id)!);
    expect(await secrets.read(SecretStore.serverPasswordKey(s.url, 'me')), isNull);
    expect(servers.all.map((x) => x.name), ['Books']);
  });

  test('changing a server\'s address moves its password; bad entries in the file are skipped', () async {
    final s = await servers.add(
      type: ServerType.plex,
      name: 'Plex',
      url: 'http://a:32400',
      username: 'u',
      password: 'pw',
      uses: {MediaKind.videos},
    );
    await servers.update(s.copyWith(url: 'http://b:32400'));
    expect(await secrets.read(SecretStore.serverPasswordKey('http://a:32400', 'u')), isNull);
    expect(await secrets.read(SecretStore.serverPasswordKey('http://b:32400', 'u')), 'pw');

    expect(ServerEntry.fromJson({'id': 'x', 'type': 'nonsense', 'url': 'u'}), isNull);
    expect(ServerEntry.fromJson({'id': ServersModel.mainId, 'type': 'plex', 'url': 'u'}), isNull);
    expect(ServerEntry.fromJson('nope'), isNull);
  });

  test('the main music server is shown in the list and follows LibraryModel\'s switches', () async {
    await storage.write('settings.json', {
      'serverEnabled': true,
      'server': {'url': 'http://music.test', 'username': 'me', 'password': 'p'},
    });
    await lib.load();
    final main = servers.main!;
    expect(main.isMain, isTrue);
    expect(main.type, ServerType.subsonic);
    expect(main.name, 'music.test');
    expect(main.uses, {MediaKind.music, MediaKind.audiobooks});
    expect(servers.serversFor(MediaKind.music).first.isMain, isTrue);
    expect(servers.serversFor(MediaKind.videos), isEmpty); // Subsonic has no videos

    await servers.setUse(main, MediaKind.audiobooks, false);
    expect(lib.serverBooks, isFalse);
    expect(servers.main!.uses, {MediaKind.music});
    await servers.renameMain('Navidrome');
    expect(servers.main!.name, 'Navidrome');

    // Another server's password never overwrites the main one's.
    await servers.add(
      type: ServerType.subsonic,
      name: 'Copy',
      url: 'http://music.test',
      username: 'me',
      password: 'other',
      uses: {MediaKind.music},
    );
    expect(lib.server.password, 'p');
  });

  test('a test result is kept on the server', () async {
    servers.probe = (type, url, {username = '', password = ''}) async =>
        const ProbeResult(true, 'Found a Plex server.');
    final s = await servers.add(type: ServerType.plex, name: 'P', url: 'p.local', uses: {MediaKind.videos});
    final r = await servers.test(s);
    expect(r.ok, isTrue);
    expect(servers.byId(s.id)!.lastCheck, 'Found a Plex server.');
    expect(servers.byId(s.id)!.reachable, isTrue);
  });

  group('testing a server', () {
    MockClient answering(Map<String, (int, String)> replies) => MockClient((req) async {
      final r = replies[req.url.path];
      return r == null ? http.Response('nope', 404) : http.Response(r.$2, r.$1);
    });

    test('addresses: as typed, else https then http', () {
      expect(candidateUrls('https://x/'), ['https://x']);
      expect(candidateUrls('x:8096'), ['https://x:8096', 'http://x:8096']);
      expect(candidateUrls('  '), isEmpty);
    });

    test('Jellyfin, Emby, Plex, Audiobookshelf and HomeTunes are recognised; no sign-in is sent', () async {
      final seen = <Uri>[];
      final jellyfin = MockClient((req) async {
        seen.add(req.url);
        return http.Response(
          jsonEncode({'ServerName': 'Den', 'Version': '10.9.1', 'ProductName': 'Jellyfin Server', 'Id': 'a'}),
          200,
        );
      });
      final r = await probeServer(
        ServerType.jellyfin,
        'http://den:8096',
        username: 'me',
        password: 'secret',
        client: jellyfin,
      );
      expect(r.ok, isTrue);
      expect(r.message, contains('Jellyfin server called "Den", version 10.9.1'));
      expect(r.message, contains('can\'t play from Jellyfin yet'));
      expect(seen.single.toString(), 'http://den:8096/System/Info/Public');
      expect(seen.single.toString(), isNot(contains('secret')));

      // An Emby server set up as Jellyfin says so.
      final emby = answering({
        '/System/Info/Public': (200, jsonEncode({'ServerName': 'E', 'ProductName': 'Emby Server'})),
      });
      expect((await probeServer(ServerType.jellyfin, 'http://e', client: emby)).message, contains('choose Emby'));

      final plex = answering({'/identity': (200, '<MediaContainer size="0" machineIdentifier="x" version="1.40.1"/>')});
      expect(
        (await probeServer(ServerType.plex, 'http://p:32400', client: plex)).message,
        contains('Plex server, version 1.40.1'),
      );

      final abs = answering({
        '/status': (200, jsonEncode({'isInit': true, 'serverVersion': '2.12.3'})),
      });
      expect(
        (await probeServer(ServerType.audiobookshelf, 'http://a', client: abs)).message,
        contains('Audiobookshelf server, version 2.12.3'),
      );

      final ours = answering({
        '/api/info': (200, jsonEncode({'app': 'HomeTunes', 'version': '0.1.0'})),
      });
      final h = await probeServer(ServerType.hometunes, 'http://h', client: ours);
      expect(h.ok, isTrue);
      expect(h.message, contains('HomeTunes server, version 0.1.0'));

      // Something else at that address.
      final other = answering({'/': (200, 'hello')});
      final no = await probeServer(ServerType.plex, 'http://x', client: other);
      expect(no.ok, isFalse);
      expect(no.message, contains('doesn\'t look like a Plex server'));
    });

    test('a Subsonic server is signed in to (and never over plain http to the internet)', () async {
      final ok = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'subsonic-response': {'status': 'ok'},
          }),
          200,
        ),
      );
      final r = await probeServer(
        ServerType.subsonic,
        'http://192.168.1.5:4533',
        username: 'me',
        password: 'p',
        client: ok,
      );
      expect(r.ok, isTrue);
      expect(r.message, contains('Signed in'));

      final urls = <String>[];
      final https = MockClient((req) async {
        urls.add(req.url.scheme);
        throw const SocketException('no https');
      });
      final internet = await probeServer(
        ServerType.subsonic,
        'music.example.com',
        username: 'me',
        password: 'p',
        client: https,
      );
      expect(internet.ok, isFalse);
      expect(urls, ['https']); // plain http to the internet wasn't tried with the sign-in
      expect((await probeServer(ServerType.subsonic, 'http://x', client: ok)).message, contains('user name'));
    });
  });

  testWidgets('the Servers page: a section per kind, and adding a server', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: servers),
        ],
        child: const MaterialApp(home: Scaffold(body: ServerSettings())),
      ),
    );
    for (final k in ['MUSIC', 'AUDIOBOOKS', 'VIDEOS']) {
      // headings are shown in capitals
      expect(find.text(k), findsOneWidget);
    }
    expect(find.text('No video servers yet.'), findsOneWidget);
    expect(find.text('KINDS OF SERVER'), findsOneWidget);

    // Add a Jellyfin server from the Videos section.
    await tester.tap(find.byKey(const ValueKey('add-videos-server')));
    await tester.pumpAndSettle();
    expect(find.text('Add a server'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('server-name')), 'Den');
    await tester.enterText(find.byKey(const ValueKey('server-url')), 'http://192.168.1.20:8096');
    await tester.enterText(find.byKey(const ValueKey('server-user')), 'me');
    await tester.enterText(find.byKey(const ValueKey('server-password')), 'pw');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('server-save')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    final added = servers.all.single;
    expect(added.type, ServerType.jellyfin); // the first kind that holds videos
    expect(added.uses, {MediaKind.videos});
    expect(find.text('Den'), findsNWidgets(3)); // in Music, Audiobooks and Videos
    for (final k in MediaKind.values) {
      final card = find.byKey(ValueKey('server-${added.id}-${k.name}'));
      expect(
        find.descendant(of: card, matching: find.text('Coming later')),
        findsOneWidget,
        reason: k.name,
      );
    }
    final videoSwitch = tester.widget<Switch>(find.byKey(ValueKey('use-${added.id}-videos')));
    expect(videoSwitch.value, isTrue);
    final musicSwitch = tester.widget<Switch>(find.byKey(ValueKey('use-${added.id}-music')));
    expect(musicSwitch.value, isFalse);
  });
}
