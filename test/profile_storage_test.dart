// Where a profile's own files are kept (Profiles plan, phase 0; services/storage.dart forProfile):
// with profiles off it's the data folder itself; a profile's view saves into profiles/<id>/,
// shares the art folder, and its problems show with the data folder's messages.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late Storage storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_profile_storage');
    storage = Storage.at(dir);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('with profiles off, a profile\'s files are the data folder\'s (nothing moves)', () {
    expect(identical(storage.forProfile(null), storage), isTrue);
  });

  test('a profile saves in profiles/<id>/, reads its own files, and shares the art folder', () async {
    final p1 = storage.forProfile('p1');
    expect(identical(storage.forProfile('p1'), p1), isTrue);
    expect(p1.root.path, p.join(dir.path, 'profiles', 'p1'));
    expect(p1.artDir, storage.artDir);
    expect(await p1.write('playlists.json', {'liked': ['a']}), isTrue);
    expect(File(p.join(dir.path, 'profiles', 'p1', 'playlists.json')).existsSync(), isTrue);
    expect(await p1.read('playlists.json'), {'liked': ['a']});
    expect(await storage.read('playlists.json'), isNull);
    expect(await storage.forProfile('p2').read('playlists.json'), isNull);
    // From a profile's view, "profiles off" is still the data folder.
    expect(identical(p1.forProfile(null), storage), isTrue);
    expect(identical(p1.forProfile('p2'), storage.forProfile('p2')), isTrue);
  });

  test('a damaged file in a profile is reported with the data folder\'s messages', () async {
    final p1 = storage.forProfile('p1');
    File(p.join(p1.root.path, 'listening.json')).writeAsStringSync('{"books": ');
    expect(await p1.read('listening.json'), isNull);
    expect(storage.messages.single, contains('was damaged'));
  });

  test('only plain ids are profile folders', () {
    expect(() => storage.forProfile('../x'), throwsArgumentError);
    expect(() => storage.forProfile(''), throwsArgumentError);
  });
}
