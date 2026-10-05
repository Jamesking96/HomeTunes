// 0.1.55: video playback stats in the Playback log (services/video_stats.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/playback_log.dart';
import 'package:hometunes/services/video_drawing.dart';
import 'package:hometunes/services/video_stats.dart';

void main() {
  setUp(PlaybackLog.reset);

  group('plain words', () {
    test('decoder', () {
      expect(describeDecoder(''), 'software (main processor)');
      expect(describeDecoder('no'), 'software (main processor)');
      expect(describeDecoder('mediacodec-copy'), 'video chip, copied before drawing (mediacodec-copy)');
      expect(describeDecoder('d3d11va'), 'video chip (d3d11va)');
    });

    test('format and the start line', () {
      expect(describeFormat('hevc', 'yuv420p10'), 'HEVC 10-bit');
      expect(describeFormat('h264', 'yuv420p'), 'H264');
      expect(describeFormat('', ''), 'unknown format');
      expect(
          startLine('Video', 'Silo S1 E2', {
            'video-params/w': '3840',
            'video-params/h': '2160',
            'video-format': 'hevc',
            'video-params/pixelformat': 'yuv420p10',
            'container-fps': '23.976024',
            'hwdec-current': 'mediacodec-copy',
            'current-vo': 'gpu',
          }),
          'Video started: Silo S1 E2 · 3840×2160 · HEVC 10-bit · 23.98 fps · '
          'decoding: video chip, copied before drawing (mediacodec-copy) · drawing: gpu');
    });

    test('stutter and summary lines', () {
      expect(
          stutterLine('Video',
              decoderDrops: 0, screenDrops: 0, waits: 0, slowAppFrames: 0, readAhead: '', over: const Duration(seconds: 30)),
          isNull);
      expect(
          stutterLine('Music video',
              decoderDrops: 3,
              screenDrops: 12,
              waits: 1,
              slowAppFrames: 4,
              readAhead: '8.250000',
              over: const Duration(seconds: 30)),
          'Music video stutter in the last 30 s: 15 pictures dropped (decoder 3, screen 12) · '
          'paused to load 1 time · app slow to draw 4 times · read ahead 8.3 s');
      // 0.1.57: how far out the jumps were, why the app was slow, and leaving the app.
      expect(
          stutterLine('Music video',
              decoderDrops: 0,
              screenDrops: 0,
              waits: 0,
              slowAppFrames: 3,
              jumps: 3,
              jumpDrifts: const [
                Duration(milliseconds: -1800),
                Duration(milliseconds: -2600),
                Duration(milliseconds: 2100),
              ],
              slowWhy: slowDetail(worstMs: 85, building: 1, drawing: 2),
              leftScreen: true,
              readAhead: '',
              over: const Duration(seconds: 30)),
          'Music video stutter in the last 30 s: jumped back into step 3 times '
          '(video behind by 1.8–2.6 s, video ahead by 2.1 s) · app slow to draw 3 times '
          '(worst 85 ms, mostly drawing) · the app was out of sight for part of it');
      expect(
          stutterLine('Video',
              decoderDrops: 0,
              screenDrops: 0,
              waits: 5,
              slowAppFrames: 0,
              skips: 4,
              readAhead: '',
              over: const Duration(seconds: 30)),
          'Video stutter in the last 30 s: paused to load 5 times · you skipped or moved it 4 times');
      expect(slowDetail(worstMs: 40, building: 2, drawing: 0), 'worst 40 ms, mostly building the screen');
      expect(slowDetail(worstMs: 0, building: 0, drawing: 0), '');
      expect(jumpDetail(const [Duration(seconds: -2)]), 'video behind by 2 s');
      expect(describeDrawing('mediacodec_embed'), 'straight from the video chip (mediacodec_embed)');
      expect(describeDrawing('gpu'), 'gpu');
      expect(summaryLine('Video', 'Film', played: const Duration(minutes: 2, seconds: 5), drops: 0, waits: 0, slowAppFrames: 0),
          'Video finished: Film · played 2:05 · smooth');
    });
  });

  // 0.1.57: on a phone, videos are drawn straight from the video chip unless switched off.
  test('how videos are drawn', () {
    final direct = videoDrawing(direct: true, android: true);
    expect(direct.vo, 'mediacodec_embed');
    expect(direct.hwdec, 'mediacodec');
    expect(videoDrawing(direct: false, android: true).vo, isNull);
    expect(videoDrawing(direct: true, android: false).vo, isNull);
    // 0.1.58: music videos have no sound to keep time by, so they always draw the usual way.
    expect(musicVideoDrawing.vo, isNull);
    expect(musicVideoDrawing.hwdec, isNull);
  });

  testWidgets('a watched player: start line, a stutter report, and a summary', (tester) async {
    var clock = DateTime(2026, 10, 5, 12);
    var decoderDrops = 0, screenDrops = 0;
    final props = {
      'video-params/w': '1920',
      'video-params/h': '1080',
      'video-format': 'h264',
      'video-params/pixelformat': 'yuv420p',
      'container-fps': '25',
      'hwdec-current': 'no',
      'current-vo': 'gpu',
      'demuxer-cache-duration': '4.5',
    };
    Future<String> read(String name) async => switch (name) {
          'decoder-frame-drop-count' => '$decoderDrops',
          'frame-drop-count' => '$screenDrops',
          _ => props[name] ?? '',
        };
    final stats = VideoStats('Video', read, reportEvery: 2, now: () => clock);

    stats.started('Film');
    await tester.pump(const Duration(seconds: 3));
    expect(PlaybackLog.lines.where((l) => l.contains('Video started: Film · 1920×1080 · H264 · 25 fps')), hasLength(1));
    expect(PlaybackLog.lines.where((l) => l.contains('software (main processor)')), hasLength(1));

    // Ten smooth seconds: nothing logged.
    stats.playing(true);
    await tester.pump(const Duration(seconds: 10));
    expect(PlaybackLog.lines.where((l) => l.contains('stutter')), isEmpty);

    // Then some dropped pictures and a wait for the file.
    decoderDrops = 2;
    screenDrops = 5;
    clock = clock.add(const Duration(seconds: 20)); // past the pause that comes with opening
    // 0.1.58: the viewer skipping ahead is said too.
    stats.moved(const Duration(seconds: 40));
    stats.moved(const Duration(milliseconds: 40300));
    stats.moved(const Duration(seconds: 50));
    stats.buffering(true);
    stats.jumped();
    stats.buffering(true); // the pause after a jump isn't counted
    await tester.pump(const Duration(seconds: 10));
    final stutter = PlaybackLog.lines.where((l) => l.contains('stutter')).toList();
    expect(stutter, hasLength(1));
    expect(stutter.single, contains('7 pictures dropped (decoder 2, screen 5)'));
    expect(stutter.single, contains('jumped back into step 1 time · paused to load 1 time'));
    expect(stutter.single, contains('read ahead 4.5 s'));
    expect(stutter.single, contains('you skipped or moved it once'));

    // Closing sums it up.
    clock = clock.add(const Duration(minutes: 1, seconds: 10));
    stats.dispose();
    expect(PlaybackLog.lines.last, contains('Video finished: Film · played 1:30 · 7 pictures dropped, jumped back into step 1 time, paused to load 1 time'));
    await tester.pump(const Duration(seconds: 10)); // no timers left running
  });
}
