// "Where does this come from?": reads one song or audiobook file again and works out, for
// each detail HomeTunes shows, where it came from: the file's own tags, a book details file
// beside it (Libation / Audiobookshelf), a text or picture file beside it, the folder or file
// name, the music server, or the user's own edit. Also lists what the file itself contains.
//
// Used by the Details page (ui/screens/details_screen.dart). Nothing here changes any file.
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../models/track.dart';
import 'book_sidecar.dart';
import 'local_scanner.dart' show fallbackFromFileName;

/// Where one detail came from.
enum DetailSource {
  tags('The file\'s tags'),
  bookFile('Book details file'),
  textFile('Text file beside it'),
  picture('Picture beside it'),
  embedded('Built into the file'),
  folderName('Folder name'),
  fileName('File name'),
  measured('Measured when played'),
  edit('Your edit'),
  server('Music server'),
  standIn('Stand-in (nothing found)'),
  notSet('Not set'),
  unknown('Couldn\'t tell');

  final String label;
  const DetailSource(this.label);
}

/// One row of the Details page: what HomeTunes shows, where it came from, and
/// what the file itself says when that's different (e.g. after an edit).
class DetailRow {
  final String label;
  final String shown;
  final DetailSource source;
  /// Which file it came from, when that's a file beside the song (a name, not a path).
  final String? from;
  /// The file's own value when it differs from what's shown.
  final String? inFile;
  const DetailRow(this.label, this.shown, this.source, {this.from, this.inFile});
}

/// Everything the Details page shows about one file.
class FileDetails {
  final Track track;
  final bool isServer;
  final bool exists;
  final String? folder;
  final String? fileName;
  final String? format;
  final int? sizeBytes;
  final DateTime? modified;
  /// What the file's tags contain, in plain words ("Title" → "…"), in a fixed order.
  final List<(String, String)> inFile;
  /// Other files beside it that HomeTunes uses (name, what it's used for).
  final List<(String, String)> besideIt;
  final List<DetailRow> rows;
  /// Set when the file couldn't be read.
  final String? problem;

  const FileDetails({
    required this.track,
    required this.isServer,
    required this.exists,
    this.folder,
    this.fileName,
    this.format,
    this.sizeBytes,
    this.modified,
    this.inFile = const [],
    this.besideIt = const [],
    this.rows = const [],
    this.problem,
  });
}

/// Reads [scanned] (the song as the scan saw it) and [shown] (with the user's
/// edits) and explains every detail. Runs in the background.
Future<FileDetails> inspectTrack({required Track shown, required Track scanned, required String artDir}) =>
    Isolate.run(() => inspectTrackNow(shown: shown, scanned: scanned, artDir: artDir));

