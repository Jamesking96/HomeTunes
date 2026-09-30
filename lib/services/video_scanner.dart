// Videos (0.1.32): finds the video files in the video folders and turns them into VideoItems.
//
// Like the music scanner (local_scanner.dart), the folder walk and the reading happen in a
// background isolate, and a file whose modified time hasn't changed is reused rather than read
// again (so its thumbnail, length and "added" date are kept). VideoLibraryModel.scan() calls it.
// Any common video format is picked up; whether it actually plays depends on the engine (libmpv
// with FFmpeg), which reads practically everything.
// Each video's collection, category, season, episode and title come from its folders and file
// name (video_names.dart), with the title, year and genre from its tags where there are any
// (MP4, M4V and MOV files). A poster picture in the collection's folder becomes the collection's
// cover, and subtitle files beside the video (or in a Subs folder) are listed so they can be
// offered as choices while it plays. The user can change all of the details (VideoEdit).
// An .nfo file beside the video (Kodi / Jellyfin style, see video_nfo.dart) wins over all of
// that, and a tvshow.nfo in the collection's folder names the collection and describes it.
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../models/video_item.dart';
import 'video_names.dart';
import 'video_nfo.dart';

/// Every file type the Videos tab lists.
const videoFileExtensions = {
  '.mp4', '.m4v', '.mkv', '.webm', '.mov', '.avi', '.wmv', '.flv', '.mpg', '.mpeg', '.m2ts', '.mts',
  '.ts', '.3gp', '.ogv', '.vob', '.divx', '.asf',
};

/// The ones with MP4-style tags that can be read for a title, year and genre.
const _taggedExtensions = {'.mp4', '.m4v', '.mov'};

/// The current version of the name-reading rules. Videos saved by an older one are read again
/// once (keeping their thumbnail, length and "added" date).
const videoScanVersion = 4; // 3: .nfo files; 4: season titles

