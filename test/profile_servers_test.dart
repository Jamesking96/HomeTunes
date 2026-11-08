// Profiles, phase 3: each person's own server sign-in and what it reads. The servers set up for
// the device are shared; each profile signs in with its own user name (the user, 8 Nov: only he
// has users so far), a profile that hasn't signed in sees nothing from a server, and a profile
// can add servers just for itself. A switch never signs the last person out.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/secret_store.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/profiles_model.dart';
import 'package:hometunes/state/server_books.dart';
import 'package:hometunes/state/server_videos.dart';
import 'package:hometunes/state/servers_model.dart';
import 'package:hometunes/state/settings/settings_groups.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:path/path.dart' as p;

import 'jellyfin_test.dart' show FakeJellyfin;

/// main.dart's host, for the server side (the other personal models are in profiles_model_test).
class ServersHost implements ProfileHost {
  ServersHost(this.lib, this.listening, this.videos, this.servers, this.serverVideos, this.serverBooks);
  final LibraryModel lib;
  final ListeningModel listening;
  final VideoLibraryModel videos;
  final ServersModel servers;
  final ServerVideosModel serverVideos;
  final ServerBooksModel serverBooks;

  @override
  Future<void> saveEverything() => videos.flushPendingSaves();

  @override
  Map<String, dynamic> personalSettings() => lib.settings.toJsonFor(SettingScope.profile);

  @override
  Future<void> use(Storage personal, {required bool split}) async {
    await lib.usePersonal(personal, split: split);
    await listening.useStorage(personal);
    await videos.usePersonal(personal);
    await servers.usePersonal(personal, split: split);
    serverVideos.knowServers();
    serverBooks.knowServers();
    await serverVideos.useStorage(personal);
    await serverBooks.useStorage(personal);
    servers.announce();
  }

  @override
  Future<void> saveSettings() => lib.saveSettingsNow();

  @override
  Map<String, dynamic> currentSignIns() => servers.currentSignIns();
}

