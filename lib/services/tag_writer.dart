// Writes the user's edits into the music files themselves ("Save edits into music files").
// LibraryModel.writeEditsToFiles calls writeTagsToFile once per edited song. Each write runs in
// a background isolate, can first copy the original into a backup folder, and writes into a
// working copy that is re-read and checked before it replaces the original (so a failed write
// never harms the original). Tags HomeTunes doesn't manage are kept, thanks to the
// patched tag library in packages/audio_metadata_reader. Anything a format can't hold (see
// TagSupport) comes back as a "leftover" and simply stays as a HomeTunes edit.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../models/track_edit.dart';

/// Which tag fields each file type can store.
class TagSupport {
  final bool title, artist, album, albumArtist, trackNumber, discNumber, year, genre, cover, lyrics;
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
    this.lyrics = true,
  });

  /// A file type we can't write at all.
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
    lyrics: false,
  );

  /// By file extension. OGG/Opus have no writer in the tag library.
  static TagSupport forPath(String path) => switch (p.extension(path).toLowerCase()) {
        '.mp3' || '.flac' => const TagSupport(),
        '.m4a' || '.mp4' || '.aac' => const TagSupport(albumArtist: false),
        '.wav' => const TagSupport(albumArtist: false, discNumber: false, cover: false, lyrics: false),
        _ => none,
      };

  /// True if at least one field can be written.
  bool get anything =>
      title || artist || album || albumArtist || trackNumber || discNumber || year || genre || cover || lyrics;

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
        // Audiobook details have no standard tag: they always stay in HomeTunes.
        narrator: e.narrator,
        series: e.series,
        seriesIndex: e.seriesIndex,
        lyrics: lyrics ? null : e.lyrics,
      );
}

/// Outcome of writing one file.
class TagWriteResult {
  final String path;
  /// True when the file was written and checked. On failure [error] says why.
  final bool ok;
  final String? error;

  /// Parts of the edit that couldn't be written (kept as a HomeTunes edit).
  final TrackEdit leftover;
  const TagWriteResult(this.path, {required this.ok, this.error, this.leftover = TrackEdit.empty});
}

/// Writes [edit] into the music file at [path], in a background isolate.
///
/// If [backupDir] is given, the original file is also copied there first. The tags are
/// written into a working copy beside the file, which is re-read and checked and only then
/// replaces the original, so a failed write never changes the original.
Future<TagWriteResult> writeTagsToFile(String path, TrackEdit edit, {String? backupDir}) {
  final job = _WriteJob(path, edit.toJson(), backupDir);
  return Isolate.run(job.run);
}

/// Everything the isolate needs, as simple values (the edit travels as JSON).
class _WriteJob {
  final String path;
  final Map<String, dynamic> editJson;
  final String? backupDir;
  _WriteJob(this.path, this.editJson, this.backupDir);

  TagWriteResult run() {
    // 1. Work out what this file type can take.
    final edit = TrackEdit.fromJson(editJson);
    final support = TagSupport.forPath(path);
    final leftover = support.leftover(edit);  // what stays as a HomeTunes edit
    if (!support.anything) {
      return TagWriteResult(path, ok: false, error: 'This file type can\'t be written', leftover: edit);
    }

    final file = File(path);
    // HomeTunes: the tags are written into a copy beside the original, which only replaces the
    // original once it has been checked. Before 0.1.14 the original was changed in place, so a
    // write that failed partway (with "make a backup" off) could leave a damaged music file.
    final work = File(workingCopyPath(path));
    try {
      // 2. Safety copy first, under a name that doesn't overwrite an older backup. (Optional:
      //    the original is never touched until the new version is known to be good.)
      if (backupDir != null) {
        Directory(backupDir!).createSync(recursive: true);
        file.copySync(p.join(backupDir!, _uniqueName(backupDir!, p.basename(path))));
      }

      // 3. Load the new cover and check it's a picture the tag formats accept.
      Uint8List? coverBytes;
      String? coverMime;
      if (support.cover && edit.art != null) {
        coverBytes = File(edit.art!).readAsBytesSync();
        coverMime = imageMimeType(coverBytes);
        if (coverMime == null) throw const FormatException('The cover image isn\'t a JPEG or PNG');
      }

      // 4. Write the tags into a working copy. (The tag library recognises formats by their
      //    contents, not the file name, so the copy's odd extension doesn't matter, and the
      //    scanner ignores it because it isn't an audio extension.)
      file.copySync(work.path);
      if (p.extension(path).toLowerCase() == '.wav') ensureRiffInfoChunk(work);
      updateMetadata(work, (m) => _apply(m, edit, support, coverBytes, coverMime));

      // Make sure the copy still reads properly and the main changes stuck
      // (e.g. an MP3 with no ID3v2 tag can't take them).
      final after = readMetadata(work);
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
      // 5. All good: swap the checked copy in for the original in one step. If this fails
      //    (e.g. another program has the file open), the original is still as it was.
      work.renameSync(path);
      return TagWriteResult(path, ok: true, leftover: leftover);
    } catch (e) {
      // The original was never changed; just throw the working copy away.
      try {
        if (work.existsSync()) work.deleteSync();
      } catch (_) {}
      return TagWriteResult(path, ok: false, error: '$e', leftover: edit);
    }
  }
}

