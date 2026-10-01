// Music videos (0.1.40): finding the video that goes with a song.
//
// Downloaders such as the YouTube offline player save a song twice, side by side:
//   "Miley Cyrus - Flowers (Official Video).m4a"   (the sound)
//   "Miley Cyrus - Flowers (Official Video).mp4"   (the video, with the same sound in it)
// Before 0.1.40 both were scanned as songs, so every such song showed up twice. Now:
//  * an audio file with a video of the same name beside it is the song, and the video is its
//    music video (Track.video). The video file is not listed as a song of its own;
//  * an .mp4 on its own is still a song (it plays as audio, as before). If it really has
//    pictures in it (mp4HasVideo), it is also its own music video;
//  * an .mp4 with no pictures (just sound) is simply a song, with no video.
// The scanner (local_scanner.dart) calls pairMusicVideos on every scan, so adding or removing a
// video beside a song is picked up by the next scan even when the song itself hasn't changed.
// Nothing here uses Flutter, so it's unit tested directly (test/music_video_test.dart).
import 'dart:io';

import 'package:path/path.dart' as p;

/// Files that can hold a music video. Only .mp4 is also scanned as a song on its own (it was
/// before 0.1.40); the others only count as the video beside a song.
const videoExtensions = {'.mp4', '.m4v', '.webm', '.mkv', '.mov'};

/// Sound-only song files (every scanned song type except .mp4).
const _soundOnly = {'.mp3', '.flac', '.m4a', '.m4b', '.aac', '.ogg', '.opus', '.wav'};

/// Which video wins when a song has more than one beside it.
int _videoRank(String path) => switch (p.extension(path).toLowerCase()) {
      '.mp4' => 0,
      '.m4v' => 1,
      '.webm' => 2,
      '.mkv' => 3,
      _ => 4,
    };

/// Splits a folder listing into the files to scan as songs and each song's video.
///
/// [files] is every song file and video file found. Files pair up when they're in the same folder
/// and their names match apart from the extension (ignoring upper and lower case). Returns the
/// song files in the order they came in, and a map from a song file to its video file.
({List<String> songs, Map<String, String> videos}) pairMusicVideos(
  Iterable<String> files, {
  required Set<String> songExtensions,
}) {
  // Group by folder + name without the extension.
  final groups = <String, List<String>>{};
  for (final f in files) {
    final key = p.join(p.dirname(f), p.basenameWithoutExtension(f)).toLowerCase();
    (groups[key] ??= []).add(f);
  }
  final videoOf = <String, String>{};
  final hidden = <String>{}; // videos that belong to a song, so aren't songs themselves
  for (final group in groups.values) {
    final sounds = [for (final f in group) if (_soundOnly.contains(p.extension(f).toLowerCase())) f];
    final videos = [for (final f in group) if (videoExtensions.contains(p.extension(f).toLowerCase())) f]
      ..sort((a, b) => _videoRank(a).compareTo(_videoRank(b)));
    if (sounds.isEmpty || videos.isEmpty) continue;
    for (final s in sounds) {
      videoOf[s] = videos.first;
    }
    hidden.addAll(videos);
  }
  final songs = [
    for (final f in files)
      if (!hidden.contains(f) && songExtensions.contains(p.extension(f).toLowerCase())) f,
  ];
  return (songs: songs, videos: videoOf);
}

/// Video formats inside an MP4 that are real moving pictures. Audiobooks can carry chapter
/// pictures as a 'jpeg' or 'png ' track, which don't count.
const _movingPictureCodecs = {'avc1', 'avc3', 'hvc1', 'hev1', 'av01', 'vp08', 'vp09', 'mp4v', 'dvh1', 'dvhe'};

/// Whether the MP4 / M4V / MOV file at [path] has a video track with moving pictures.
///
/// Only reads the headers of the boxes it needs (moov > trak > mdia > hdlr, and the first
/// sample description), skipping everything else, so it's quick even for big files. Returns
/// false for anything it can't read.
bool mp4HasVideo(String path) {
  RandomAccessFile? f;
  try {
    f = File(path).openSync();
    final length = f.lengthSync();
    final moov = _find(f, 0, length, 'moov');
    if (moov == null) return false;
    for (final trak in _boxes(f, moov.$1, moov.$2)) {
      if (trak.$3 != 'trak') continue;
      final mdia = _find(f, trak.$1, trak.$2, 'mdia');
      if (mdia == null) continue;
      final hdlr = _find(f, mdia.$1, mdia.$2, 'hdlr');
      // hdlr: version and flags (4 bytes), pre_defined (4), then the handler type.
      if (hdlr == null || _text(f, hdlr.$1 + 8, 4) != 'vide') continue;
      final minf = _find(f, mdia.$1, mdia.$2, 'minf');
      final stbl = minf == null ? null : _find(f, minf.$1, minf.$2, 'stbl');
      final stsd = stbl == null ? null : _find(f, stbl.$1, stbl.$2, 'stsd');
      // stsd: version and flags (4), entry count (4), then the first entry's size (4) and format.
      if (stsd == null) continue;
      if (_movingPictureCodecs.contains(_text(f, stsd.$1 + 12, 4))) return true;
    }
    return false;
  } catch (_) {
    return false;
  } finally {
    try {
      f?.closeSync();
    } catch (_) {}
  }
}

/// The first box of [type] directly inside the range: (body start, box end).
(int, int)? _find(RandomAccessFile f, int start, int end, String type) {
  for (final b in _boxes(f, start, end)) {
    if (b.$3 == type) return (b.$1, b.$2);
  }
  return null;
}

/// The boxes directly inside the range [start, end): (body start, box end, type).
Iterable<(int, int, String)> _boxes(RandomAccessFile f, int start, int end) sync* {
  var pos = start;
  var count = 0;
  while (pos + 8 <= end && count++ < 10000) {
    f.setPositionSync(pos);
    final h = f.readSync(8);
    if (h.length < 8) return;
    var size = (h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3];
    final type = String.fromCharCodes(h.sublist(4, 8));
    var header = 8;
    if (size == 1) {
      // A 64-bit size follows the type.
      final big = f.readSync(8);
      if (big.length < 8) return;
      size = 0;
      for (final b in big) {
        size = (size << 8) | b;
      }
      header = 16;
    } else if (size == 0) {
      size = end - pos; // runs to the end
    }
    if (size < header || pos + size > end) return; // damaged: stop rather than guess
    yield (pos + header, pos + size, type);
    pos += size;
  }
}

String _text(RandomAccessFile f, int at, int n) {
  f.setPositionSync(at);
  return String.fromCharCodes(f.readSync(n));
}
