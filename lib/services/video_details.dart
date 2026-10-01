// "Where does this come from?" for videos (0.1.44): reads one video's folders, file name, .nfo
// files and tags again and works out, for each detail the Videos tab shows, where it came from:
// its own .nfo file, the series' tvshow.nfo, the file's tags (MP4 / M4V / MOV), the folder or
// file name, the video itself (length and picture size, learned when its picture was made), or
// the user's own edit. Also lists the files beside it that HomeTunes uses (.nfo files, the
// collection's poster, subtitle files) and what the .nfo file and the tags say.
//
// Used by the video Details page (ui/screens/video_details_screen.dart), like media_details.dart
// for songs and books. Nothing here changes any file. What's inside the file itself (its tracks)
// comes from the video engine instead: video_probe.dart.
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../models/video_item.dart';
import 'media_details.dart';
import 'video_names.dart';
import 'video_nfo.dart';

/// Everything the video Details page shows about one video's file and details.
class VideoFileReport {
  final bool exists;
  final String folder;
  final String fileName;
  final String format;
  final int? sizeBytes;
  final DateTime? modified;

  /// The video folder (Settings › Folders & scanning) it was found in, if it's still one.
  final String? videoFolder;
  final List<DetailRow> rows;

  /// Other files HomeTunes uses (name, what for).
  final List<(String, String)> besideIt;

  /// What the video's .nfo file says, and what the file's tags say ("Title" → "…").
  final List<(String, String)> nfoSays;
  final List<(String, String)> tagsSay;
  final String? problem;

  const VideoFileReport({
    required this.exists,
    required this.folder,
    required this.fileName,
    required this.format,
    this.sizeBytes,
    this.modified,
    this.videoFolder,
    this.rows = const [],
    this.besideIt = const [],
    this.nfoSays = const [],
    this.tagsSay = const [],
    this.problem,
  });
}

/// Reads [scanned] (the video as the scan saw it) and [shown] (with the user's edits) again and
/// explains every detail, in the background. [roots] are the video folders; [ownPicture] whether
/// the user chose its picture; [ownSeasonTitle] whether they named its season.
Future<VideoFileReport> inspectVideo({
  required VideoItem shown,
  required VideoItem scanned,
  required List<String> roots,
  bool ownPicture = false,
  bool ownSeasonTitle = false,
}) => Isolate.run(
  () => inspectVideoNow(
    shown: shown,
    scanned: scanned,
    roots: roots,
    ownPicture: ownPicture,
    ownSeasonTitle: ownSeasonTitle,
  ),
);

