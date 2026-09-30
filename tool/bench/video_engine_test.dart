// Checks music videos (0.1.32) against the real engine (libmpv, video build) on this machine:
//  * the main player with vid=no plays an .mp4 as sound only (no picture size reported);
//  * a muted video player with aid=no opens the video, reports its picture size, plays and
//    seeks precisely enough for the display to stay in step (ui/widgets/music_video_view.dart);
//  * song and video started together stay close over several seconds;
//  * the Videos tab's thumbnail maker takes a small picture and learns the length (0.1.32).
// Run (the DLL is in build\windows\x64\runner\Release\ after a Windows build):
//   flutter test tool/bench/video_engine_test.dart --dart-define=LIBMPV=<libmpv-2.dll>
//     --dart-define=AUDIO=<song.m4a> --dart-define=VIDEO=<song.mp4>
// Lives in tool/bench/ because it needs the real engine and real files. Everything plays muted.
// It prints a short report, like engine_test.dart.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/video_thumbnails.dart';
import 'package:media_kit/media_kit.dart';

Future<void> _wait(bool Function() ok, {int seconds = 10}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!ok() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // the thumbnail step shrinks pictures with Flutter
  const lib = String.fromEnvironment('LIBMPV');
  const audio = String.fromEnvironment('AUDIO');
  const video = String.fromEnvironment('VIDEO');

  test('music videos on the real engine', () async {
    MediaKit.ensureInitialized(libmpv: lib.isEmpty ? null : lib);
    expect(audio.isNotEmpty && video.isNotEmpty, isTrue, reason: 'pass --dart-define=AUDIO=... and VIDEO=...');

    // 1. The main player, as PlayerModel sets it up: sound only.
    final song = Player();
    await (song.platform as NativePlayer).setProperty('vid', 'no');
    await song.setVolume(0);
    await song.open(Media(video)); // an .mp4 played as a song
    await _wait(() => song.state.position > const Duration(seconds: 1));
    print('main player on the .mp4: position ${song.state.position}, picture width ${song.state.width}');
    expect(song.state.position, greaterThan(Duration.zero));
    expect(song.state.width ?? 0, 0, reason: 'vid=no: no pictures decoded');

    // 2. The video display's player: pictures only.
    final pics = Player();
    final native = pics.platform as NativePlayer;
    await native.setProperty('aid', 'no');
    await native.setProperty('sid', 'no');
    // media_kit starts every player with vid=no; attaching a VideoController (as the display
    // does) switches it to 'auto'. There's no screen here, so do that part by hand.
    await native.setProperty('vid', 'auto');
    await pics.setVolume(0);
    await pics.open(Media(video, start: const Duration(seconds: 20)), play: false);
    await _wait(() => (pics.state.width ?? 0) > 0);
    print('video player: ${pics.state.width}x${pics.state.height}, length ${pics.state.duration}, '
        'opened at ${pics.state.position}');
    expect(pics.state.width, greaterThan(0));
    expect((pics.state.position - const Duration(seconds: 20)).abs(), lessThan(const Duration(milliseconds: 500)));

    // Seeking lands close to where it was asked (what the display relies on to catch up).
    final asked = DateTime.now();
    await pics.seek(const Duration(seconds: 60));
    await _wait(() => (pics.state.position - const Duration(seconds: 60)).abs() < const Duration(milliseconds: 300),
        seconds: 5);
    print('seek to 60 s: at ${pics.state.position} after ${DateTime.now().difference(asked).inMilliseconds} ms');
    expect((pics.state.position - const Duration(seconds: 60)).abs(), lessThan(const Duration(milliseconds: 400)));

    // 3. Song and video started together stay in step.
    await song.open(Media(audio), play: false);
    await pics.seek(Duration.zero);
    await _wait(() => song.state.duration > Duration.zero);
    await Future.wait([song.play(), pics.play()]);
    var worst = Duration.zero;
    for (var i = 0; i < 16; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final gap = (song.state.position - pics.state.position).abs();
      if (gap > worst) worst = gap;
    }
    print('after 8 s together: song ${song.state.position}, video ${pics.state.position}, worst gap $worst');
    expect(pics.state.playing, isTrue);
    expect(pics.state.position, greaterThan(const Duration(seconds: 5)));

    await song.dispose();
    await pics.dispose();

    // 4. Thumbnails for the Videos tab: a picture a tenth of the way in, shrunk to a small JPEG.
    final dir = Directory.systemTemp.createTempSync('hometunes_thumbs');
    final maker = VideoThumbnailer(dir.path);
    final took = Stopwatch()..start();
    final facts = await maker.make(video, modifiedMs: 1);
    await maker.dispose();
    print('thumbnail: ${facts.thumb == null ? 'none' : '${File(facts.thumb!).lengthSync()} bytes'} in '
        '${took.elapsedMilliseconds} ms; length ${facts.duration}, ${facts.width}x${facts.height}');
    expect(facts.thumb, isNotNull);
    expect(File(facts.thumb!).lengthSync(), lessThan(200 << 10));
    expect(facts.duration, greaterThan(Duration.zero));
    dir.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
