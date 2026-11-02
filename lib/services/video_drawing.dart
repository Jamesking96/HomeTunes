// How videos reach the screen on a phone (0.1.57).
//
// The Playback log (0.1.55/0.1.56) showed that on the phone the video chip decoded every
// picture in time, and the file was read far ahead, but pictures were still dropped on the way
// to the screen. media_kit's usual Android setup decodes on the chip, copies each picture back
// into ordinary memory, then draws it again with the graphics chip ("mediacodec-copy" + "gpu").
// Drawing straight from the video chip ("mediacodec" + "mediacodec_embed") skips the copy and
// the extra drawing step, which is lighter and smoother.
//
// What it gives up: the engine can't draw anything on top of the picture itself. On the phone
// the app already draws subtitles itself (video_player_screen.dart), so nothing is lost there.
// A video the chip can't decode (an unusual format) has nowhere to go and may show a black
// picture; Settings › Videos › "Smoother video on phones" turns this off again.
// Windows and other systems keep media_kit's own setup.
import 'dart:io';

import 'package:media_kit_video/media_kit_video.dart';

/// How a page shows the picture (0.2.8).
enum VideoDrawing {
  /// Not Android, and tests: the engine decodes and draws as it always has; nothing changes.
  none,

  /// Straight from the video chip (Android's "Smoother video"). A picture the chip can't decode
  /// has nowhere to go: sound, but a black screen.
  chip,

  /// The app draws the picture, so anything can be decoded in software.
  app,
}

/// Music videos (a second player with no sound) always use media_kit's own setup (0.1.58): with
/// no sound to keep time by, drawing straight from the chip let the video freeze and then race
/// far ahead of the song.
const musicVideoDrawing = VideoControllerConfiguration();

/// The video controller setup for this device (the Videos tab's player). [android] is for tests.
VideoControllerConfiguration videoDrawing({required bool direct, bool? android}) {
  if ((android ?? Platform.isAndroid) && direct) {
    return const VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec');
  }
  return const VideoControllerConfiguration();
}

/// How the app draws subtitles on Android (the PC's engine draws its own, sized by mpv's
/// `sub-scale`): media_kit's own look, [size] times as big (0.2.8, Settings › Videos ›
/// Subtitle size).
SubtitleViewConfiguration subtitleView({required double size, bool? android}) {
  const usual = SubtitleViewConfiguration();
  return SubtitleViewConfiguration(
    visible: android ?? Platform.isAndroid,
    style: usual.style.copyWith(fontSize: (usual.style.fontSize ?? 32) * size),
  );
}

/// How a video page's session sees the drawing (0.2.8): from the chip on Android with
/// [direct], the app's own on Android otherwise; elsewhere nothing changes.
VideoDrawing pageDrawing({required bool direct, bool? android}) =>
    !(android ?? Platform.isAndroid) ? VideoDrawing.none : (direct ? VideoDrawing.chip : VideoDrawing.app);
