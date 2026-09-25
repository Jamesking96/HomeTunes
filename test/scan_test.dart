// Tests for scanning a music folder (services/local_scanner.dart and LibraryModel.scanLocal).
// They write lots of tiny silent WAV files into a temp folder, so they run without any real
// music. Covered: the parallel background workers find every file exactly once and keep folder
// order, and scan progress is reported separately so the whole app doesn't redraw per batch.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/local_scanner.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:path/path.dart' as p;

import 'metadata_features_test.dart' show silentWav;

void main() {
  // The scanner reads tags in batches spread over several isolates (workers); results must still
  // come back complete, without duplicates and sorted by path, and progress must reach the total.
  test('several workers at once: every file found once, in folder order', () async {
    final dir = Directory.systemTemp.createTempSync('hometunes_scan');
    addTearDown(() => dir.deleteSync(recursive: true));
    final music = Directory(p.join(dir.path, 'music'))..createSync();
    final n = LocalScanner.batchSize * 3 + 7; // more batches than one worker would take
    for (var i = 0; i < n; i++) {
      File(p.join(music.path, 'song ${i.toString().padLeft(3, '0')}.wav')).writeAsBytesSync(silentWav());
    }
    final art = Directory(p.join(dir.path, 'art'))..createSync();
    var lastDone = 0;
    final tracks = await LocalScanner(art.path).scan([music.path], onProgress: (done, total) {
      expect(total, n);
      lastDone = done;
    });
    expect(tracks.length, n);
    expect(lastDone, n);
    final paths = [for (final t in tracks) t.path!];
    expect(paths, [...paths]..sort());
    expect(paths.toSet().length, n);
  });

  // Progress goes through the separate `statusText` notifier; the main library notifier (which
  // makes every screen rebuild) should only fire a handful of times for the whole scan.
  test('scan progress doesn\'t redraw the whole app', () async {
    final dir = Directory.systemTemp.createTempSync('hometunes_scan2');
    addTearDown(() => dir.deleteSync(recursive: true));
    final music = Directory(p.join(dir.path, 'music'))..createSync();
    for (var i = 0; i < LocalScanner.batchSize * 2; i++) {
      File(p.join(music.path, '$i.wav')).writeAsBytesSync(silentWav());
    }
    final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    Directory(storage.artDir).createSync();
    final lib = LibraryModel(storage)..folders = [music.path];
    var redraws = 0;
    var progressUpdates = 0;
    lib.addListener(() => redraws++);
    lib.statusText.addListener(() => progressUpdates++);
    await lib.scanLocal();
    expect(lib.tracks.length, LocalScanner.batchSize * 2);
    expect(progressUpdates, greaterThan(2));
    expect(redraws, lessThanOrEqualTo(4)); // start, finished, rebuilt – not once per batch
    expect(lib.songsByTitle.length, lib.tracks.length);
  });
}
