import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/track.dart';

/// Extensions the scanner picks up.
const audioExtensions = {'.mp3', '.flac', '.m4a', '.mp4', '.aac', '.ogg', '.opus', '.wav'};

/// Image files commonly dropped next to albums.
const _folderArtNames = ['cover.jpg', 'cover.png', 'folder.jpg', 'folder.png', 'front.jpg', 'front.png', 'album.jpg'];

/// Walks music folders and turns audio files into [Track]s.
class LocalScanner {
  final String artDir;

  LocalScanner(this.artDir);

  /// Lists every audio file under [folders].
  Future<List<String>> findAudioFiles(List<String> folders) =>
      Isolate.run(_ListJob(List.of(folders)).run);

  /// Scans [folders]. Tracks in [previous] whose file hasn't changed are reused
  /// without re-reading tags. [onProgress] gets (done, total).
  Future<List<Track>> scan(
    List<String> folders, {
    Map<String, Track> previous = const {},
    void Function(int done, int total)? onProgress,
  }) async {
    final files = await findAudioFiles(folders);
    final result = <Track>[];
    const batchSize = 40;
    final artDir = this.artDir;

    for (var i = 0; i < files.length; i += batchSize) {
      final batch = files.sublist(i, (i + batchSize).clamp(0, files.length));
      // Only the tracks that need (re)reading go to the isolate.
      final prevJson = <String, Map<String, dynamic>>{
        for (final f in batch)
          if (previous['local:$f'] != null) f: previous['local:$f']!.toJson(),
      };
      final jsonList = await Isolate.run(_BatchJob(batch, prevJson, artDir).run);
      result.addAll(jsonList.map(Track.fromJson));
      onProgress?.call(result.length, files.length);
    }
    return result;
  }

  /// Deletes cached cover images that no track uses any more
  /// (album removed, or its embedded art changed).
  Future<void> removeUnusedArt(List<Track> tracks) async {
    final used = {for (final t in tracks) if (t.art != null) p.normalize(t.art!)};
    final dir = Directory(artDir);
    if (!await dir.exists()) return;
    await for (final e in dir.list()) {
      if (e is File && p.extension(e.path) == '.img' && !used.contains(p.normalize(e.path))) {
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

  List<String> run() {
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
        } else if (e is File && audioExtensions.contains(p.extension(e.path).toLowerCase())) {
          if (seen.add(e.path)) out.add(e.path); // overlapping folders: count once
        }
      }
    }
    out.sort();
    return out;
  }
}

/// Self-contained job sent to a background isolate.
class _BatchJob {
  final List<String> files;
  final Map<String, Map<String, dynamic>> previous;
  final String artDir;
  _BatchJob(this.files, this.previous, this.artDir);
  List<Map<String, dynamic>> run() => _scanBatch(files, previous, artDir);
}

List<Map<String, dynamic>> _scanBatch(
  List<String> files,
  Map<String, Map<String, dynamic>> previous,
  String artDir,
) {
  final out = <Map<String, dynamic>>[];
  for (final path in files) {
    try {
      final modified = File(path).statSync().modified.millisecondsSinceEpoch;
      final prev = previous[path];
      if (prev != null && prev['modifiedMs'] == modified) {
        out.add(prev);
        continue;
      }
      out.add(readTrack(path, modified, artDir).toJson());
    } catch (_) {
      // File vanished mid-scan: ignore it.
    }
  }
  return out;
}

/// Reads one file's tags. Never throws on bad tags: falls back to the file
/// and folder names so every file still shows up.
Track readTrack(String path, int modifiedMs, String artDir) {
  String? title, artist, albumArtist, album, genre;
  int? trackNo, discNo, year;
  Duration duration = Duration.zero;
  List<int>? pictureBytes;

  try {
    final m = readMetadata(File(path), getImage: true);
    title = _clean(m.title);
    artist = _clean(m.artist);
    albumArtist = _clean(m.albumArtist);
    album = _clean(m.album);
    trackNo = m.trackNumber;
    discNo = m.discNumber;
    year = m.year?.year;
    duration = m.duration ?? Duration.zero;
    if (m.genres.isNotEmpty) genre = _clean(m.genres.first);
    if (m.pictures.isNotEmpty) pictureBytes = m.pictures.first.bytes;
  } catch (_) {
    // Unsupported or damaged tags.
  }

  // No length in the tags: WAV files can be measured from their header.
  if (duration == Duration.zero && p.extension(path).toLowerCase() == '.wav') {
    duration = wavDuration(File(path)) ?? Duration.zero;
  }

  final folder = p.dirname(path);
  final fallback = fallbackFromFileName(p.basenameWithoutExtension(path));
  title ??= fallback.title;
  trackNo ??= fallback.trackNumber;
  artist ??= 'Unknown Artist';
  albumArtist ??= artist;
  album ??= p.basename(folder);

  final art = _saveArt(pictureBytes, folder, artDir);

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
  );
}

/// Parses names like "03 - Song Name" or "03. Song Name".
({String title, int? trackNumber}) fallbackFromFileName(String name) {
  final match = RegExp(r'^\s*(\d{1,3})\s*[-._)]?\s+(.+)$').firstMatch(name);
  if (match != null) {
    return (title: match.group(2)!.trim(), trackNumber: int.tryParse(match.group(1)!));
  }
  return (title: name, trackNumber: null);
}

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
    final name = md5.convert(bytes).toString();
    final file = File(p.join(artDir, '$name.img'));
    if (!file.existsSync()) {
      try {
        file.writeAsBytesSync(bytes);
      } catch (_) {
        return null;
      }
    }
    return file.path;
  }
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
    final header = raf.readSync(12);
    if (header.length < 12 || String.fromCharCodes(header.sublist(0, 4)) != 'RIFF') return null;
    int? byteRate;
    int? dataSize;
    var pos = 12;
    while (pos + 8 <= length && (byteRate == null || dataSize == null)) {
      raf.setPositionSync(pos);
      final h = raf.readSync(8);
      final id = String.fromCharCodes(h.sublist(0, 4));
      final size = h[4] | (h[5] << 8) | (h[6] << 16) | (h[7] << 24);
      if (id == 'fmt ') {
        final fmt = raf.readSync(12);
        if (fmt.length >= 12) byteRate = fmt[8] | (fmt[9] << 8) | (fmt[10] << 16) | (fmt[11] << 24);
      } else if (id == 'data') {
        dataSize = size;
      }
      pos += 8 + size + (size.isOdd ? 1 : 0);
    }
    if (byteRate == null || byteRate == 0 || dataSize == null) return null;
    return Duration(microseconds: (dataSize * 1000000 / byteRate).round());
  } catch (_) {
    return null;
  } finally {
    raf?.closeSync();
  }
}
