// Checks what the bottom bar relies on from the real video engine: after opening a video, the
// player reports playing, moving position and volume changes on its streams.
//   flutter test tool/bench/video_bar_engine_test.dart --dart-define=LIBMPV=<libmpv-2.dll>
//     --dart-define=VIDEO=<any video>
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lib = String.fromEnvironment('LIBMPV');
  const video = String.fromEnvironment('VIDEO');

  test('video streams on the real engine', () async {
    MediaKit.ensureInitialized(libmpv: lib.isEmpty ? null : lib);
    final player = Player(configuration: const PlayerConfiguration(title: 'bench', libass: true));
    final volumes = <double>[], playing = <bool>[];
    var positions = 0;
    player.stream.volume.listen(volumes.add);
    player.stream.playing.listen(playing.add);
    player.stream.position.listen((_) => positions++);
    await (player.platform as NativePlayer).setProperty('vid', 'no');
    await player.setVolume(0);
    await player.open(Media(video));
    await Future<void>.delayed(const Duration(seconds: 2));
    print('after open: playing events $playing, position events $positions, volume events $volumes, '
        'state volume ${player.state.volume}');
    final before = volumes.length;
    await player.setVolume(30);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await player.setVolume(10);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    print('after setVolume 30, 10: volume events ${volumes.sublist(before)}, state ${player.state.volume}');
    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 1)));
}
