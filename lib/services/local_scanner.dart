// The local music scanner: turns the files in the user's chosen folders into Tracks.
// LibraryModel.scanLocal() creates a LocalScanner and calls scan(); the results are saved in
// library.json. Speed tricks (a big library has thousands of files):
//  - folder walking and tag reading happen in background isolates, never on the UI thread;
//  - files go out in batches to several isolates at once, and results come back in order;
//  - a file whose modified time and side files haven't changed is reused, not re-read.
// Cover art found inside files is saved once into the art/ cache, named by its content.
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' hide Chapter;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/track.dart';
import 'book_sidecar.dart';
import 'music_video.dart';

/// Extensions the scanner picks up.
const audioExtensions = {'.mp3', '.flac', '.m4a', '.m4b', '.mp4', '.aac', '.ogg', '.opus', '.wav'};

/// Image files commonly dropped next to albums.
const _folderArtNames = ['cover.jpg', 'cover.png', 'folder.jpg', 'folder.png', 'front.jpg', 'front.png', 'album.jpg'];

/// Walks music folders and turns audio files into [Track]s.
class LocalScanner {
  /// Where cover images are cached (Storage.artDir).
  final String artDir;

  LocalScanner(this.artDir);

  /// Lists every song file under [folders], and each song's music video (see music_video.dart).
  Future<({List<String> songs, Map<String, String> videos})> findFiles(List<String> folders) =>
      Isolate.run(_ListJob(List.of(folders)).run);

  /// Lists every song file under [folders]. A video beside a song with the same name isn't one.
  Future<List<String>> findAudioFiles(List<String> folders) async => (await findFiles(folders)).songs;

  /// Scans [folders]. Tracks in [previous] whose file hasn't changed are reused
  /// without re-reading tags. [onProgress] gets (done, total).
  Future<List<Track>> scan(
    List<String> folders, {
    Map<String, Track> previous = const {},
    void Function(int done, int total)? onProgress,
  }) async {
    // 1. Find every audio file (sorted by path, so albums stay together).
    // Videos beside songs are left out of the list and given to their songs instead (0.1.32).
    final found = await findFiles(folders);
    final files = found.songs;
    // 2. Cut the list into batches. A local copy of artDir is taken so the isolate job
    //    doesn't need to capture `this`.
    final artDir = this.artDir;
    final batches = [
      for (var i = 0; i < files.length; i += batchSize) files.sublist(i, (i + batchSize).clamp(0, files.length)),
    ];
    // One slot per batch, so results land in the right order however fast each worker is.
    final results = List<List<Track>?>.filled(batches.length, null);
    var next = 0;
    var done = 0;

    // Several background workers read batches at the same time (one per spare
    // CPU core, up to [maxWorkers]); results are put back in folder order.
    Future<void> worker() async {
      while (true) {
        final i = next++;  // safe without locks: this code all runs on one thread
        if (i >= batches.length) return;
        final batch = batches[i];
        // Only the tracks that need (re)reading go to the isolate.
        final prevJson = <String, Map<String, dynamic>>{
          for (final f in batch)
            if (previous['local:$f'] != null) f: previous['local:$f']!.toJson(),
        };
        final videos = {for (final f in batch) if (found.videos[f] != null) f: found.videos[f]!};
        final jsonList = await Isolate.run(_BatchJob(batch, prevJson, artDir, videos).run);  // sent as JSON
        results[i] = [for (final j in jsonList) Track.fromJson(j)];
        done += batch.length;
        onProgress?.call(done, files.length);
      }
    }

    // 3. Start the workers. One core is left free so the app stays smooth while scanning.
    final workers = max(1, min(min(Platform.numberOfProcessors - 1, maxWorkers), batches.length));
    await Future.wait([for (var w = 0; w < workers; w++) worker()]);
    // 4. Join the batches back into one list.
    return [for (final r in results) ...?r];
  }

  /// Files per background job, and how many jobs run at once.
  static const batchSize = 60;
  static const maxWorkers = 6;

