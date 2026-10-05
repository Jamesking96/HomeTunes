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

/// The video controller setup for this device. [android] is for tests.
VideoControllerConfiguration videoDrawing({required bool direct, bool? android}) {
  if ((android ?? Platform.isAndroid) && direct) {
    return const VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec');
  }
  return const VideoControllerConfiguration();
}
