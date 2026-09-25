// Times a full library scan through the app's own model (no screens).
// Run: flutter test tool/bench/library_scan_test.dart --dart-define=FOLDER=F:\Music
//
// A timing bench, not a pass/fail test (kept in tool/bench/ so the normal test run skips it).
// It scans the folder twice through LibraryModel with its data saved in a temp folder: the
// first scan reads every file, the second should reuse almost everything because nothing
// changed. It also counts change notifications, since each one can make the screens redraw.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';

void main() {
  test('scan timing', () async {
    const folder = String.fromEnvironment('FOLDER');
    final dir = Directory.systemTemp.createTempSync('hometunes_libbench');
    // Keep all saved data in the temp folder so the real app's library isn't touched.
    final storage = Storage.at(dir);
    Directory(storage.artDir).createSync();
    final lib = LibraryModel(storage);
    // Second run: files are unchanged, so this measures the "quick rescan" path.
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