  /// Deletes cached cover images that no track uses any more
  /// (album removed, or its embedded art changed).
  Future<void> removeUnusedArt(List<Track> tracks) async {
    final used = {for (final t in tracks) if (t.art != null) p.normalize(t.art!)};
    final dir = Directory(artDir);
    if (!await dir.exists()) return;
    // Only our own cache files (*.img) are removed; folder covers like cover.jpg are
    // the user's files and are never touched. art/custom/ is a subfolder, so it's skipped.
    await for (final e in dir.list()) {
      final leftoverTemp = e.path.endsWith('.tmp'); // from a scan that was interrupted
      if (e is File && (leftoverTemp || (p.extension(e.path) == '.img' && !used.contains(p.normalize(e.path))))) {
        try {
          await e.delete();
        } catch (_) {
          // In use or already gone: try again next scan.
        }
      }
    }
  }
}

/// Walks folders in a background isolate.
class _ListJob {
  final List<String> folders;
  _ListJob(this.folders);

  ({List<String> songs, Map<String, String> videos}) run() {
    final out = <String>[];
    final seen = <String>{};
    final pending = [for (final f in folders) Directory(f)];
    // Walk one folder at a time so a single unreadable subfolder
    // (e.g. "System Volume Information") doesn't stop the whole scan.
    while (pending.isNotEmpty) {
      final dir = pending.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final e in entries) {
        if (e is Directory) {
          pending.add(e);
        } else if (e is File && _wanted.contains(p.extension(e.path).toLowerCase())) {
          if (seen.add(e.path)) out.add(e.path); // overlapping folders: count once
        }
      }
    }
    // Sorted so the batches, and the library's first view, follow folder order.
    out.sort();
    // Pair songs with their videos; a video beside a song isn't a song itself.
    return pairMusicVideos(out, songExtensions: audioExtensions);
  }

  /// Song files, plus video files that may belong to a song.
  static final _wanted = {...audioExtensions, ...videoExtensions};
}

/// Self-contained job sent to a background isolate.
class _BatchJob {
  final List<String> files;
  final Map<String, Map<String, dynamic>> previous;
  final String artDir;
  /// Each song's music video, by song file (only songs that have one).
  final Map<String, String> videos;
  _BatchJob(this.files, this.previous, this.artDir, [this.videos = const {}]);
  List<Map<String, dynamic>> run() => _scanBatch(files, previous, artDir, videos);
}

/// Reads one batch of files inside a background isolate. Works with JSON maps rather than
/// Tracks so the data passes cheaply between isolates.
List<Map<String, dynamic>> _scanBatch(
  List<String> files,
  Map<String, Map<String, dynamic>> previous,
  String artDir, [
  Map<String, String> videos = const {},
]) {
  final out = <Map<String, dynamic>>[];
  // Remembers each folder's file list, so looking for side files doesn't list the same
  // folder again for every file in it.
  final folders = FolderCache();
  for (final path in files) {
    try {
      final modified = File(path).statSync().modified.millisecondsSinceEpoch;
      final sidecars = findSidecars(path, folders);
      final stamp = sidecars.stamp == 0 ? null : sidecars.stamp;
      final prev = previous[path];
      // Unchanged file, and no extra files added, removed or changed beside it.
      if (prev != null && prev['modifiedMs'] == modified && prev['sidecarStamp'] == stamp) {
        out.add(_withVideo(prev, path, videos[path]));
        continue;
      }
      out.add(_withVideo(readTrack(path, modified, artDir, sidecars: sidecars).toJson(), path, videos[path]));
    } catch (_) {
      // File vanished mid-scan: ignore it.
    }
  }
  return out;
}

/// Sets a scanned song's music video (0.1.32): the video beside it, or for an .mp4 on its own,
/// the file itself when it has moving pictures. Worked out on every scan, so a video added or
/// removed beside an unchanged song is noticed.
Map<String, dynamic> _withVideo(Map<String, dynamic> json, String path, String? besideIt) {
  final own = besideIt == null && videoExtensions.contains(p.extension(path).toLowerCase()) && mp4HasVideo(path);
  final video = besideIt ?? (own ? path : null);
  if (json['video'] == video) return json;
  final out = Map<String, dynamic>.of(json);
  if (video == null) {
    out.remove('video');
  } else {
    out['video'] = video;
  }
  return out;
}

