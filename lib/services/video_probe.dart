// What's inside a video file (0.1.44, for the video Details page): its container, and each
// picture, sound and subtitle track with its codec, language, name, picture size, frame rate,
// channels and sample rate, plus the number of chapters.
//
// The video engine (libmpv) reads this. A hidden, paused, silent player (no sound device, no
// picture decoding) opens the file, the engine's "track-list" is read as soon as it's there
// (usually within a tenth of a second; checked with tool/bench/video_probe_engine_test.dart),
// and the player is closed again. Sound has to stay switched on: with no picture, sound or
// subtitle track chosen the engine closes the file straight away and lists nothing.
// parseVideoProbe turns the engine's answers into a VideoProbe, without the engine (tested).
import 'dart:async';
import 'dart:convert';

import 'package:media_kit/media_kit.dart';

/// One track in a video file.
class ProbeTrack {
  /// 'video', 'audio' or 'sub'.
  final String kind;
  final String? codec;
  final String? language;
  final String? title;
  final bool isDefault;
  final bool forced;
  final bool hearingImpaired;
  final int? width;
  final int? height;
  final double? fps;
  final int? channels;
  final int? sampleRate;

  /// A cover picture stored in the file, not a real video track.
  final bool picture;

  const ProbeTrack({
    required this.kind,
    this.codec,
    this.language,
    this.title,
    this.isDefault = false,
    this.forced = false,
    this.hearingImpaired = false,
    this.width,
    this.height,
    this.fps,
    this.channels,
    this.sampleRate,
    this.picture = false,
  });
}

/// What the engine found in a file.
class VideoProbe {
  /// "mkv", "mov,mp4,m4a,3gp,3g2,mj2"…
  final String? container;
  final Duration duration;
  final List<ProbeTrack> tracks;
  final int chapters;

  const VideoProbe({this.container, this.duration = Duration.zero, this.tracks = const [], this.chapters = 0});

  List<ProbeTrack> get video => [
    for (final t in tracks)
      if (t.kind == 'video' && !t.picture) t,
  ];
  List<ProbeTrack> get audio => [
    for (final t in tracks)
      if (t.kind == 'audio') t,
  ];
  List<ProbeTrack> get subtitles => [
    for (final t in tracks)
      if (t.kind == 'sub') t,
  ];
}

/// Builds a [VideoProbe] from the engine's answers: `file-format`, `duration` (seconds),
/// `track-list` (JSON) and `chapter-list/count`.
VideoProbe parseVideoProbe({String? format, String? duration, String? trackList, String? chapters}) {
  final tracks = <ProbeTrack>[];
  try {
    final list = jsonDecode(trackList ?? '[]');
    if (list is List) {
      for (final t in list.whereType<Map>()) {
        String? s(String k) {
          final v = t[k];
          return v is String && v.trim().isNotEmpty ? v.trim() : null;
        }

        int? i(String k) => t[k] is num ? (t[k] as num).round() : null;
        final kind = s('type');
        if (kind == null) continue;
        tracks.add(
          ProbeTrack(
            kind: kind,
            codec: s('codec'),
            language: s('lang'),
            title: s('title'),
            isDefault: t['default'] == true,
            forced: t['forced'] == true,
            hearingImpaired: t['hearing-impaired'] == true,
            width: i('demux-w'),
            height: i('demux-h'),
            fps: t['demux-fps'] is num ? (t['demux-fps'] as num).toDouble() : null,
            channels: i('demux-channel-count'),
            sampleRate: i('demux-samplerate'),
            picture: t['image'] == true || t['albumart'] == true,
          ),
        );
      }
    }
  } catch (_) {
    // Not JSON: no tracks.
  }
  final secs = double.tryParse(duration ?? '');
  return VideoProbe(
    container: (format == null || format.trim().isEmpty) ? null : format.trim(),
    duration: secs == null ? Duration.zero : Duration(milliseconds: (secs * 1000).round()),
    tracks: tracks,
    chapters: int.tryParse(chapters ?? '') ?? 0,
  );
}

/// Asks the engine what's inside [path]. Null when it couldn't be opened. Never throws.
Future<VideoProbe?> probeVideo(String path, {Duration timeout = const Duration(seconds: 10)}) async {
  Player? player;
  try {
    player = Player(configuration: const PlayerConfiguration(title: 'HomeTunes details'));
    final engine = player.platform;
    if (engine is! NativePlayer) return null;
    // No sound device and no subtitles; no picture is decoded without a video view (vid=no).
    await engine.setProperty('ao', 'null');
    await engine.setProperty('sid', 'no');
    await player.setVolume(0);
    await player.open(Media(path), play: false);
    final end = DateTime.now().add(timeout);
    while ((int.tryParse(await engine.getProperty('track-list/count')) ?? 0) == 0) {
      if (DateTime.now().isAfter(end)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return parseVideoProbe(
      format: await engine.getProperty('file-format'),
      duration: await engine.getProperty('duration'),
      trackList: await engine.getProperty('track-list'),
      chapters: await engine.getProperty('chapter-list/count'),
    );
  } catch (_) {
    return null;
  } finally {
    await player?.dispose();
  }
}