void main() {
  late Directory dir;
  late Storage storage;
  late MemorySecretStore secrets;
  late FakeJellyfin jellyfin;
  late ProfilesModel profiles;
  late ServersHost host;
  late ServerEntry den;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('hometunes_profile_servers');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    secrets = MemorySecretStore();
    jellyfin = FakeJellyfin();
    profiles = ProfilesModel(storage);
    await profiles.load();
    final mine = profiles.session.storage;
    final lib = LibraryModel(storage, secrets: secrets, personal: mine, splitSettings: profiles.on);
    final listening = ListeningModel(mine);
    final videos = VideoLibraryModel(storage, lib, personal: mine);
    final servers = ServersModel(storage, lib);
    await servers.load();
    den = await servers.add(
      type: ServerType.jellyfin,
      name: 'Den',
      url: 'http://192.168.0.10:8096',
      username: 'james',
      password: 'sesame',
      uses: {MediaKind.videos},
    );
    final serverVideos = ServerVideosModel(
      storage: mine,
      servers: servers,
      videos: videos,
      secrets: secrets,
      httpClient: () => jellyfin.client,
      deviceName: 'Test PC',
    );
    await serverVideos.load();
    final serverBooks = ServerBooksModel(storage: mine, servers: servers, library: lib, listening: listening, secrets: secrets);
    await serverBooks.load();
    host = ServersHost(lib, listening, videos, servers, serverVideos, serverBooks);
    profiles.host = host;
    await serverVideos.sync(den);
  });

  tearDown(() async {
    host.serverVideos.dispose();
    host.serverBooks.dispose();
    await host.videos.settle();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  int serverVideos() => host.videos.serverVideosOf(den.id).length;
  String tokenOf(String user) => 'jellyfin-token:$user@${den.url.toLowerCase()}';

  test('turning on: the sign-in in use is the first profile\'s, and its videos stay', () async {
    expect(serverVideos(), 4);
    await profiles.turnOn(name: 'James');
    await settle();
    expect(host.servers.byId(den.id)?.username, 'james');
    expect(File(p.join(dir.path, 'data', 'profiles', 'p1', ProfilesModel.serversFile)).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'data', 'profiles', 'p1', ServerVideosModel.fileName)).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'data', ServerVideosModel.fileName)).existsSync(), isFalse);
    expect(serverVideos(), 4);
  });

  test('a profile that hasn\'t signed in sees nothing from the server; switching back keeps the sign-in', () async {
    await profiles.turnOn(name: 'James');
    await profiles.add(name: 'Sam');
    final signInsBefore = jellyfin.signIns;
    expect(await secrets.read(tokenOf('james')), isNotNull);

    await profiles.switchTo('p2');
    await settle();
    expect(host.servers.byId(den.id)?.username, '');
    expect(serverVideos(), 0);
    expect(host.serverVideos.statusFor(host.servers.byId(den.id)!), contains('user name'));
    // James's token wasn't thrown away by the switch.
    expect(await secrets.read(tokenOf('james')), isNotNull);

    await profiles.switchTo('p1');
    await settle();
    expect(host.servers.byId(den.id)?.username, 'james');
    expect(serverVideos(), 4);
    // Read again with the token kept: no new sign-in with the password.
    expect(jellyfin.signIns, signInsBefore);
  });

  test('what\'s downloaded on this device is everyone\'s, signed in to the server or not (8 Nov)', () async {
    final downloaded = 'jf:${den.id}:ep1';
    host.serverVideos.isDownloaded = (id) => id == downloaded;
    await profiles.turnOn(name: 'James');
    await profiles.add(name: 'Sam');
    await profiles.switchTo('p2');
    await settle();
    // Sam hasn't signed in: just the downloaded episode shows.
    expect([for (final v in host.videos.serverVideosOf(den.id)) v.id], [downloaded]);
    expect(File(p.join(dir.path, 'data', ServerVideosModel.offlineFileName)).existsSync(), isTrue);
    // Back as James: everything, the downloaded one once.
    await profiles.switchTo('p1');
    await settle();
    expect(serverVideos(), 4);
    // Removed from the downloads: Sam no longer has it.
    host.serverVideos.isDownloaded = (id) => false;
    await host.serverVideos.rememberDownloaded();
    await profiles.switchTo('p2');
    await settle();
    expect(serverVideos(), 0);
  });

  test('signing in on one profile is that profile\'s alone; the address is everyone\'s', () async {
    await profiles.turnOn(name: 'James');
    await profiles.add(name: 'Sam');
    await profiles.switchTo('p2');
    await settle();
    final mine = host.servers.byId(den.id)!;
    await host.servers.update(mine.copyWith(username: 'sam', name: 'The den'), password: 'pw');
    await settle();
    expect(host.servers.byId(den.id)?.username, 'sam');
    expect(serverVideos(), 0); // the pretend server only knows James
    await profiles.switchTo('p1');
    await settle();
    expect(host.servers.byId(den.id)?.username, 'james');
    expect(host.servers.byId(den.id)?.name, 'The den');
    expect(await host.servers.passwordOf(host.servers.byId(den.id)!), 'sesame');
  });

  test('a server just for me isn\'t seen by anyone else; off keeps the kept person\'s', () async {
    await profiles.turnOn(name: 'James');
    await profiles.add(name: 'Sam');
    await profiles.switchTo('p2');
    await settle();
    final own = await host.servers.add(
      type: ServerType.audiobookshelf,
      name: 'Sam\'s books',
      url: 'http://192.168.1.90:13378',
      uses: {MediaKind.audiobooks},
      justForMe: true,
    );
    expect(host.servers.isMine(own), isTrue);
    expect(host.servers.byId(own.id), isNotNull);
    await host.servers.update(host.servers.byId(den.id)!.copyWith(username: 'sam'));

    await profiles.switchTo('p1');
    await settle();
    expect(host.servers.byId(own.id), isNull);
    expect(host.servers.all.where((s) => s.name == 'Sam\'s books'), isEmpty);

    // Off, keeping Sam's: his sign-in and his own server are everyone's now.
    await profiles.turnOff('p2');
    await settle();
    expect(host.servers.split, isFalse);
    expect(host.servers.byId(den.id)?.username, 'sam');
    expect(host.servers.byId(own.id)?.name, 'Sam\'s books');
    expect(host.servers.isMine(host.servers.byId(own.id)!), isFalse);
  });
}