/// Reads one file's tags. Never throws on bad tags: falls back to the file
/// and folder names so every file still shows up.
Track readTrack(String path, int modifiedMs, String artDir, {Sidecars sidecars = Sidecars.none}) {
  String? title, artist, albumArtist, album, genre;
  int? trackNo, discNo, year;
  Duration duration = Duration.zero;
  List<int>? pictureBytes;
  var chapters = const <Chapter>[];

  try {
    // 1. Tags from the file itself.
    final m = readMetadata(File(path), getImage: true);
    title = _clean(m.title);
    artist = _clean(m.artist);
    albumArtist = _clean(m.albumArtist);
    album = _clean(m.album);
    trackNo = m.trackNumber;
    discNo = m.discNumber;
    final y = m.year?.year;
    year = (y != null && y > 0) ? y : null; // some files say "year 0"
    duration = m.duration ?? Duration.zero;
    if (m.genres.isNotEmpty) genre = _clean(m.genres.first);
    if (m.pictures.isNotEmpty) pictureBytes = m.pictures.first.bytes;
    // Audiobooks: chapter markers inside the file (M4B with Nero chapters).
    chapters = [for (final c in m.chapters) Chapter(c.start, c.title.trim())];
  } catch (_) {
    // Unsupported or damaged tags.
  }

  // 2. Fill gaps the tags left.
  // No length in the tags: WAV files can be measured from their header.
  if (duration == Duration.zero && p.extension(path).toLowerCase() == '.wav') {
    duration = wavDuration(File(path)) ?? Duration.zero;
  }

  // 3. Book side files.
  // Extra files beside it (audiobooks): a metadata file's details beat the
  // tags, which are often messy ("Author, Translator - translator").
  final info = sidecars.metadataFile == null ? null : BookInfo.parse(readSmallText(sidecars.metadataFile!, maxBytes: 4 << 20) ?? '');
  String? narrator, series, description;
  double? seriesIndex;
  if (info != null) {
    // A metadata file for this one file names it; a shared one (e.g. an Audiobookshelf
    // metadata.json for a whole folder) only names the book, not each part.
    if (sidecars.metadataIsOwn && info.title != null) title = info.title;
    album = info.title ?? album;
    artist = info.author ?? artist;
    albumArtist = info.author ?? albumArtist;
    year = info.year ?? year;
    if (genre == null && info.genres.isNotEmpty) genre = info.genres.first;
    narrator = info.narrator;
    series = info.series;
    seriesIndex = info.seriesIndex;
    description = info.description;
    // Chapters in the file itself line up exactly; otherwise use the metadata's.
    if (chapters.isEmpty && sidecars.metadataIsOwn) chapters = info.chaptersFor(duration);
  }
  if (description == null && sidecars.descriptionFile != null) {
    description = readSmallText(sidecars.descriptionFile!, maxBytes: 64 << 10);
  }

  // 4. Anything still missing comes from the file and folder names.
  final folder = p.dirname(path);
  final fallback = fallbackFromFileName(p.basenameWithoutExtension(path));
  title ??= fallback.title;
  trackNo ??= fallback.trackNumber;
  artist ??= 'Unknown Artist';
  albumArtist ??= artist;
  album ??= p.basename(folder);

  // A picture named after the file wins; otherwise the file's own art, then
  // a cover picture in the folder.
  final art = sidecars.imageIsOwn ? sidecars.image : (_saveArt(pictureBytes, folder, artDir) ?? sidecars.image);

  // 5. Build the finished Track.
  return Track(
    id: 'local:$path',
    source: TrackSource.local,
    title: title,
    artist: artist,
    album: album,
    albumArtist: albumArtist,
    trackNumber: trackNo,
    discNumber: discNo,
    year: year,
    genre: genre,
    duration: duration,
    path: path,
    art: art,
    modifiedMs: modifiedMs,
    chapters: chapters,
    narrator: narrator,
    series: series,
    seriesIndex: seriesIndex,
    description: description,
    companions: sidecars.companions,
    hasBookInfo: info != null,
    sidecarStamp: sidecars.stamp == 0 ? null : sidecars.stamp,
  );
}