VideoFileReport inspectVideoNow({
  required VideoItem shown,
  required VideoItem scanned,
  required List<String> roots,
  bool ownPicture = false,
  bool ownSeasonTitle = false,
}) {
  final path = scanned.path;
  final file = File(path);
  final exists = file.existsSync();
  final folder = p.dirname(path);
  final stat = exists ? file.statSync() : null;
  final root = roots
      .where((r) => p.isWithin(r, path))
      .fold<String?>(null, (best, r) => best == null || r.length > best.length ? r : best); // the innermost
  final info = root == null ? null : describeVideoPath(root, path);

  // The .nfo files, as the scan finds them (any case).
  File? named(String dir, String name) {
    try {
      return Directory(dir)
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => p.basename(f.path).toLowerCase() == name.toLowerCase())
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  final nfoFile = named(folder, p.basename(nfoPathFor(path)));
  final showFile = info == null ? null : named(info.collectionFolder, showNfoName);
  final nfo = nfoFile == null ? null : readNfo(nfoFile.path);
  final show = showFile == null ? null : readNfo(showFile.path);
  final nfoName = nfoFile == null ? null : p.basename(nfoFile.path);
  final showName = showFile == null ? null : _relative(showFile.path, folder);

  // MP4-style tags.
  AudioMetadata? tags;
  String? problem;
  if (!exists) {
    problem = 'The file isn\'t there any more. These details are from the last time it was found.';
  } else if (const {'.mp4', '.m4v', '.mov'}.contains(p.extension(path).toLowerCase())) {
    try {
      tags = readMetadata(file, getImage: false);
    } catch (_) {
      // No readable tags: nothing to say about them.
    }
  }
  String? clean(String? s) {
    final t = s?.replaceAll('\u0000', '').trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  var tagTitle = clean(tags?.title);
  if (tagTitle != null && tagTitle.toLowerCase() == p.basenameWithoutExtension(path).toLowerCase()) tagTitle = null;
  final tagGenre = (tags == null || tags.genres.isEmpty) ? null : clean(tags.genres.first);
  final ty = tags?.year?.year;
  final tagYear = (ty != null && ty > 1800) ? ty : null;

  // What the file name and the folders each say on their own.
  final fileName = p.basenameWithoutExtension(path);
  final fromFile = parseEpisodeName(fileName);
  final fileClean = cleanVideoName(fileName);
  final collectionFolderName = info == null ? null : p.basename(info.collectionFolder);
  final looseFilm = info != null && p.equals(info.collectionFolder, folder) && info.collection == fileClean.title;

  String? str(Object? o) => o?.toString();
  DetailRow row(
    String label,
    String? scannedValue,
    String? shownValue, {
    String? fromNfo,
    String? fromShow,
    String? fromTags,
    String? fromFolder,
    String? folderName,
    String? fromFileName,
    bool editedElsewhere = false,
  }) {
    final s = scannedValue ?? '', v = shownValue ?? '';
    if (v != s || editedElsewhere) {
      return DetailRow(label, v.isEmpty ? '–' : v, DetailSource.edit, inFile: s.isEmpty ? '–' : s);
    }
    if (v.isEmpty) return DetailRow(label, '–', DetailSource.notSet);
    if (fromNfo != null && fromNfo == s) return DetailRow(label, v, DetailSource.nfoFile, from: nfoName);
    if (fromShow != null && fromShow == s) return DetailRow(label, v, DetailSource.showNfo, from: showName);
    if (fromTags != null && fromTags == s) return DetailRow(label, v, DetailSource.tags);
    if (fromFileName != null && fromFileName == s) return DetailRow(label, v, DetailSource.fileName);
    if (fromFolder != null && fromFolder == s) return DetailRow(label, v, DetailSource.folderName, from: folderName);
    return DetailRow(label, v, DetailSource.unknown);
  }

  // The season folder (the one that names the season), if any.
  String? seasonFolder;
  if (root != null) {
    for (final d in p.split(p.relative(folder, from: root))) {
      if (seasonOfFolder(d) != null && !isExtrasFolder(d)) seasonFolder = d;
    }
  }
  final extrasFolder = root == null ? null : p.split(p.relative(folder, from: root)).where(isExtrasFolder).firstOrNull;

  final rows = <DetailRow>[
    row(
      'Title',
      scanned.title,
      shown.title,
      fromNfo: nfo?.title,
      fromTags: tagTitle,
      fromFileName: info?.title ?? fileClean.title,
    ),
    row(
      'Collection',
      scanned.collection,
      shown.collection,
      fromNfo: nfo?.showTitle ?? nfo?.set,
      fromShow: show?.title,
      fromFileName: looseFilm ? info.collection : null,
      fromFolder: info?.collection,
      folderName: collectionFolderName,
    ),
    row('Category', scanned.category, shown.category, fromFolder: info?.category, folderName: info?.category),
    row(
      'Season',
      str(scanned.seasonLabel),
      str(shown.seasonLabel),
      fromNfo: str(nfo?.season),
      fromFileName: str(fromFile.season),
      fromFolder: seasonFolder == null
          ? null
          : str(seasonText(seasonOfFolder(seasonFolder)!, subSeasonOfFolder(seasonFolder))),
      folderName: seasonFolder,
    ),
    row(
      'Episode',
      str(scanned.episode),
      str(shown.episode),
      fromNfo: str(nfo?.episode),
      fromFileName: str(fromFile.episode),
    ),
    if (scanned.seasonTitle != null || shown.seasonTitle != null || ownSeasonTitle)
      row(
        'Season title',
        scanned.seasonTitle,
        shown.seasonTitle,
        fromShow: scanned.season == null ? null : show?.namedSeasons[scanned.season],
        fromFolder: info?.seasonTitle,
        folderName: seasonFolder,
        editedElsewhere: ownSeasonTitle,
      ),
    row(
      'Year',
      str(scanned.year),
      str(shown.year),
      fromNfo: str(nfo?.year),
      fromTags: str(tagYear),
      fromFileName: str(fileClean.year),
      fromFolder: str(info?.year),
      folderName: collectionFolderName,
    ),
    row('Genre', scanned.genre, shown.genre, fromNfo: nfo?.genre, fromTags: tagGenre, fromShow: show?.genre),
    _short(row('Description', scanned.description, shown.description, fromNfo: nfo?.plot)),
    if (scanned.extra || shown.extra)
      DetailRow(
        'Kind',
        shown.extra ? 'Extra' : 'Episode',
        scanned.extra == shown.extra ? DetailSource.folderName : DetailSource.edit,
        from: scanned.extra == shown.extra ? extrasFolder : null,
      ),
    // Length: MP4 tags, else learned from the video when its picture was made (or it played).
    DetailRow(
      'Length',
      shown.duration == Duration.zero ? '–' : _length(shown.duration),
      shown.duration == Duration.zero
          ? DetailSource.notSet
          : (tags?.duration != null && tags!.duration == scanned.duration ? DetailSource.tags : DetailSource.fromVideo),
    ),
    DetailRow(
      'Picture size',
      shown.resolution ?? '–',
      shown.resolution == null ? DetailSource.notSet : DetailSource.fromVideo,
    ),
    DetailRow(
      'Picture',
      ownPicture ? 'Picture you chose' : (shown.thumb != null ? 'A frame from the video' : 'None yet'),
      ownPicture ? DetailSource.edit : (shown.thumb != null ? DetailSource.frame : DetailSource.notSet),
    ),
  ];

  final beside = <(String, String)>[
    if (nfoName != null) (nfoName, 'Details (.nfo file)'),
    if (showName != null) (showName, 'The series\' details (.nfo file)'),
    if (scanned.cover != null) (_relative(scanned.cover!, folder), 'The collection\'s poster'),
    for (final s in scanned.subtitles) (_relative(s, folder), 'Subtitles: ${subtitleLabel(s, path)}'),
  ];

  final nfoSays = <(String, String)>[
    if (nfo != null) ...[
      if (nfo.title != null) ('Title', nfo.title!),
      if (nfo.showTitle != null) ('Series', nfo.showTitle!),
      if (nfo.set != null) ('Collection', nfo.set!),
      if (nfo.season != null) ('Season', '${nfo.season}'),
      if (nfo.episode != null) ('Episode', '${nfo.episode}'),
      if (nfo.year != null) ('Year', '${nfo.year}'),
      if (nfo.genre != null) ('Genre', nfo.genre!),
      if (nfo.plot != null) ('Description', _cut(nfo.plot!)),
    ],
  ];
  final tagsSay = <(String, String)>[
    if (tags != null) ...[
      ('Title', clean(tags.title) ?? '–'),
      ('Year', tagYear?.toString() ?? '–'),
      ('Genre', tags.genres.isEmpty ? '–' : tags.genres.join(', ')),
      ('Length', tags.duration == null ? '–' : _length(tags.duration!)),
    ],
  ];

  return VideoFileReport(
    exists: exists,
    folder: folder,
    fileName: p.basename(path),
    format: scanned.format,
    sizeBytes: stat?.size ?? scanned.sizeBytes,
    modified: stat?.modified,
    videoFolder: root,
    rows: rows,
    besideIt: beside,
    nfoSays: nfoSays,
    tagsSay: tagsSay,
    problem: problem,
  );
}

DetailRow _short(DetailRow r) => r.shown.length <= 80
    ? r
    : DetailRow(r.label, _cut(r.shown), r.source, from: r.from, inFile: r.inFile == null ? null : _cut(r.inFile!));

String _cut(String s) => s.length > 80 ? '${s.substring(0, 80)}…' : s;

String _length(Duration d) {
  final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// A file's name, with its folder when it's not beside the video ("Subs\English.srt").
String _relative(String path, String folder) {
  if (p.equals(p.dirname(path), folder)) return p.basename(path);
  if (p.isWithin(folder, path)) return p.relative(path, from: folder);
  return '${p.basename(p.dirname(path))}${p.separator}${p.basename(path)}';
}
