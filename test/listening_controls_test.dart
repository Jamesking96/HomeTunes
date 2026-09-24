import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/book.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/state/sleep_timer.dart';
import 'package:hometunes/ui/widgets/listening_controls.dart';
import 'package:hometunes/ui/widgets/player_controls.dart';

Track song(String id, {int seconds = 180}) => Track(
      id: id,
      source: TrackSource.local,
      title: id,
      artist: 'A',
      album: 'B',
      albumArtist: 'A',
      duration: Duration(seconds: seconds),
      path: '/m/$id.mp3',
    );

/// Stands in for the real player (which needs the audio engine).
class FakeTarget implements SleepTarget {
  @override
  bool inBook = false;
  @override
  bool playing = true;
  @override
  Track? current = song('one');
  @override
  Duration duration = const Duration(minutes: 3);
  @override
  Duration position = Duration.zero;
  @override
  Duration bookOffset = Duration.zero;
  @override
  int currentChapterIndex = -1;
  Duration end = Duration.zero;
  @override
  double volume = 80;
  bool paused = false;
  bool saved = false;

  @override
  Duration chapterEnd(int i) => end;
  @override
  Future<void> setVolume(double v) async => volume = v;
  @override
  Future<void> pause() async {
    paused = true;
    playing = false;
  }

  @override
  void saveBookPlace() => saved = true;
}