/// Picture names that are a collection's poster, best first (lower case, without extension).
const _posterNames = ['poster', 'folder', 'cover', 'season-all-poster', 'show', 'movie'];
const _pictureExtensions = {'.jpg', '.jpeg', '.png', '.webp'};

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

  // Each folder's files, listed once.
  final Map<String, List<File>> _listed = {};
  List<File> _files(String dir) => _listed.putIfAbsent(dir, () {
        try {
          return Directory(dir).listSync(followLinks: false).whereType<File>().toList();
        } catch (_) {
          return const <File>[];
        }
      });

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
        _listed[dir.path] = entries.whereType<File>().toList();
        for (final e in entries) {
          if (e is Directory) {
            pending.add(e);
          } else if (e is File && videoFileExtensions.contains(p.extension(e.path).toLowerCase())) {
            if (!seen.add(e.path)) continue; // overlapping folders: once
            try {
              out.add(_one(root, e));
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

  Map<String, dynamic> _one(String root, File file) {
    final stat = file.statSync();
    final modified = stat.modified.millisecondsSinceEpoch;
    final prev = previous[VideoItem.idFor(file.path)];
    final unchanged = prev != null && prev['modifiedMs'] == modified;
    // Subtitle files and the poster can change without the video changing: looked for each time.
    final subs = findSubtitles(file.path, _files);
    // So are .nfo files (the video's own, and the series' tvshow.nfo).
    final info = describeVideoPath(root, file.path);
    File? named(String dir, String name) =>
        _files(dir).where((f) => p.basename(f.path).toLowerCase() == name.toLowerCase()).firstOrNull;
    final nfoFile = named(p.dirname(file.path), p.basename(nfoPathFor(file.path)));
    final showFile = named(info.collectionFolder, showNfoName);
    int? stamp(File? f) {
      try {
        return f?.statSync().modified.millisecondsSinceEpoch;
      } catch (_) {
        return null;
      }
    }

    final nfoStamps = [stamp(nfoFile), stamp(showFile)].whereType<int>();
    final nfoMs = nfoStamps.isEmpty ? null : nfoStamps.reduce((a, b) => a + b);
    if (unchanged && (prev['scan'] as int? ?? 0) >= videoScanVersion && prev['nfoMs'] == nfoMs) {
      return {...prev, 'subtitles': subs}..removeWhere((k, v) => k == 'subtitles' && (v as List).isEmpty);
    }
    final json = readVideo(file.path, modified, stat.size,
            info: info,
            addedMs: prev?['addedMs'] as int? ?? now,
            nfo: nfoFile == null ? null : readNfo(nfoFile.path),
            show: showFile == null ? null : readNfo(showFile.path),
            nfoMs: nfoMs)
        .toJson();
    json['cover'] = findCover(info.collectionFolder, file.path, _files);
    json['subtitles'] = subs;
    json.removeWhere((k, v) => v == null || (k == 'subtitles' && (v as List).isEmpty));
    // Re-read because the rules changed, not the file: keep what was learned about it.
    if (unchanged) {
      for (final k in ['thumb', 'width', 'height']) {
        if (prev[k] != null) json[k] = prev[k];
      }
      if ((json['durationMs'] as int? ?? 0) == 0 && prev['durationMs'] != null) json['durationMs'] = prev['durationMs'];
    }
    return json;
  }
}

/// Reads one video's details. Never throws on bad tags: falls back to what [info] (its folders
/// and file name) says. What its own .nfo ([nfo]) says wins over the tags and the name; the
/// series' tvshow.nfo ([show]) gives the collection's name, genre and description.
VideoItem readVideo(String path, int modifiedMs, int sizeBytes,
    {required VideoPathInfo info, int? addedMs, NfoInfo? nfo, NfoInfo? show, int? nfoMs}) {
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
  // A tag title that's just the file name again says nothing new.
  if (title != null && title.toLowerCase() == p.basenameWithoutExtension(path).toLowerCase()) title = null;
  final season = nfo?.season ?? info.season;
  final episode = nfo?.episode ?? info.episode;
  return VideoItem(
    id: VideoItem.idFor(path),
    path: path,
    title: nfo?.title ?? title ?? info.title,
    collection: nfo?.showTitle ?? nfo?.set ?? show?.title ?? info.collection,
    category: info.category,
    season: season,
    episode: episode,
    part: info.part,
    // The series' tvshow.nfo names seasons (HomeTunes saves the user's names there too); else
    // the season folder's own title ("Season 1 - Offline News").
    seasonTitle: season == null || season == 0
        ? null
        : (show?.namedSeasons[season] ?? (season == info.season ? info.seasonTitle : null)),
    // An .nfo that numbers it makes it an episode, even in an Extras folder.
    extra: info.extra && nfo?.season == null && nfo?.episode == null,
    year: nfo?.year ?? year ?? info.year,
    genre: nfo?.genre ?? genre ?? show?.genre,
    description: nfo?.plot,
    duration: duration,
    modifiedMs: modifiedMs,
    sizeBytes: sizeBytes,
    addedMs: addedMs,
    scan: videoScanVersion,
    showPlot: show?.plot,
    nfoMs: nfoMs,
  );
}

/// A poster picture for a collection: poster.jpg, folder.jpg, cover.jpg… in its folder (any
/// case), or a picture named like the video. Null when there's none.
String? findCover(String collectionFolder, String videoPath, List<File> Function(String dir) files) {
  final pictures = [
    for (final f in files(collectionFolder))
      if (_pictureExtensions.contains(p.extension(f.path).toLowerCase())) f.path
  ];
  for (final name in _posterNames) {
    for (final f in pictures) {
      if (p.basenameWithoutExtension(f).toLowerCase() == name) return f;
    }
  }
  final video = p.basenameWithoutExtension(videoPath).toLowerCase();
  for (final f in [
    ...pictures,
    for (final g in files(p.dirname(videoPath))) if (_pictureExtensions.contains(p.extension(g.path).toLowerCase())) g.path
  ]) {
    if (p.basenameWithoutExtension(f).toLowerCase() == video) return f;
  }
  return null;
}

/// Subtitle files for a video: beside it with the same name ("Film.srt", "Film.en.srt"), or in a
/// Subs / Subtitles folder, either in a folder named after the video ("Subs\Film\3_English.srt")
/// or named after it ("Subs\Film.English.srt").
List<String> findSubtitles(String videoPath, List<File> Function(String dir) files) {
  final dir = p.dirname(videoPath);
  final base = p.basenameWithoutExtension(videoPath).toLowerCase();
  bool isSub(String f) => subtitleExtensions.contains(p.extension(f).toLowerCase());
  final out = <String>[
    for (final f in files(dir))
      if (isSub(f.path) && p.basenameWithoutExtension(f.path).toLowerCase().startsWith(base)) f.path
  ];
  for (final name in const ['Subs', 'subs', 'Subtitles', 'subtitles', 'Sub', 'subs_folder']) {
    final subs = p.join(dir, name);
    if (!Directory(subs).existsSync()) continue;
    for (final f in files(subs)) {
      if (isSub(f.path) && p.basenameWithoutExtension(f.path).toLowerCase().startsWith(base)) out.add(f.path);
    }
    for (final f in files(p.join(subs, p.basenameWithoutExtension(videoPath)))) {
      if (isSub(f.path)) out.add(f.path);
    }
    break; // Windows folder names ignore case: one is enough
  }
  return {...out}.toList()..sort();
}

/// A readable title (and a year, if there's one) from a file name.
/// "My.Film.2019.1080p.BluRay" → ("My Film", 2019); "Holiday day 1" → ("Holiday day 1", null).
({String title, int? year}) videoNameFromFile(String name) => cleanVideoName(name);

String? _clean(String? s) {
  if (s == null) return null;
  final t = s.replaceAll('\u0000', '').trim();
  return t.isEmpty ? null : t;
}
