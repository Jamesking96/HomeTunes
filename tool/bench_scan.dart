// Times the parts of a library scan on a real folder, to see what's slow.
// Usage: dart run tool/bench_scan.dart <folder> [files to read, default 400]
//
// A developer tool, not part of the app. It compares reading tags with one background worker
// (isolate) against several at once, and how long a "nothing changed" rescan takes, then
// estimates the time for a full first scan. Covers found in files are written to a temporary
// folder that is deleted at the end.
import 'dart:io';
import 'dart:isolate';

import 'package:hometunes/services/local_scanner.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/bench_scan.dart <folder> [count]');
    // 64 is the conventional "wrong command-line usage" exit code.
    exit(64);
  }
  final count = args.length > 1 ? int.parse(args[1]) : 400;
  final art = Directory.systemTemp.createTempSync('hometunes_bench');
  // The scanner is only used here to list the audio files (the same way the app does).
  final scanner = LocalScanner(art.path);

  var sw = Stopwatch()..start();
  final files = await scanner.findAudioFiles([args.first]);
  stdout.writeln('Listing: ${files.length} audio files in ${sw.elapsedMilliseconds} ms');

  // Only time reading a sample of the files, so the bench finishes in reasonable time.
  final sample = files.take(count).toList();
  final mb = sample.fold<int>(0, (a, f) => a + File(f).lengthSync()) / (1024 * 1024);
  stdout.writeln('Sample: ${sample.length} files, ${mb.toStringAsFixed(0)} MB');

  // 1. One background worker (how the app works today).
  sw = Stopwatch()..start();
  await Isolate.run(() {
    for (final f in sample) {
      readTrack(f, 0, art.path);
    }
  });
  final one = sw.elapsedMilliseconds;
  stdout.writeln('1 worker : $one ms  (${(one / sample.length).toStringAsFixed(1)} ms per file)');

  // 2. Several workers at once.
  // Leave one CPU core free for the rest of the system; use between 2 and 6 workers.
  final workers = (Platform.numberOfProcessors - 1).clamp(2, 6);
  sw = Stopwatch()..start();
  // Split the sample into one equal slice per worker and run them all at the same time.
  final chunk = (sample.length / workers).ceil();
  await Future.wait([
    for (var i = 0; i < sample.length; i += chunk)
      Isolate.run(() {
        for (final f in sample.sublist(i, (i + chunk).clamp(0, sample.length))) {
          readTrack(f, 0, art.path);
        }
      }),
  ]);
  final many = sw.elapsedMilliseconds;
  stdout.writeln('$workers workers: $many ms  (${(one / (many == 0 ? 1 : many)).toStringAsFixed(1)}x faster)');

  // 3. Rescan cost when nothing changed: just checking each file's date.
  sw = Stopwatch()..start();
  for (final f in files) {
    File(f).statSync();
  }
  stdout.writeln('Checking all ${files.length} file dates (a rescan): ${sw.elapsedMilliseconds} ms');
  // Scale the sample timings up to the whole folder.
  stdout.writeln('Estimated first scan of everything today: '
      '${(one / sample.length * files.length / 1000).toStringAsFixed(0)} s, with $workers workers: '
      '${(many / sample.length * files.length / 1000).toStringAsFixed(0)} s');
  art.deleteSync(recursive: true);
}