void main() {
  const m = Duration(minutes: 1);
  const s = Duration(seconds: 1);

  group('Skipping', () {
    final parts = [m * 10, m * 10, m * 10];

    test('back 15 s from near the start of a file goes into the previous one', () {
      expect(PlayerModel.skipTarget(parts, 1, s * 5, -s * 15), (0, m * 10 - s * 10));
    });

    test('forward 30 s near the end of a file carries into the next one', () {
      expect(PlayerModel.skipTarget(parts, 0, m * 10 - s * 10, s * 30), (1, s * 20));
    });

    test('stops at the very start and the very end of the book', () {
      expect(PlayerModel.skipTarget(parts, 0, s * 5, -s * 15), (0, Duration.zero));
      expect(PlayerModel.skipTarget(parts, 2, m * 10 - s * 10, s * 30), (2, m * 10 - s));
    });

    test('songs: back stops at 0, forward past the end means next song', () {
      expect(PlayerModel.skipTarget([m * 3], 0, s * 5, -s * 15), (0, Duration.zero));
      expect(PlayerModel.skipTarget([m * 3], 0, m * 3 - s * 10, s * 30), isNull);
    });
  });

  test('which chapter a time is in', () {
    const chapters = [
      BookChapter(part: 0, start: Duration.zero, offset: Duration.zero, title: 'One'),
      BookChapter(part: 0, start: Duration(minutes: 10), offset: Duration(minutes: 10), title: 'Two'),
      BookChapter(part: 1, start: Duration.zero, offset: Duration(minutes: 30), title: 'Three'),
    ];
    expect(PlayerModel.chapterIndexAt(chapters, Duration.zero), 0);
    expect(PlayerModel.chapterIndexAt(chapters, m * 12), 1);
    expect(PlayerModel.chapterIndexAt(chapters, m * 45), 2);
    expect(PlayerModel.chapterIndexAt(const [], m), -1);
  });

  test('mouse wheel over the volume: down turns it down, up turns it up, within 0–100', () {
    expect(VolumeControl.afterWheel(50, 100), 45);
    expect(VolumeControl.afterWheel(50, -100), 55);
    expect(VolumeControl.afterWheel(2, 100), 0);
    expect(VolumeControl.afterWheel(98, -100), 100);
    expect(VolumeControl.afterWheel(50, 0), 50);
  });

  test('speed labels', () {
    expect(SpeedButton.label(1.0), '1.0×');
    expect(SpeedButton.label(1.25), '1.25×');
    expect(SpeedButton.label(2.5), '2.5×');
    expect(SpeedButton.label(0.75), '0.75×');
  });

  group('Sleep timer', () {
    late Directory dir;
    late LibraryModel settings;
    late FakeTarget player;
    late SleepTimer timer;
    var clock = DateTime(2026, 9, 24, 23);

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_sleep');
      settings = LibraryModel(Storage.at(dir));
      player = FakeTarget();
      timer = SleepTimer(player, settings)..now = () => clock;
    });
    tearDown(() async {
      timer.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      dir.deleteSync(recursive: true);
    });

    test('music uses the music length; one tap on, one tap off', () async {
      await settings.updateListeningSettings(sleepMusicMinutes: 20, sleepBookMinutes: 45);
      timer.toggle();
      expect(timer.active, isTrue);
      expect(timer.remaining, m * 20);
      timer.toggle();
      expect(timer.active, isFalse);
      expect(player.paused, isFalse);
    });

    test('books use the book length, fade out, then pause and save the place', () async {
      await settings.updateListeningSettings(sleepBookMinutes: 45, sleepFadeSeconds: 10);
      player.inBook = true;
      timer.start();
      expect(timer.remaining, m * 45);
      clock = clock.add(m * 45 - s * 5); // 5 s left: halfway through the fade
      timer.tick();
      expect(player.volume, closeTo(40, 1));
      clock = clock.add(s * 6);
      timer.tick();
      await Future<void>.delayed(Duration.zero);
      expect(player.paused, isTrue);
      expect(player.saved, isTrue);
      expect(player.volume, 80); // volume put back for next time
      expect(timer.active, isFalse);
    });

    test('end of song: pauses when the song changes', () async {
      await settings.updateListeningSettings(sleepMusicMinutes: LibraryModel.sleepAtEnd);
      timer.start();
      expect(timer.mode, SleepMode.endOfSong);
      expect(timer.remaining, m * 3);
      player.current = song('two');
      timer.tick();
      await Future<void>.delayed(Duration.zero);
      expect(player.paused, isTrue);
    });

    test('end of chapter: counts down to the chapter end', () async {
      await settings.updateListeningSettings(sleepBookMinutes: LibraryModel.sleepAtEnd, sleepFadeSeconds: 0);
      player
        ..inBook = true
        ..currentChapterIndex = 3
        ..bookOffset = m * 50
        ..end = m * 62;
      timer.start();
      expect(timer.mode, SleepMode.endOfChapter);
      expect(timer.remaining, m * 12);
      player.currentChapterIndex = 4; // the chapter ended
      timer.tick();
      await Future<void>.delayed(Duration.zero);
      expect(player.paused, isTrue);
    });
  });

  group('Settings and per-book speed are saved', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_lset'));
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      dir.deleteSync(recursive: true);
    });

    test('listening settings survive a restart', () async {
      final a = LibraryModel(Storage.at(dir));
      await a.updateListeningSettings(
        skipBackSeconds: 10,
        skipForwardSeconds: 45,
        rewindOnResume: false,
        defaultBookSpeed: 1.25,
        sleepButtonShown: false,
        sleepBookMinutes: LibraryModel.sleepAtEnd,
        sleepMusicMinutes: 15,
        sleepFadeSeconds: 30,
      );
      final b = LibraryModel(Storage.at(dir));
      await b.load();
      expect(b.skipBackSeconds, 10);
      expect(b.skipForwardSeconds, 45);
      expect(b.rewindOnResume, isFalse);
      expect(b.defaultBookSpeed, 1.25);
      expect(b.sleepButtonShown, isFalse);
      expect(b.sleepBookMinutes, LibraryModel.sleepAtEnd);
      expect(b.sleepMusicMinutes, 15);
      expect(b.sleepFadeSeconds, 30);
    });

    test('a book keeps its speed as you listen', () async {
      final l = ListeningModel(Storage.at(dir));
      await l.load();
      final book = Book(id: 'b', title: 'B', author: 'A', parts: [song('p1', seconds: 600)]);
      expect(l.speedFor(book), isNull);
      await l.setSpeed(book, 1.5);
      await l.record(book, 'p1', m * 2);
      expect(l.speedFor(book), 1.5);
      expect(l.stateOf(book), BookState.inProgress);
    });
  });
}
