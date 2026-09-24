// Times a full library scan through the app's own model (no screens).
// Run: flutter test tool/bench/library_scan_test.dart --dart-define=FOLDER=F:\Music
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';

void main() {
  test('scan timing', () async {
    const folder = String.fromEnvironment('FOLDER');
    final dir = Directory.systemTemp.createTempSync('hometunes_libbench');
    final storage = Storage.at(dir);
    Directory(storage.artDir).createSync();
    final lib = LibraryModel(storage);
    var notifications = 0;
    lib.addListener(() => notifications++);
    lib.folders = [folder];
    final sw = Stopwatch()..start();
    await lib.scanLocal();
    // ignore: avoid_print
    print('first scan: ${sw.elapsedMilliseconds} ms, ${lib.tracks.length} songs, '
        '${lib.albums.length} albums, $notifications screen updates');
    notifications = 0;
    sw.reset();
    await lib.scanLocal();
    // ignore: avoid_print
    print('rescan: ${sw.elapsedMilliseconds} ms, $notifications screen updates');
    dir.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
