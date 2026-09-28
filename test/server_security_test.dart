// Tests for release 0.1.17 (code review release D, fix 11): the music server's password is kept
// in the system's protected storage instead of settings.json, old plain-text passwords are moved
// there, backups only include it when asked, login details are hidden in error messages, and
// plain-http addresses outside the home network are recognised for the warning.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/secret_store.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/subsonic_client.dart';
import 'package:hometunes/state/library_model.dart';

void main() {
  late Directory dir;
  late Storage storage;
  late MemorySecretStore secrets;
  final key = SecretStore.serverPasswordKey('http://music.test', 'me');

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_secret');
    storage = Storage.at(dir);
    secrets = MemorySecretStore();
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    dir.deleteSync(recursive: true);
  });

  Future<void> oldSettings({String password = 'sesame'}) => storage.write('settings.json', {
        'folders': [],
        'server': {'url': 'http://music.test', 'username': 'me', 'password': password},
      });

  test('a plain-text password in settings.json is moved into protected storage', () async {
    await oldSettings();
    final lib = LibraryModel(storage, secrets: secrets);
    await lib.load();
    expect(lib.server.password, 'sesame');
    expect(secrets.values[key], 'sesame');
    final saved = await storage.read('settings.json') as Map<String, dynamic>;
    expect((saved['server'] as Map).containsKey('password'), isFalse);
    expect((saved['server'] as Map)['url'], 'http://music.test');
    // Next start: the password comes back from protected storage.
    final again = LibraryModel(storage, secrets: secrets);
    await again.load();
    expect(again.server.password, 'sesame');
  });

  test('if protected storage can\'t save it, the password stays in settings.json', () async {
    secrets.failWrites = true;
    await oldSettings();
    final lib = LibraryModel(storage, secrets: secrets);
    await lib.load();
    expect(lib.server.password, 'sesame');
    await lib.setOnlineCovers(false); // any save of settings.json
    final saved = await storage.read('settings.json') as Map<String, dynamic>;
    expect((saved['server'] as Map)['password'], 'sesame');
  });

  test('another server or user never gets the saved password', () async {
    secrets.values[key] = 'sesame';
    await storage.write('settings.json', {
      'server': {'url': 'http://other.test', 'username': 'me'},
    });
    final lib = LibraryModel(storage, secrets: secrets);
    await lib.load();
    expect(lib.server.password, isEmpty);
  });

  test('forgetting the server removes its password too', () async {
    await oldSettings();
    final lib = LibraryModel(storage, secrets: secrets);
    await lib.load();
    await lib.forgetServer();
    expect(secrets.values, isEmpty);
  });

  test('backups never include the password (0.1.21)', () async {
    await oldSettings();
    final lib = LibraryModel(storage, secrets: secrets);
    await lib.load();
    expect(AppBackup.read(await lib.createBackup()).hasPassword, isFalse);
  });

  test('an old backup that has a password still restores it into protected storage', () async {
    await oldSettings();
    final lib = LibraryModel(storage, secrets: secrets);
    await lib.load();
    // A backup made by 0.1.20 or earlier with "Include the server password" ticked.
    final bytes = await lib.createBackup();
    final json = jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    ((json['files'] as Map)['settings.json'] as Map)['server'] = {
      'url': 'http://music.test', 'username': 'me', 'password': 'from-backup',
    };
    final old = AppBackup.read(gzip.encode(utf8.encode(jsonEncode(json))));
    expect(old.hasPassword, isTrue);
    secrets.values.clear();
    await lib.restoreBackup(old, merge: false, reloadOthers: () async {});
    expect(lib.server.password, 'from-backup');
    expect(secrets.values[key], 'from-backup');
    final saved = await storage.read('settings.json') as Map<String, dynamic>;
    expect((saved['server'] as Map).containsKey('password'), isFalse);
  });

  test('restoring a backup of the same server doesn\'t ask for the password again', () async {
    await oldSettings();
    final lib = LibraryModel(storage, secrets: secrets);
    await lib.load();
    final backup = AppBackup.read(await lib.createBackup()); // no password inside
    final result = await lib.restoreBackup(backup, merge: false, reloadOthers: () async {});
    expect(result.needsPassword, isFalse);
    expect(lib.server.password, 'sesame');
  });

  test('login details are hidden in error messages', () {
    const raw = 'ClientException: Connection refused, uri=http://music.test/rest/ping?u=me&t=26719a&s=c19b2d&v=1.16.1&c=hometunes&f=json';
    final shown = hideSecrets(raw);
    expect(shown, isNot(contains('26719a')));
    expect(shown, isNot(contains('c19b2d')));
    expect(shown, isNot(contains('u=me')));
    expect(shown, contains('v=1.16.1'));
    expect(shown, contains('http://music.test/rest/ping'));
  });

  test('plain http is only flagged for addresses outside the home network', () {
    for (final home in [
      'http://192.168.1.20:4533',
      '192.168.1.20:4533',
      'http://10.0.0.5',
      'http://172.20.1.1',
      'http://localhost:4533',
      'http://nas:4533',
      'http://nas.local',
      'http://100.101.5.6',
      'https://music.example.com',
      '',
    ]) {
      expect(isPlainHttpToInternet(home), isFalse, reason: home);
    }
    for (final internet in ['http://music.example.com', 'music.example.com:4533', 'http://8.8.8.8']) {
      expect(isPlainHttpToInternet(internet), isTrue, reason: internet);
    }
  });

  test('a server\'s own error answer is marked as coming from the server', () {
    expect(SubsonicException('Wrong username or password', fromServer: true).fromServer, isTrue);
    expect(SubsonicException('Could not reach').fromServer, isFalse);
  });
}
