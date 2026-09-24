import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../models/track_edit.dart';

/// Which tag fields each file type can store.
class TagSupport {
  final bool title, artist, album, albumArtist, trackNumber, discNumber, year, genre, cover;
  const TagSupport({
    this.title = true,
    this.artist = true,
    this.album = true,
    this.albumArtist = true,
    this.trackNumber = true,
    this.discNumber = true,
    this.year = true,
    this.genre = true,
    this.cover = true,
  });

  static const none = TagSupport(
    title: false,
    artist: false,
    album: false,
    albumArtist: false,
    trackNumber: false,
    discNumber: false,
    year: false,
    genre: false,
    cover: false,
  );

  /// By file extension. OGG/Opus have no writer in the tag library.
  static TagSupport forPath(String path) => switch (p.extension(path).toLowerCase()) {
        '.mp3' || '.flac' => const TagSupport(),
        '.m4a' || '.mp4' || '.aac' => const TagSupport(albumArtist: false),
        '.wav' => const TagSupport(albumArtist: false, discNumber: false, cover: false),
        _ => none,
      };

  bool get anything => title || artist || album || albumArtist || trackNumber || discNumber || year || genre || cover;

  /// The part of [e] this file type can't store (it stays as a HomeTunes edit).
  TrackEdit leftover(TrackEdit e) => TrackEdit(
        title: title ? null : e.title,
        artist: artist ? null : e.artist,
        album: album ? null : e.album,
        albumArtist: albumArtist ? null : e.albumArtist,
        trackNumber: trackNumber ? null : e.trackNumber,
        discNumber: discNumber ? null : e.discNumber,
        year: year ? null : e.year,
        genre: genre ? null : e.genre,
        art: cover ? null : e.art,
      );
}

/// Outcome of writing one file.
class TagWriteResult {
  final String path;
  final bool ok;
  final String? error;

  /// Parts of the edit that couldn't be written (kept as a HomeTunes edit).
  final TrackEdit leftover;
  const TagWriteResult(this.path, {required this.ok, this.error, this.leftover = TrackEdit.empty});
}

/// Writes [edit] into the music file at [path], in a background isolate.
///
/// If [backupDir] is given, the original file is copied there first. After
/// writing, the file is re-read; if that fails the backup is put back.
Future<TagWriteResult> writeTagsToFile(String path, TrackEdit edit, {String? backupDir}) {
  final job = _WriteJob(path, edit.toJson(), backupDir);
  return Isolate.run(job.run);
}

class _WriteJob {
  final String path;
  final Map<String, dynamic> editJson;
  final String? backupDir;
  _WriteJob(this.path, this.editJson, this.backupDir);

  TagWriteResult run() {
    final edit = TrackEdit.fromJson(editJson);
    final support = TagSupport.forPath(path);
    final leftover = support.leftover(edit);
    if (!support.anything) {
      return TagWriteResult(path, ok: false, error: 'This file type can\'t be written', leftover: edit);
    }

    final file = File(path);
    File? backup;
    try {
      if (backupDir != null) {
        Directory(backupDir!).createSync(recursive: true);
        backup = file.copySync(p.join(backupDir!, _uniqueName(backupDir!, p.basename(path))));
      }

      Uint8List? coverBytes;
      String? coverMime;
      if (support.cover && edit.art != null) {
        coverBytes = File(edit.art!).readAsBytesSync();
        coverMime = imageMimeType(coverBytes);
        if (coverMime == null) throw const FormatException('The cover image isn\'t a JPEG or PNG');
      }

      updateMetadata(file, (m) => _apply(m, edit, support, coverBytes, coverMime));

      // Make sure the file still reads properly and the main changes stuck
      // (e.g. an MP3 with no ID3v2 tag can't take them).
      final after = readMetadata(file);
      String? check(String? wanted, String? got, String name) =>
          (wanted != null && got?.trim() != wanted.trim()) ? name : null;
      final missing = [
        if (support.title) check(edit.title, after.title, 'title'),
        if (support.artist) check(edit.artist, after.artist, 'artist'),
        if (support.album) check(edit.album, after.album, 'album'),
      ].whereType<String>().toList();
      if (missing.isNotEmpty) {
        throw StateError('The file didn\'t accept the new ${missing.join(', ')}');
      }
      return TagWriteResult(path, ok: true, leftover: leftover);
    } catch (e) {
      // Put the original back if we changed it and have a copy.
      if (backup != null) {
        try {
          backup.copySync(path);
        } catch (_) {}
      }
      return TagWriteResult(path, ok: false, error: '$e', leftover: edit);
    }
  }
}

String _uniqueName(String dir, String name) {
  var candidate = name;
  var i = 1;
  while (File(p.join(dir, candidate)).existsSync()) {
    candidate = '${p.basenameWithoutExtension(name)} ($i)${p.extension(name)}';
    i++;
  }
  return candidate;
}

/// JPEG or PNG, from the file's first bytes.
String? imageMimeType(List<int> bytes) {
  if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'image/jpeg';
  if (bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return 'image/png';
  }
  return null;
}

void _apply(Object m, TrackEdit e, TagSupport s, Uint8List? cover, String? coverMime) {
  final picture = (cover != null && coverMime != null) ? Picture(cover, coverMime, PictureType.coverFront) : null;
  switch (m) {
    case Mp3Metadata():
      if (e.title != null) m.songName = e.title;
      if (e.artist != null) m.leadPerformer = e.artist;
      if (e.album != null) m.album = e.album;
      if (e.albumArtist != null) m.bandOrOrchestra = e.albumArtist;
      if (e.trackNumber != null) m.trackNumber = e.trackNumber;
      if (e.discNumber != null) m.partOfSet = '${e.discNumber}';
      if (e.year != null) m.year = e.year;
      if (e.genre != null) m.genres = [e.genre!];
      if (picture != null) {
        m.pictures = [
          picture,
          ...m.pictures.where((x) => x.pictureType != PictureType.coverFront),
        ];
      }
    case Mp4Metadata():
      if (e.title != null) m.title = e.title;
      if (e.artist != null) m.artist = e.artist;
      if (e.album != null) m.album = e.album;
      if (e.trackNumber != null) m.trackNumber = e.trackNumber;
      if (e.discNumber != null) m.discNumber = e.discNumber;
      if (e.year != null) m.year = DateTime(e.year!);
      if (e.genre != null) m.genre = e.genre;
      if (picture != null) m.picture = picture;
    case VorbisMetadata():
      if (e.title != null) m.title = [e.title!];
      if (e.artist != null) m.artist = [e.artist!];
      if (e.album != null) m.album = [e.album!];
      if (e.albumArtist != null) m.albumArtist = [e.albumArtist!];
      if (e.trackNumber != null) m.trackNumber = [e.trackNumber!];
      if (e.discNumber != null) m.discNumber = e.discNumber;
      if (e.year != null) m.date = [DateTime(e.year!)];
      if (e.genre != null) m.genres = [e.genre!];
      if (picture != null) {
        m.pictures = [
          picture,
          ...m.pictures.where((x) => x.pictureType != PictureType.coverFront),
        ];
      }
    case RiffMetadata():
      if (e.title != null) m.title = e.title;
      if (e.artist != null) m.artist = e.artist;
      if (e.album != null) m.album = e.album;
      if (e.trackNumber != null) m.trackNumber = e.trackNumber;
      if (e.year != null) m.year = DateTime(e.year!);
      if (e.genre != null) m.genre = e.genre;
    default:
      throw UnsupportedError('This file type can\'t be written');
  }
}
