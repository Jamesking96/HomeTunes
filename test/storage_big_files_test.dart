// Big data files are read, turned into text and written in a background isolate (0.2.12,
// services/storage.dart: the Jellyfin catalogue froze the TV's screen for about a second at each
// save). The same safety rules as small files: whole files only, damaged ones kept aside.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late Storage storage;

  /// About [kb] KB of JSON: a list of made-up videos.
  Map<String, Object> bigJson(int kb, {String tag = 'a'}) => {
        'videos': [
          for (var i = 0; i < kb * 20; i++) {'id': 'jf:s1:$tag$i', 'title': 'Video number $i, $tag', 'n': i},
        ],
      };

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_storage_big');
    storage = Storage.at(dir);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a big file saves and reads back the same, and is then saved in the background', () async {
    final data = bigJson(400);
    expect(storage.isBig('big.json'), isFalse);
    expect(await storage.write('big.json', data), isTrue);
    expect(File(p.join(dir.path, 'big.json')).lengthSync(), greaterThan(Storage.bigFileBytes));
    expect(storage.isBig('big.json'), isTrue);
    expect(jsonEncode(await storage.read('big.json')), jsonEncode(data));
    // The next save goes through the isolate, and still lands whole.
    final again = bigJson(400, tag: 'b');
    expect(await storage.write('big.json', again), isTrue);
    expect(jsonEncode(await storage.read('big.json')), jsonEncode(again));
    expect(File(p.join(dir.path, 'big.json.tmp')).existsSync(), isFalse);
  });

  test('a big file read at start is known as big; one that shrinks is saved here again', () async {
    File(p.join(dir.path, 'cat.json')).writeAsStringSync(jsonEncode(bigJson(300)));
    final fresh = Storage.at(dir);
    expect((await fresh.read('cat.json') as Map)['videos'], hasLength(6000));
    expect(fresh.isBig('cat.json'), isTrue);
    expect(await fresh.write('cat.json', {'videos': []}), isTrue);
    expect(fresh.isBig('cat.json'), isFalse);
    expect(await fresh.read('cat.json'), {'videos': []});
  });

  test('saves of a big file one after another keep their order', () async {
    await storage.write('big.json', bigJson(300));
    final saves = [for (var i = 0; i < 4; i++) storage.write('big.json', bigJson(300, tag: 'v$i'))];
    await Future.wait(saves);
    expect(jsonEncode(await storage.read('big.json')), jsonEncode(bigJson(300, tag: 'v3')));
  });

  test('a damaged big file is kept aside, as a small one is', () async {
    final f = File(p.join(dir.path, 'cat.json'));
    f.writeAsStringSync('{"videos": [${List.filled(100000, '"x"').join(',')}'); // cut off
    expect(f.lengthSync(), greaterThan(Storage.bigFileBytes));
    expect(await storage.read('cat.json'), isNull);
    expect(f.existsSync(), isFalse);
    expect(dir.listSync().map((e) => p.basename(e.path)).any((n) => n.startsWith('cat.corrupt-')), isTrue);
    expect(storage.messages, isNotEmpty);
  });
}
