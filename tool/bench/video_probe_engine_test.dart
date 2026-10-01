// Checks services/video_probe.dart against the real engine (for the video Details page): it
// lists the file's container, tracks and chapters quickly, without playing it.
//   flutter test tool/bench/video_probe_engine_test.dart --dart-define=LIBMPV=<libmpv-2.dll>
//     --dart-define=VIDEO=<any video>
// Found 1 Oct: with no picture, sound or subtitle track chosen the engine closes the file at
// once and lists nothing, so the probe leaves sound on (to a "null" sound device).
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/video_probe.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lib = String.fromEnvironment('LIBMPV');
  const video = String.fromEnvironment('VIDEO');

  test('probe on the real engine', () async {
    MediaKit.ensureInitialized(libmpv: lib.isEmpty ? null : lib);
    final took = Stopwatch()..start();
    final probe = await probeVideo(video);
    print('probe took ${took.elapsedMilliseconds} ms');
    expect(probe, isNotNull);
    print('container ${probe!.container}, length ${probe.duration}, chapters ${probe.chapters}');
    for (final t in probe.tracks) {
      print('${t.kind}: codec=${t.codec} lang=${t.language} title=${t.title} default=${t.isDefault} '
          'forced=${t.forced} ${t.width}x${t.height} fps=${t.fps} ch=${t.channels} sr=${t.sampleRate} picture=${t.picture}');
    }
    expect(probe.video, isNotEmpty);
    expect(probe.duration, greaterThan(Duration.zero));
  }, timeout: const Timeout(Duration(minutes: 1)));
}
