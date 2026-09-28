// Tests for the lock-screen playback fix: the grace period before telling the phone "paused",
// the stall detector, and the playback log.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/playback_log.dart';
import 'package:hometunes/state/playback_guard.dart';
import 'package:path/path.dart' as p;

void main() {
  final t0 = DateTime(2026, 9, 28, 12);

  group('SystemPlayingState', () {
    test('a pause nobody asked for is hidden for the grace period', () {
      final s = SystemPlayingState();
      expect(s.report(playing: true, pausedOnPurpose: false, now: t0), isTrue);
      // Opening the next song: the engine pauses for a moment.
      expect(s.report(playing: false, pausedOnPurpose: false, now: t0), isTrue);
      expect(s.graceEndsAt, t0.add(SystemPlayingState.grace));
      expect(s.report(playing: false, pausedOnPurpose: false, now: t0.add(const Duration(seconds: 4))), isTrue);
      // Playing again before the grace ran out: never reported as paused.
      expect(s.report(playing: true, pausedOnPurpose: false, now: t0.add(const Duration(seconds: 4))), isTrue);
      expect(s.graceEndsAt, isNull);
    });

    test('a pause that lasts past the grace period is passed on', () {
      final s = SystemPlayingState();
      s.report(playing: false, pausedOnPurpose: false, now: t0);
      expect(s.report(playing: false, pausedOnPurpose: false, now: t0.add(SystemPlayingState.grace)), isFalse);
    });

    test('a pause on purpose is passed on at once', () {
      final s = SystemPlayingState();
      s.report(playing: true, pausedOnPurpose: false, now: t0);
      expect(s.report(playing: false, pausedOnPurpose: true, now: t0), isFalse);
      expect(s.graceEndsAt, isNull);
    });
  });

  group('StallDetector', () {
    test('fires once after no movement for the limit while playing', () {
      final d = StallDetector();
      const pos = Duration(seconds: 30);
      expect(d.check(playing: true, busy: false, position: pos, now: t0), isFalse);
      expect(d.check(playing: true, busy: false, position: pos, now: t0.add(const Duration(seconds: 9))), isFalse);
      expect(d.check(playing: true, busy: false, position: pos, now: t0.add(StallDetector.limit)), isTrue);
      // Starts counting again after firing.
      expect(d.check(playing: true, busy: false, position: pos, now: t0.add(const Duration(seconds: 13))), isFalse);
    });

    test('moving, paused or busy never counts as stuck', () {
      final d = StallDetector();
      var now = t0;
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(seconds: 3));
        expect(d.check(playing: true, busy: false, position: Duration(seconds: i * 3), now: now), isFalse);
      }
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(seconds: 3));
        expect(d.check(playing: false, busy: false, position: Duration.zero, now: now), isFalse);
      }
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(seconds: 3));
        expect(d.check(playing: true, busy: true, position: Duration.zero, now: now), isFalse);
      }
    });

    test('reset starts counting again', () {
      final d = StallDetector();
      d.check(playing: true, busy: false, position: Duration.zero, now: t0);
      d.reset();
      expect(d.check(playing: true, busy: false, position: Duration.zero, now: t0.add(const Duration(seconds: 11))), isFalse);
    });
  });

  group('PlaybackLog', () {
    late Directory dir;
    setUp(() async {
      PlaybackLog.reset();
      dir = await Directory.systemTemp.createTemp('ht_log');
    });
    tearDown(() async {
      PlaybackLog.reset();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('keeps only the last lines', () {
      for (var i = 0; i < PlaybackLog.maxLines + 50; i++) {
        PlaybackLog.add('line $i', at: t0);
      }
      expect(PlaybackLog.lines.length, PlaybackLog.maxLines);
      expect(PlaybackLog.lines.first, endsWith('line 50'));
      expect(PlaybackLog.lines.last, '2026-09-28 12:00:00  line ${PlaybackLog.maxLines + 49}');
    });

    test('is saved and read back on the next start', () async {
      await PlaybackLog.attach(dir.path);
      PlaybackLog.add('Opening "Song"', at: t0);
      await PlaybackLog.save();
      expect(File(p.join(dir.path, 'playback-log.txt')).readAsStringSync(), contains('Opening "Song"'));

      PlaybackLog.reset();
      await PlaybackLog.attach(dir.path);
      PlaybackLog.add('HomeTunes started', at: t0);
      expect(PlaybackLog.lines, hasLength(2));
      expect(PlaybackLog.lines.first, contains('Opening "Song"'));
      await PlaybackLog.save();
    });
  });
}
