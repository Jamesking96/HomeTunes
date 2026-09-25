// Checks the real audio engine (libmpv) on this machine: gapless moves between
// songs, editing the list of what plays next, and whether the equaliser and
// ReplayGain filters exist.
// Run: flutter test tool/bench/engine_test.dart --dart-define=LIBMPV=<path to libmpv-2.dll>
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// A WAV tone of [seconds] seconds.
File tone(String path, double seconds, double hz) {
  const rate = 22050;
  final n = (rate * seconds).round();
  final d = ByteData(44 + n * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      d.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  d.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little);
  d.setUint16(22, 1, Endian.little);
  d.setUint32(24, rate, Endian.little);
  d.setUint32(28, rate * 2, Endian.little);
  d.setUint16(32, 2, Endian.little);
  d.setUint16(34, 16, Endian.little);
  str(36, 'data');
  d.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    d.setInt16(44 + i * 2, (sin(2 * pi * hz * i / rate) * 3000).round(), Endian.little);
  }
  return File(path)..writeAsBytesSync(d.buffer.asUint8List());
}

void main() {
  test('audio engine', () async {
    const lib = String.fromEnvironment('LIBMPV');
    MediaKit.ensureInitialized(libmpv: lib.isEmpty ? null : lib);
    final dir = Directory.systemTemp.createTempSync('hometunes_engine');
    final a = tone('${dir.path}/a.wav', 1.2, 440);
    final b = tone('${dir.path}/b.wav', 1.2, 660);
    final c = tone('${dir.path}/c.wav', 1.2, 880);

    final player = Player();
    final native = player.platform as NativePlayer;
    await player.setVolume(0); // silent test
    await native.setProperty('gapless-audio', 'yes');
    await native.setProperty('prefetch-playlist', 'yes');

    final events = <String>[];
    final sw = Stopwatch()..start();
    final subs = [
      player.stream.playlist.listen((p) => events.add('${sw.elapsedMilliseconds}ms index=${p.index}/${p.medias.length}')),
      player.stream.completed.listen((v) {
        if (v) events.add('${sw.elapsedMilliseconds}ms COMPLETED');
      }),
    ];

    await player.open(Playlist([Media(a.path), Media(b.path)]), play: true);
    // Wait for the engine to reach the second song.
    for (var i = 0; i < 40 && player.state.playlist.index != 1; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final reachedSecond = player.state.playlist.index == 1;
    final completedBeforeSecond = events.any((e) => e.contains('COMPLETED'));
    // Like the app: drop the finished song, add the next one.
    await player.remove(0);
    await player.add(Media(c.path));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final afterEdit = '${player.state.playlist.index}/${player.state.playlist.medias.length}';
    for (var i = 0; i < 40 && player.state.playlist.index != 1; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final reachedThird = player.state.playlist.index == 1;
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    final completedAtEnd = events.any((e) => e.contains('COMPLETED'));

    // Filters.
    String afAfter(String value) {
      return value;
    }

    await native.setProperty('af', 'lavfi=[equalizer=f=1000:t=o:w=1:g=6]');
    final eq = await native.getProperty('af');
    await native.setProperty('af', 'lavfi=[superequalizer=1b=1.5]');
    final superEq = await native.getProperty('af');
    await native.setProperty('af', '');
    await native.setProperty('replaygain', 'track');
    final rg = await native.getProperty('replaygain');
    final version = await native.getProperty('mpv-version');
    final ffmpeg = await native.getProperty('ffmpeg-version');
    afAfter('');

    // ignore: avoid_print
    print([
      'engine: $version, ffmpeg $ffmpeg',
      ...events,
      'moved to 2nd song by itself: $reachedSecond (reported finished before it: $completedBeforeSecond)',
      'after dropping 1st + adding 3rd: index/length = $afterEdit',
      'moved to 3rd song by itself: $reachedThird, finished at end: $completedAtEnd',
      'equalizer filter accepted: "$eq"',
      'superequalizer filter accepted: "$superEq"',
      'replaygain: "$rg"',
    ].join('\n'));

    for (final s in subs) {
      await s.cancel();
    }
    await player.dispose();
    dir.deleteSync(recursive: true);
    expect(reachedSecond, isTrue);
    expect(completedBeforeSecond, isFalse);
    expect(reachedThird, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
