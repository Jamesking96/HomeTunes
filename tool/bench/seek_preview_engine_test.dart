// Checks the seek preview (services/seek_preview.dart, 0.1.84) against the real engine: the
// hidden player opens the video, and pictures of spots far apart come back small (320 px wide),
// different from each other, and quickly.
//   flutter test tool/bench/seek_preview_engine_test.dart --dart-define=LIBMPV=<libmpv-2.dll>
//     --dart-define=VIDEO=<any video over a minute>
// ignore_for_file: avoid_print
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/seek_preview.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lib = String.fromEnvironment('LIBMPV');
  const video = String.fromEnvironment('VIDEO');

  test('seek preview pictures on the real engine', () async {
    MediaKit.ensureInitialized(libmpv: lib.isEmpty ? null : lib);
    final frames = EngineSeekFrames();
    final opening = Stopwatch()..start();
    await frames.open(video);
    print('opened in ${opening.elapsedMilliseconds} ms');

    final pictures = <List<int>>[];
    for (final at in const [Duration(seconds: 5), Duration(seconds: 30), Duration(seconds: 55), Duration(seconds: 20)]) {
      final took = Stopwatch()..start();
      final picture = await frames.frameAt(at);
      expect(picture, isNotNull, reason: 'no picture at $at');
      final codec = await ui.instantiateImageCodec(picture!);
      final image = (await codec.getNextFrame()).image;
      print('$at: ${took.elapsedMilliseconds} ms, ${picture.length ~/ 1024} KB, ${image.width}x${image.height}');
      expect(image.width, lessThanOrEqualTo(seekPreviewWidth));
      expect(took.elapsedMilliseconds, lessThan(400));
      pictures.add(picture);
    }
    // Spots far apart are different pictures (not the same frame again and again).
    expect(pictures.toSet().length, greaterThan(1));
    String key(List<int> b) => '${b.length}:${b.skip(b.length ~/ 2).take(64).join(',')}';
    expect({for (final p in pictures) key(p)}.length, pictures.length);
    await frames.close();
  });
}
