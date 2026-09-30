// Checks "Pick a frame" (ui/screens/video_pictures.dart) against the real engine: a silent,
// paused player seeks exactly, steps one frame forward and back, and gives a screenshot that
// becomes a picture of at most 1280 px. (The dialog's picture itself needs a window.)
//   flutter test tool/bench/frame_picker_engine_test.dart --dart-define=LIBMPV=<libmpv-2.dll>
//     --dart-define=VIDEO=<any video>
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/video_thumbnails.dart';
import 'package:media_kit/media_kit.dart';

Future<void> _wait(bool Function() ok, {int seconds = 10}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!ok() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lib = String.fromEnvironment('LIBMPV');
  const video = String.fromEnvironment('VIDEO');

  test('pick a frame on the real engine', () async {
    MediaKit.ensureInitialized(libmpv: lib.isEmpty ? null : lib);
    final player = Player(configuration: const PlayerConfiguration(title: 'frame picker bench'));
    final engine = player.platform as NativePlayer;
    await engine.setProperty('vid', 'auto');
    await engine.setProperty('aid', 'no');
    await engine.setProperty('sid', 'no');
    await engine.setProperty('hr-seek', 'yes');
    await player.setVolume(0);
    await player.open(Media(video), play: false);
    await _wait(() => player.state.duration > Duration.zero && (player.state.width ?? 0) > 0);
    print('length ${player.state.duration}, ${player.state.width}x${player.state.height}');
    expect(player.state.duration, greaterThan(Duration.zero));

    const at = Duration(seconds: 42, milliseconds: 500);
    await player.seek(at);
    await _wait(() => (player.state.position - at).abs() < const Duration(milliseconds: 100), seconds: 5);
    print('seeked to ${player.state.position} (asked $at)');
    expect((player.state.position - at).abs(), lessThan(const Duration(milliseconds: 100)));

    final before = player.state.position;
    await engine.command(['frame-step']);
    await _wait(() => player.state.position > before, seconds: 3);
    final stepped = player.state.position;
    print('one frame forward: ${stepped - before}, playing: ${player.state.playing}');
    expect(stepped, greaterThan(before));
    expect(stepped - before, lessThan(const Duration(milliseconds: 200)));
    await engine.command(['frame-back-step']);
    await _wait(() => player.state.position < stepped, seconds: 3);
    print('one frame back: ${player.state.position}');
    expect(player.state.position, lessThan(stepped));

    List<int>? shot;
    for (var i = 0; i < 20 && shot == null; i++) {
      shot = await player.screenshot(format: 'image/jpeg');
      if (shot == null) await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(shot, isNotNull);
    final picture = await shrinkToJpeg(shot!, width: 1280, quality: 88, onlyShrink: true);
    print('screenshot ${shot.length} bytes -> picture ${picture?.length} bytes');
    expect(picture, isNotNull);
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