/// Parses names like "03 - Song Name" or "03. Song Name".
({String title, int? trackNumber}) fallbackFromFileName(String name) {
  // 1-3 digits, an optional - . _ or ), then a space and the title.
  final match = RegExp(r'^\s*(\d{1,3})\s*[-._)]?\s+(.+)$').firstMatch(name);
  if (match != null) {
    return (title: match.group(2)!.trim(), trackNumber: int.tryParse(match.group(1)!));
  }
  return (title: name, trackNumber: null);
}

/// Trims a tag value, removing stray null characters some taggers leave; blank means none.
String? _clean(String? s) {
  if (s == null) return null;
  final t = s.replaceAll('\u0000', '').trim();
  return t.isEmpty ? null : t;
}

/// Caches embedded art, named by its content so identical covers (a whole
/// album) share one file and changed art gets a new file. Falls back to
/// cover.jpg etc. in the folder.
String? _saveArt(List<int>? bytes, String folder, String artDir) {
  if (bytes != null && bytes.isNotEmpty) {
    final name = md5.convert(bytes).toString();  // same picture = same name
    final file = File(p.join(artDir, '$name.img'));
    if (!file.existsSync()) {
      // Several workers may save the same album cover at once: write to a
      // private temp file, then move it into place.
      final tmp = File('${file.path}.${Isolate.current.hashCode}.${DateTime.now().microsecondsSinceEpoch}.tmp');
      try {
        tmp.writeAsBytesSync(bytes);
        tmp.renameSync(file.path);
      } catch (_) {
        try {
          if (tmp.existsSync()) tmp.deleteSync();
        } catch (_) {}
        if (!file.existsSync()) return null; // another worker saved it, or it really failed
      }
    }
    return file.path;
  }
  // No picture inside the file: look for a cover image in the folder.
  for (final n in _folderArtNames) {
    final f = File(p.join(folder, n));
    if (f.existsSync()) return f.path;
  }
  return null;
}

/// Length of a WAV file from its `fmt ` (bytes per second) and `data` chunks.
Duration? wavDuration(File file) {
  RandomAccessFile? raf;
  try {
    raf = file.openSync();
    final length = raf.lengthSync();
    // A WAV file is "RIFF" + size + "WAVE", then a list of chunks, each with a 4-letter id
    // and a size. We skip from chunk to chunk until we've seen both `fmt ` and `data`.
    final header = raf.readSync(12);
    if (header.length < 12 || String.fromCharCodes(header.sublist(0, 4)) != 'RIFF') return null;
    int? byteRate;
    int? dataSize;
    var pos = 12;
    while (pos + 8 <= length && (byteRate == null || dataSize == null)) {
      raf.setPositionSync(pos);
      final h = raf.readSync(8);
      final id = String.fromCharCodes(h.sublist(0, 4));
      final size = h[4] | (h[5] << 8) | (h[6] << 16) | (h[7] << 24);  // little-endian
      if (id == 'fmt ') {
        final fmt = raf.readSync(12);
        // Bytes 8-11 of the fmt chunk hold the average bytes per second.
        if (fmt.length >= 12) byteRate = fmt[8] | (fmt[9] << 8) | (fmt[10] << 16) | (fmt[11] << 24);
      } else if (id == 'data') {
        dataSize = size;
      }
      pos += 8 + size + (size.isOdd ? 1 : 0);  // chunks are padded to even sizes
    }
    if (byteRate == null || byteRate == 0 || dataSize == null) return null;
    // Length = amount of sound data / bytes played per second.
    return Duration(microseconds: (dataSize * 1000000 / byteRate).round());
  } catch (_) {
    return null;
  } finally {
    raf?.closeSync();
  }
}
