// 0.1.63: the sleep timer for videos (state/video_sleep_timer.dart).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_sleep_timer.dart';

class _FakeVideo extends ChangeNotifier implements VideoSleepTarget {
  @override
  String? videoId = 'v1';
  @override
  bool playing = true;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(minutes: 24);
  @override
  double volume = 80;
  int pauses = 0;

  @override
  Future<void> setVolume(double v) async => volume = v;
  @override
  Future<void> pause() async {
    pauses++;
    playing = false;
  }
}

void main() {
  late LibraryModel settings;
  late _FakeVideo video;
  late DateTime clock;
  late VideoSleepTimer timer;

  setUp(() {
    settings = LibraryModel(Storage.at(Directory.systemTemp));
    video = _FakeVideo();
    clock = DateTime(2026, 10, 6, 1);
    timer = VideoSleepTimer(video, settings, changes: video)..now = () => clock;
  });
  tearDown(() => timer.dispose());

  test('after the length for videos: fades out, pauses, puts the volume back', () {
    settings.sleepVideoMinutes = 20;
    settings.sleepFadeSeconds = 10;
    timer.start();
    expect(timer.active, isTrue);
    expect(timer.mode, VideoSleepMode.minutes);
    expect(timer.remaining, const Duration(minutes: 20));

    clock = clock.add(const Duration(minutes: 19, seconds: 55));
    timer.tick();
    expect(video.volume, closeTo(40, 0.01)); // half way through the 10 s fade
    expect(video.pauses, 0);

    clock = clock.add(const Duration(seconds: 6));
    timer.tick();
    expect(video.pauses, 1);
  });

  test('end of video: pauses just before the end, so the next episode does not start', () async {
    settings.sleepVideoMinutes = LibraryModel.sleepAtEnd;
    settings.sleepFadeSeconds = 0;
    video.position = const Duration(minutes: 20);
    timer.start();
    expect(timer.mode, VideoSleepMode.endOfVideo);
    expect(timer.remaining, const Duration(minutes: 4));
    video.position = const Duration(minutes: 23, seconds: 59, milliseconds: 600);
    timer.tick();
    expect(video.pauses, 1);
    await pumpEventQueue(); // the timer switches off once the pause is done
    expect(timer.active, isFalse);
  });

  test('end of video: if the next video starts anyway, that one is paused', () {
    settings.sleepVideoMinutes = LibraryModel.sleepAtEnd;
    timer.start();
    video.videoId = 'v2';
    video.position = Duration.zero;
    timer.tick();
    expect(video.pauses, 1);
  });

  test('closing the video page stops the timer; tapping again turns it off', () {
    settings.sleepVideoMinutes = 30;
    timer.toggle();
    expect(timer.active, isTrue);
    timer.toggle();
    expect(timer.active, isFalse);

    timer.start();
    video.videoId = null;
    video.notifyListeners();
    expect(timer.active, isFalse);
    expect(video.pauses, 0);
  });

  test('no video: nothing starts', () {
    video.videoId = null;
    timer.start();
    expect(timer.active, isFalse);
  });
}