/// Where the tags are written before the result replaces the original: beside it, so the
/// final rename stays on the same drive and happens in one step.
String workingCopyPath(String path) => '$path.$workingCopyExtension';

/// Ending of the working copies (not an audio extension, so scans never pick them up).
const workingCopyExtension = 'hometunes-tmp';

/// "song.mp3", or "song (1).mp3", "song (2).mp3"... if that name is already taken.
String _uniqueName(String dir, String name) {
  var candidate = name;
  var i = 1;
  while (File(p.join(dir, candidate)).existsSync()) {
    candidate = '${p.basenameWithoutExtension(name)} ($i)${p.extension(name)}';
    i++;
  }
  return candidate;
}

/// The tag library only rewrites an existing `LIST/INFO` block in WAV files,
/// and many WAVs have none. This appends an empty one (and fixes the RIFF
/// size) so there's somewhere for the tags to go. Does nothing if present.
void ensureRiffInfoChunk(File file) {
  final data = file.readAsBytesSync();
  if (data.length < 12 ||
      String.fromCharCodes(data.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(data.sublist(8, 12)) != 'WAVE') {
    return;
  }
  final view = ByteData.sublistView(data);
  // Look for an existing LIST/INFO chunk.
  var pos = 12;
  while (pos + 8 <= data.length) {
    final id = String.fromCharCodes(data.sublist(pos, pos + 4));
    final size = view.getUint32(pos + 4, Endian.little);
    if (id == 'LIST' && pos + 12 <= data.length && String.fromCharCodes(data.sublist(pos + 8, pos + 12)) == 'INFO') {
      return;
    }
    pos += 8 + size + (size.isOdd ? 1 : 0);
  }
  // Append an empty LIST/INFO chunk (keeping chunks on even offsets) and fix the RIFF size.
  final out = BytesBuilder(copy: false)..add(data);
  if (data.length.isOdd) out.addByte(0);
  out
    ..add('LIST'.codeUnits)
    ..add((ByteData(4)..setUint32(0, 4, Endian.little)).buffer.asUint8List())
    ..add('INFO'.codeUnits);
  final bytes = out.toBytes();
  // Bytes 4-7 of a WAV file hold the size of everything after them.
  ByteData.sublistView(bytes).setUint32(4, bytes.length - 8, Endian.little);
  file.writeAsBytesSync(bytes, flush: true);
}

/// JPEG or PNG, from the file's first bytes.
String? imageMimeType(List<int> bytes) {
  // Checks the "magic" bytes every JPEG / PNG file starts with, rather than trusting the name.
  if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'image/jpeg';
  if (bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return 'image/png';
  }
  return null;
}

/// Copies the edited fields into the tag object for the file's format. Fields left null
/// in the edit aren't touched. Each format names things differently (e.g. ID3's
/// "band/orchestra" frame, TPE2, is what players use for album artist).
void _apply(Object m, TrackEdit e, TagSupport s, Uint8List? cover, String? coverMime) {
  final picture = (cover != null && coverMime != null) ? Picture(cover, coverMime, PictureType.coverFront) : null;
  switch (m) {
    case Mp3Metadata():
      if (e.title != null) m.songName = e.title;
      if (e.artist != null) m.leadPerformer = e.artist;
      if (e.album != null) m.album = e.album;
      if (e.albumArtist != null) m.bandOrOrchestra = e.albumArtist;  // ID3 TPE2 frame
      if (e.trackNumber != null) m.trackNumber = e.trackNumber;
      if (e.discNumber != null) m.partOfSet = '${e.discNumber}';  // ID3 stores it as text
      if (e.year != null) m.year = e.year;
      if (e.genre != null) m.genres = [e.genre!];
      // The new cover replaces the old front cover; other pictures (back, booklet) stay.
      if (picture != null) {
        m.pictures = [
          picture,
          ...m.pictures.where((x) => x.pictureType != PictureType.coverFront),
        ];
      }
      if (e.lyrics != null) m.lyric = e.lyrics;
    case Mp4Metadata():  // M4A / M4B / MP4
      if (e.title != null) m.title = e.title;
      if (e.artist != null) m.artist = e.artist;
      if (e.album != null) m.album = e.album;
      if (e.trackNumber != null) m.trackNumber = e.trackNumber;
      if (e.discNumber != null) m.discNumber = e.discNumber;
      if (e.year != null) m.year = DateTime(e.year!);
      if (e.genre != null) m.genre = e.genre;
      if (picture != null) m.picture = picture;
      if (e.lyrics != null) m.lyrics = e.lyrics;
    case VorbisMetadata():  // FLAC
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
      if (e.lyrics != null) m.lyric = e.lyrics;
    case RiffMetadata():  // WAV (LIST/INFO chunk)
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