FileDetails inspectTrackNow({required Track shown, required Track scanned, required String artDir}) {
  final path = scanned.path;
  if (path == null) return _serverDetails(shown, scanned);

  final file = File(path);
  final exists = file.existsSync();
  final folder = p.dirname(path);
  FileStat? stat;
  AudioMetadata? m;
  String? problem;
  if (exists) {
    stat = file.statSync();
    try {
      m = readMetadata(file, getImage: true);
    } catch (e) {
      problem = 'The file\'s tags couldn\'t be read ($e).';
    }
  } else {
    problem = 'The file isn\'t there any more. These details are from the last time it was found.';
  }

  final sidecars = exists ? findSidecars(path, FolderCache()) : Sidecars.none;
  final info = sidecars.metadataFile == null
      ? null
      : BookInfo.parse(readSmallText(sidecars.metadataFile!, maxBytes: 4 << 20) ?? '');
  final infoName = sidecars.metadataFile == null ? null : p.basename(sidecars.metadataFile!);

  String? clean(String? s) {
    final t = s?.replaceAll('\u0000', '').trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  final tagTitle = clean(m?.title), tagArtist = clean(m?.artist), tagAlbumArtist = clean(m?.albumArtist);
  final tagAlbum = clean(m?.album);
  final tagGenre = (m == null || m.genres.isEmpty) ? null : clean(m.genres.first);
  final y = m?.year?.year;
  final tagYear = (y != null && y > 0) ? y : null;
  final fallback = fallbackFromFileName(p.basenameWithoutExtension(path));

  // Works out a text detail's source by checking, in the scanner's own order, which
  // place gives the value the scan saved.
  DetailRow text(String label, String? scannedValue, String? shownValue,
      {String? tag, String? fromInfo, String? folderValue, String? fileValue, String? standIn}) {
    final s = scannedValue ?? '';
    final v = shownValue ?? '';
    if (v != s) return DetailRow(label, v.isEmpty ? '–' : v, DetailSource.edit, inFile: s.isEmpty ? '–' : s);
    if (v.isEmpty) return DetailRow(label, '–', DetailSource.notSet);
    if (fromInfo != null && fromInfo == s) return DetailRow(label, v, DetailSource.bookFile, from: infoName);
    if (tag != null && tag == s) return DetailRow(label, v, DetailSource.tags);
    if (folderValue != null && folderValue == s) return DetailRow(label, v, DetailSource.folderName);
    if (fileValue != null && fileValue == s) return DetailRow(label, v, DetailSource.fileName);
    if (standIn != null && standIn == s) return DetailRow(label, v, DetailSource.standIn);
    return DetailRow(label, v, DetailSource.unknown);
  }

  String? str(Object? o) => o?.toString();
  final rows = <DetailRow>[
    text('Title', scanned.title, shown.title,
        tag: tagTitle, fromInfo: sidecars.metadataIsOwn ? info?.title : null, fileValue: fallback.title),
    text('Artist', scanned.artist, shown.artist, tag: tagArtist, fromInfo: info?.author, standIn: 'Unknown Artist'),
    text('Album', scanned.album, shown.album, tag: tagAlbum, fromInfo: info?.title, folderValue: p.basename(folder)),
    // With no album artist in the tags, the scan uses the artist.
    text('Album artist', scanned.albumArtist, shown.albumArtist,
        tag: tagAlbumArtist ?? tagArtist, fromInfo: info?.author, standIn: 'Unknown Artist'),
    text('Track number', str(scanned.trackNumber), str(shown.trackNumber),
        tag: str(m?.trackNumber), fileValue: str(fallback.trackNumber)),
    text('Disc number', str(scanned.discNumber), str(shown.discNumber), tag: str(m?.discNumber)),
    text('Year', str(scanned.year), str(shown.year), tag: str(tagYear), fromInfo: str(info?.year)),
    text('Genre', scanned.genre, shown.genre,
        tag: tagGenre, fromInfo: info == null || info.genres.isEmpty ? null : info.genres.first),
  ];
  // Audiobook details only ever come from a book details file (or an edit).
  if (scanned.narrator != null || shown.narrator != null || info != null) {
    rows.addAll([
      text('Narrator', scanned.narrator, shown.narrator, fromInfo: info?.narrator),
      text('Series', scanned.series, shown.series, fromInfo: info?.series),
      text('Number in series', _num(scanned.seriesIndex), _num(shown.seriesIndex), fromInfo: _num(info?.seriesIndex)),
    ]);
  }

  // Length: the tags, the WAV header, or learned the first time it played.
  final tagLength = m?.duration;
  final lengthSource = (tagLength != null && tagLength == scanned.duration)
      ? DetailSource.tags
      : (p.extension(path).toLowerCase() == '.wav' ? DetailSource.embedded : DetailSource.measured);
  rows.add(DetailRow('Length', _length(shown.duration), scanned.duration == Duration.zero ? DetailSource.notSet : lengthSource));

  // Chapters: inside the file, or from the book details file.
  final fileChapters = m?.chapters.length ?? 0;
  if (scanned.chapters.isNotEmpty || fileChapters > 0) {
    rows.add(DetailRow(
      'Chapters',
      '${scanned.chapters.length}',
      fileChapters > 0 ? DetailSource.tags : (info != null ? DetailSource.bookFile : DetailSource.unknown),
      from: fileChapters > 0 ? null : infoName,
    ));
  }

  // Description: the book details file, then a text file beside it.
  if (shown.description != null) {
    final fromText = sidecars.descriptionFile;
    rows.add(DetailRow(
      'Description',
      shown.description!.length > 80 ? '${shown.description!.substring(0, 80)}…' : shown.description!,
      info?.description != null
          ? DetailSource.bookFile
          : fromText != null
              ? DetailSource.textFile
              : DetailSource.unknown,
      from: info?.description != null ? infoName : (fromText == null ? null : p.basename(fromText)),
    ));
  }

  // Cover.
  rows.add(_cover(shown, scanned, sidecars, artDir, hasEmbedded: (m?.pictures.isNotEmpty ?? false)));

  // What's inside the file.
  final inFile = <(String, String)>[
    if (m != null) ...[
      ('Title', tagTitle ?? '–'),
      ('Artist', tagArtist ?? '–'),
      ('Album', tagAlbum ?? '–'),
      ('Album artist', tagAlbumArtist ?? '–'),
      ('Track', m.trackNumber == null ? '–' : '${m.trackNumber}${m.trackTotal != null ? ' of ${m.trackTotal}' : ''}'),
      ('Disc', m.discNumber == null ? '–' : '${m.discNumber}${m.totalDisc != null ? ' of ${m.totalDisc}' : ''}'),
      ('Year', tagYear?.toString() ?? '–'),
      ('Genre', m.genres.isEmpty ? '–' : m.genres.join(', ')),
      ('Length', m.duration == null ? '–' : _length(m.duration!)),
      ('Cover pictures', m.pictures.isEmpty ? 'None' : '${m.pictures.length}'),
      ('Chapters', m.chapters.isEmpty ? 'None' : '${m.chapters.length}'),
      ('Lyrics', clean(m.lyrics) == null ? 'None' : 'Yes'),
      if (m.sampleRate != null && m.sampleRate! > 0) ('Sample rate', '${(m.sampleRate! / 1000).toStringAsFixed(1)} kHz'),
      if (m.bitrate != null && m.bitrate! > 0) ('Bit rate', '${(m.bitrate! / 1000).round()} kbps'),
    ],
  ];

  final beside = <(String, String)>[
    if (sidecars.metadataFile != null) (p.basename(sidecars.metadataFile!), 'Book details'),
    if (sidecars.image != null) (p.basename(sidecars.image!), 'Cover picture'),
    if (sidecars.descriptionFile != null) (_relative(sidecars.descriptionFile!, folder), 'Description'),
    for (final c in sidecars.companions) (p.basename(c), 'Book PDF / EPUB'),
  ];

  return FileDetails(
    track: shown,
    isServer: false,
    exists: exists,
    folder: folder,
    fileName: p.basename(path),
    format: p.extension(path).replaceFirst('.', '').toUpperCase(),
    sizeBytes: stat?.size,
    modified: stat?.modified,
    inFile: inFile,
    besideIt: beside,
    rows: rows,
    problem: problem,
  );
}

DetailRow _cover(Track shown, Track scanned, Sidecars sidecars, String artDir, {required bool hasEmbedded}) {
  if (shown.art != scanned.art) {
    return DetailRow('Cover', shown.art == null ? 'None' : 'Picture you chose', DetailSource.edit,
        inFile: scanned.art == null ? 'None' : 'The file\'s own cover');
  }
  final art = scanned.art;
  if (art == null) return const DetailRow('Cover', 'None', DetailSource.notSet);
  if (sidecars.image != null && p.equals(art, sidecars.image!)) {
    return DetailRow('Cover', 'Picture', DetailSource.picture, from: p.basename(art));
  }
  if (p.isWithin(artDir, art) && hasEmbedded) return const DetailRow('Cover', 'Picture', DetailSource.embedded);
  if (!p.isWithin(artDir, art)) return DetailRow('Cover', 'Picture', DetailSource.picture, from: p.basename(art));
  return const DetailRow('Cover', 'Picture', DetailSource.unknown);
}

FileDetails _serverDetails(Track shown, Track scanned) {
  DetailRow row(String label, Object? s, Object? v) {
    final sv = s?.toString() ?? '', vv = v?.toString() ?? '';
    if (sv != vv) return DetailRow(label, vv.isEmpty ? '–' : vv, DetailSource.edit, inFile: sv.isEmpty ? '–' : sv);
    return DetailRow(label, vv.isEmpty ? '–' : vv, vv.isEmpty ? DetailSource.notSet : DetailSource.server);
  }

  return FileDetails(
    track: shown,
    isServer: true,
    exists: true,
    rows: [
      row('Title', scanned.title, shown.title),
      row('Artist', scanned.artist, shown.artist),
      row('Album', scanned.album, shown.album),
      row('Album artist', scanned.albumArtist, shown.albumArtist),
      row('Track number', scanned.trackNumber, shown.trackNumber),
      row('Disc number', scanned.discNumber, shown.discNumber),
      row('Year', scanned.year, shown.year),
      row('Genre', scanned.genre, shown.genre),
      DetailRow('Length', _length(shown.duration), DetailSource.server),
      shown.art != scanned.art
          ? const DetailRow('Cover', 'Picture you chose', DetailSource.edit)
          : DetailRow('Cover', shown.art == null ? 'None' : 'Picture', shown.art == null ? DetailSource.notSet : DetailSource.server),
    ],
  );
}

String? _num(double? d) => d == null ? null : (d == d.roundToDouble() ? '${d.round()}' : '$d');

String _length(Duration d) {
  final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

String _relative(String path, String folder) =>
    p.dirname(path) == folder ? p.basename(path) : '${p.basename(p.dirname(path))}${p.separator}${p.basename(path)}';

/// "12.3 MB" style.
String fileSize(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
