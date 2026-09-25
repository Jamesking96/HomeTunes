// Checks the real audio engine (libmpv) on this machine: gapless moves between
// songs, editing the list of what plays next, and whether the equaliser and
// ReplayGain filters exist.
// Run: flutter test tool/bench/engine_test.dart --dart-define=LIBMPV=<path to libmpv-2.dll>
//
// Lives in tool/bench/ rather than test/ on purpose: it needs the real libmpv audio engine, so
// it isn't part of the normal `flutter test` run. It makes three short test tones, plays them
// silently (volume 0) and prints a report of what the engine did, then checks the key results.
// The PlayerModel design (gapless preloading, dropping the finished song, the equaliser and
// ReplayGain settings) relies on what this test confirms. tone() is reused by
// player_gapless_test.dart.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/eq_preset.dart';
import 'package:media_kit/media_kit.dart';

/// A WAV tone of [seconds] seconds.
///
/// Writes a plain 16-bit mono WAV file containing a sine wave at [hz] (pitch) to [path].
/// Different pitches make the files easy to tell apart by ear if the volume is turned up.
File tone(String path, double seconds, double hz) {
  const rate = 22050;
  final n = (rate * seconds).round();
  final d = ByteData(44 + n * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      d.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  // The standard 44-byte WAV header: "RIFF" + size, "WAVE", a "fmt " block describing the
  // format (PCM, 1 channel, sample rate, bytes per second, bytes per sample, 16 bits), then the
  // "data" block with the samples.
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
  // The samples: a quiet sine wave (3000 out of a possible 32767).
  for (var i = 0; i < n; i++) {
    d.setInt16(44 + i * 2, (sin(2 * pi * hz * i / rate) * 3000).round(), Endian.little);
  }
  return File(path)..writeAsBytesSync(d.buffer.asUint8List());
}

void main() {
  test('audio engine', () async {
    // LIBMPV (optional) points at a libmpv DLL; otherwise media_kit looks in its usual places.
    const lib = String.fromEnvironment('LIBMPV');
    MediaKit.ensureInitialized(libmpv: lib.isEmpty ? null : lib);
    final dir = Directory.systemTemp.createTempSync('hometunes_engine');
    final a = tone('${dir.path}/a.wav', 1.2, 440);
    final b = tone('${dir.path}/b.wav', 1.2, 660);
    final c = tone('${dir.path}/c.wav', 1.2, 880);

    final player = Player();
    // NativePlayer gives direct access to mpv's own settings ("properties").
    final native = player.platform as NativePlayer;
    await player.setVolume(0); // silent test
    // Ask mpv to join songs with no gap, and to open the next song in the list early.
    await native.setProperty('gapless-audio', 'yes');
    await native.setProperty('prefetch-playlist', 'yes');

    // Log every playlist move and "finished" signal with a timestamp, for the printed report.
    final events = <String>[];
    final sw = Stopwatch()..start();
    final subs = [
      player.stream.playlist.listen((p) => events.add('${sw.elapsedMilliseconds}ms index=${p.index}/${p.medias.length}')),
      player.stream.completed.listen((v) {
        if (v) events.add('${sw.elapsedMilliseconds}ms COMPLETED');
      }),
    ];

    // 1. Two songs in the engine's list: does it move from the first to the second by itself?
    await player.open(Playlist([Media(a.path), Media(b.path)]), play: true);
    // Wait for the engine to reach the second song.
    for (var i = 0; i < 40 && player.state.playlist.index != 1; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final reachedSecond = player.state.playlist.index == 1;
    final completedBeforeSecond = events.any((e) => e.contains('COMPLETED'));
    // Like the app: drop the finished song, add the next one.
    // 2. Edit the list while it plays (drop the finished song, add the next one), then check the
    //    engine carries on into the newly added song and reports "finished" at the very end.
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
    // 3. Check the audio filters the Settings use exist in this build: a single-band equaliser
    //    (+6 dB at 1 kHz), the multi-band "superequalizer", and ReplayGain volume levelling.
    //    Reading the property back shows whether mpv accepted it.
    await native.setProperty('af', 'lavfi=[equalizer=f=1000:t=o:w=1:g=6]');
    final eq = await native.getProperty('af');
    await native.setProperty('af', 'lavfi=[superequalizer=1b=1.5]');
    final superEq = await native.getProperty('af');
    await native.setProperty('af', '');
    await native.setProperty('replaygain', 'track');
    final rg = await native.getProperty('replaygain');
    final version = await native.getProperty('mpv-version');
    final ffmpeg = await native.getProperty('ffmpeg-version');

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

    // Tidy up: stop listening, close the engine and delete the tone files.
    for (final s in subs) {
      await s.cancel();
    }
    await player.dispose();
    dir.deleteSync(recursive: true);
    expect(reachedSecond, isTrue);
    // Note: the engine does report "finished" just before moving on to the
    // next song (completedBeforeSecond is true); PlayerModel allows for that.
    expect(reachedThird, isTrue);
    expect(completedAtEnd, isTrue);
    expect(eq, contains('equalizer'));
    expect(rg, 'track');
  }, timeout: const Timeout(Duration(minutes: 2)));

  // 4. The app's real equaliser filters: a whole preset while a tone plays at 1.5× speed,
  //    changed live to another preset. Playback must keep going with no filter errors.
  test('equaliser presets play', () async {
    const lib = String.fromEnvironment('LIBMPV');
    MediaKit.ensureInitialized(libmpv: lib.isEmpty ? null : lib);
    final dir = Directory.systemTemp.createTempSync('hometunes_eq_engine');
    final t = tone('${dir.path}/long.wav', 6, 440);
    final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn));
    final native = player.platform as NativePlayer;
    final problems = <String>[];
    final sub = player.stream.log.listen((l) => problems.add('[${l.level}] ${l.prefix}: ${l.text.trim()}'));
    final errors = player.stream.error.listen((e) => problems.add('error: $e'));
    await player.setVolume(0);

    final rock = eqFilter(builtInEqPreset('rock'));
    await native.setProperty('af', rock);
    await player.open(Media(t.path), play: true);
    await player.setRate(1.5);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final afterRock = player.state.position;
    final applied = await native.getProperty('af');

    await native.setProperty('af', eqFilter(builtInEqPreset('spoken')));
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    final afterSpoken = player.state.position;
    final stillPlaying = player.state.playing;

    await native.setProperty('af', '');
    await sub.cancel();
    await errors.cancel();
    await player.dispose();
    dir.deleteSync(recursive: true);

    // ignore: avoid_print
    print([
      'equaliser: filter set = "$applied"',
      'position after 1.5 s with Rock at 1.5x: $afterRock; after switching to Spoken word: $afterSpoken',
      'engine warnings: ${problems.isEmpty ? 'none' : problems.join(' | ')}',
    ].join('\n'));
    expect(applied, contains('equalizer'));
    expect(afterRock, greaterThan(const Duration(milliseconds: 1200))); // 1.5 s at 1.5× ≈ 2.2 s
    expect(afterSpoken, greaterThan(afterRock));
    expect(stillPlaying, isTrue);
    expect(problems.where((p) => p.contains('lavfi') || p.contains('filter') || p.startsWith('error')), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
