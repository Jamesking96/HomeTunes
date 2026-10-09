// Videos (0.1.40): a small picture for each video on the Videos tab.
//
// One hidden, silent player opens each video in turn (pictures only, paused), jumps a tenth of
// the way in, takes a screenshot, then the picture is shrunk to 480 px wide and saved as a JPEG
// in art/video/ (a full-size frame from a 4K video is ~4 MB; the saved one is ~30 KB). It also
// learns the video's real length and picture size on the way. Checked on the real engine: about
// half a second per video. VideoLibraryModel runs this in the background after a scan, one video
// at a time, so it never competes with playback for long.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import 'engine/engines.dart';

/// What was learned about one video.
class VideoFacts {
  /// The saved picture, or null if none could be taken.
  final String? thumb;
  final Duration duration;
  final int? width;
  final int? height;
  const VideoFacts({this.thumb, this.duration = Duration.zero, this.width, this.height});
}

/// Makes thumbnails with one reusable hidden player. Call [dispose] when done.
class VideoThumbnailer {
  /// Where pictures are saved (Storage.artDir/video).
  final String dir;
  VideoThumbnailer(this.dir);

  Player? _player;

  /// Width of the saved picture.
  static const width = 480;

  /// The file name a video's picture is saved under: changes when the video file changes.
  static String nameFor(String path, int? modifiedMs) => '${md5.convert('$path|$modifiedMs'.codeUnits)}.jpg';

  Future<Player> _open() async {
    final existing = _player;
    if (existing != null) return existing;
    final player = createEngine(EngineUse.thumbnails);
    // Pictures only: no sound, no subtitles. media_kit starts every player with vid=no.
    await prepareEngine(player, EngineUse.thumbnails);
    await player.setVolume(0);
    return _player = player;
  }

  /// Opens [path], takes a picture and reports what it found. Never throws.
  Future<VideoFacts> make(String path, {int? modifiedMs}) async {
    try {
      final player = await _open();
      await player.open(Media(path), play: false);
      // Wait until the engine knows the length and has a picture size.
      final ready = await _waitFor(() => player.state.duration > Duration.zero && (player.state.width ?? 0) > 0);
      final duration = player.state.duration;
      final w = player.state.width, h = player.state.height;
      if (!ready) return VideoFacts(duration: duration, width: w, height: h);
      // A tenth of the way in (openings are often black), at most a minute.
      var at = duration * 0.1;
      if (at > const Duration(minutes: 1)) at = const Duration(minutes: 1);
      await player.seek(at);
      await _waitFor(() => (player.state.position - at).abs() < const Duration(milliseconds: 500),
          timeout: const Duration(seconds: 3));
      // The first request right after a seek can come back empty: try a few times.
      List<int>? shot;
      for (var i = 0; i < 20 && shot == null; i++) {
        shot = await player.screenshot(format: 'image/jpeg');
        if (shot == null) await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await player.stop();
      if (shot == null) return VideoFacts(duration: duration, width: w, height: h);
      final small = await shrinkToJpeg(shot, width: width);
      if (small == null) return VideoFacts(duration: duration, width: w, height: h);
      await Directory(dir).create(recursive: true);
      final file = File(p.join(dir, nameFor(path, modifiedMs)));
      await file.writeAsBytes(small, flush: true);
      return VideoFacts(thumb: file.path, duration: duration, width: w, height: h);
    } catch (_) {
      return const VideoFacts();
    }
  }

  Future<bool> _waitFor(bool Function() ok, {Duration timeout = const Duration(seconds: 8)}) async {
    final end = DateTime.now().add(timeout);
    while (!ok()) {
      if (DateTime.now().isAfter(end)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return true;
  }

  Future<void> dispose() async {
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}

/// Shrinks a picture (any format Flutter can read) to [width] pixels wide, as a JPEG.
/// Flutter's own decoder does the heavy part (it can decode straight to the small size), so a
/// 4K frame takes a few milliseconds. Null if the picture can't be read.
/// With [onlyShrink], a picture that's already narrower keeps its size (chosen pictures and
/// posters: never blown up).
Future<List<int>?> shrinkToJpeg(List<int> bytes,
    {int width = VideoThumbnailer.width, int quality = 80, bool onlyShrink = false}) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes));
    final codec = await ui.instantiateImageCodecWithSize(buffer,
        getTargetSize: (w, h) => (onlyShrink && w <= width) ? const ui.TargetImageSize() : ui.TargetImageSize(width: width));
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = image.width, h = image.height;
    image.dispose();
    codec.dispose();
    if (data == null) return null;
    final picture = img.Image.fromBytes(width: w, height: h, bytes: data.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
    return img.encodeJpg(picture, quality: quality);
  } catch (_) {
    return null;
  }
}
