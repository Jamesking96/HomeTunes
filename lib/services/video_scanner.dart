// Videos (0.1.32): finds the video files in the video folders and turns them into VideoItems.
//
// Like the music scanner (local_scanner.dart), the folder walk and the reading happen in a
// background isolate, and a file whose modified time hasn't changed is reused rather than read
// again (so its thumbnail, length and "added" date are kept). VideoLibraryModel.scan() calls it.
// Any common video format is picked up; whether it actually plays depends on the engine (libmpv
// with FFmpeg), which reads practically everything.
// Details come from the file's tags where there are any (MP4, M4V and MOV files), and otherwise
// from the file name ("My.Film.2019.1080p.mkv" → "My Film", 2019). The collection a video is
// grouped under starts as its folder's name. The user can change all of these (VideoEdit).
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../models/video_item.dart';

/// Every file type the Videos tab lists.
const videoFileExtensions = {
  '.mp4', '.m4v', '.mkv', '.webm', '.mov', '.avi', '.wmv', '.flv', '.mpg', '.mpeg', '.m2ts', '.mts',
  '.ts', '.3gp', '.ogv', '.vob', '.divx', '.asf',
};

/// The ones with MP4-style tags that can be read for a title, year and genre.
const _taggedExtensions = {'.mp4', '.m4v', '.mov'};

class VideoScanner {
  /// Finds every video under [folders]. Videos in [previous] (by id) whose file hasn't changed
  /// are reused as they were. [now] stamps newly found videos (tests pass a fixed time).
  Future<List<VideoItem>> scan(List<String> folders, {Map<String, VideoItem> previous = const {}, int? now}) async {
    final prev = {for (final e in previous.entries) e.key: e.value.toJson()};
    final stamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final json = await Isolate.run(_VideoJob(List.of(folders), prev, stamp).run);
    return [for (final j in json) VideoItem.fromJson(j)];
  }
}

class _VideoJob {
  final List<String> folders;
  final Map<String, Map<String, dynamic>> previous;
  final int now;
  _VideoJob(this.folders, this.previous, this.now);

  List<Map<String, dynamic>> run() {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final root in folders) {
      final pending = [Directory(root)];
      while (pending.isNotEmpty) {
        final dir = pending.removeLast();
        List<FileSystemEntity> entries;
        try {
          entries = dir.listSync(followLinks: false);
        } on FileSystemException {
          continue; // one unreadable subfolder doesn't stop the scan
        }
        for (final e in entries) {
          if (e is Directory) {
            pending.add(e);
          } else if (e is File && videoFileExtensions.contains(p.extension(e.path).toLowerCase())) {
            if (!seen.add(e.path)) continue; // overlapping folders: once
            try {
              final stat = e.statSync();
              final modified = stat.modified.millisecondsSinceEpoch;
              final prev = previous[VideoItem.idFor(e.path)];
              if (prev != null && prev['modifiedMs'] == modified) {
                out.add(prev);
              } else {
                final added = prev?['addedMs'] as int? ?? now;
                out.add(readVideo(e.path, modified, stat.size, addedMs: added).toJson());
              }
            } catch (_) {
              // Vanished mid-scan: skip it.
            }
          }
        }
      }
    }
    out.sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
    return out;
  }
}

/// Reads one video's details. Never throws on bad tags: falls back to the file name.
VideoItem readVideo(String path, int modifiedMs, int sizeBytes, {int? addedMs}) {
  String? title, genre;
  int? year;
  var duration = Duration.zero;
  if (_taggedExtensions.contains(p.extension(path).toLowerCase())) {
    try {
      final m = readMetadata(File(path), getImage: false);
      title = _clean(m.title);
      genre = m.genres.isEmpty ? null : _clean(m.genres.first);
      final y = m.year?.year;
      year = (y != null && y > 1800) ? y : null;
      duration = m.duration ?? Duration.zero;
    } catch (_) {
      // No readable tags.
    }
  }
  final fromName = videoNameFromFile(p.basenameWithoutExtension(path));
  return VideoItem(
    id: VideoItem.idFor(path),
    path: path,
    title: title ?? fromName.title,
    collection: p.basename(p.dirname(path)),
    year: year ?? fromName.year,
    genre: genre,
    duration: duration,
    modifiedMs: modifiedMs,
    sizeBytes: sizeBytes,
    addedMs: addedMs,
  );
}

/// A readable title (and a year, if there's one) from a file name.
/// "My.Film.2019.1080p.BluRay" → ("My Film", 2019); "Holiday day 1" → ("Holiday day 1", null).
({String title, int? year}) videoNameFromFile(String name) {
  var t = name;
  // Dots or underscores used instead of spaces.
  if (!t.contains(' ')) t = t.replaceAll(RegExp(r'[._]+'), ' ');
  int? year;
  // A year in brackets, or on its own after the title: keep the title before it.
  final m = RegExp(r'^(.+?)[\s\-]*[\(\[]?((?:19|20)\d\d)[\)\]]?(?:\s.*)?$').firstMatch(t);
  if (m != null && m.group(1)!.trim().isNotEmpty) {
    year = int.parse(m.group(2)!);
    t = m.group(1)!;
  }
  t = t.trim().replaceAll(RegExp(r'\s+'), ' ');
  return (title: t.isEmpty ? name : t, year: year);
}

String? _clean(String? s) {
  if (s == null) return null;
  final t = s.replaceAll('\u0000', '').trim();
  return t.isEmpty ? null : t;
}
