// Videos (0.1.32): the Videos tab's data shapes.
//
// VideoItem is one video file found in the video folders (Settings › Folders & scanning), made
// by services/video_scanner.dart and saved in videos.json. VideoEdit is the user's changes to
// its details (title, collection, year, genre, description), kept apart from the file and laid
// over it, like TrackEdit for songs. VideoPlace is where the user got to in it, so it can carry
// on from there, and whether it's been watched. VideoLibraryModel owns all three.
import 'package:path/path.dart' as p;

/// One video file.
class VideoItem {
  /// `video:<absolute path>`.
  final String id;
  final String path;
  final String title;

  /// What the video is grouped under on the Videos tab. Starts as its folder's name
  /// ("Season 1", "Holiday 2024"); can be edited.
  final String collection;
  final int? year;
  final String? genre;
  final String? description;

  /// Zero until known (from the file's tags, or once a thumbnail has been made or it's played).
  final Duration duration;
  final int? width;
  final int? height;
  final int? modifiedMs;
  final int? sizeBytes;

  /// A small picture from the video (art/video/…jpg), made in the background after a scan.
  final String? thumb;

  /// When HomeTunes first found the file (for "Recently added").
  final int? addedMs;

  const VideoItem({
    required this.id,
    required this.path,
    required this.title,
    required this.collection,
    this.year,
    this.genre,
    this.description,
    this.duration = Duration.zero,
    this.width,
    this.height,
    this.modifiedMs,
    this.sizeBytes,
    this.thumb,
    this.addedMs,
  });

  static String idFor(String path) => 'video:$path';

  /// "MKV", "MP4"…
  String get format => p.extension(path).replaceFirst('.', '').toUpperCase();

  /// "1920×1080", or null when not known yet.
  String? get resolution => (width != null && height != null && width! > 0) ? '$width×$height' : null;

  /// A copy with things learned after the scan: its thumbnail, length and picture size.
  VideoItem copyWith({String? thumb, Duration? duration, int? width, int? height}) => VideoItem(
        id: id,
        path: path,
        title: title,
        collection: collection,
        year: year,
        genre: genre,
        description: description,
        duration: duration ?? this.duration,
        width: width ?? this.width,
        height: height ?? this.height,
        modifiedMs: modifiedMs,
        sizeBytes: sizeBytes,
        thumb: thumb ?? this.thumb,
        addedMs: addedMs,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'title': title,
        'collection': collection,
        if (year != null) 'year': year,
        if (genre != null) 'genre': genre,
        if (description != null) 'description': description,
        'durationMs': duration.inMilliseconds,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (modifiedMs != null) 'modifiedMs': modifiedMs,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (thumb != null) 'thumb': thumb,
        if (addedMs != null) 'addedMs': addedMs,
      };

  /// Reads one back from videos.json. Throws on a wrong shape (the model skips that entry).
  factory VideoItem.fromJson(Map<String, dynamic> j) {
    final path = j['path'] as String;
    return VideoItem(
      id: (j['id'] as String?) ?? idFor(path),
      path: path,
      title: (j['title'] as String?) ?? p.basenameWithoutExtension(path),
      collection: (j['collection'] as String?) ?? p.basename(p.dirname(path)),
      year: j['year'] as int?,
      genre: j['genre'] as String?,
      description: j['description'] as String?,
      duration: Duration(milliseconds: (j['durationMs'] as int?) ?? 0),
      width: j['width'] as int?,
      height: j['height'] as int?,
      modifiedMs: j['modifiedMs'] as int?,
      sizeBytes: j['sizeBytes'] as int?,
      thumb: j['thumb'] as String?,
      addedMs: j['addedMs'] as int?,
    );
  }

  @override
  bool operator ==(Object other) => other is VideoItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The user's changes to a video's details. Null means "use what the file says".
class VideoEdit {
  final String? title;
  final String? collection;
  final int? year;
  final String? genre;
  final String? description;

  /// Details the user emptied on purpose ('year', 'genre', 'description').
  final Set<String> cleared;

  const VideoEdit({this.title, this.collection, this.year, this.genre, this.description, this.cleared = const {}});

  bool get isEmpty =>
      title == null && collection == null && year == null && genre == null && description == null && cleared.isEmpty;

  /// The video as the user wants to see it.
  VideoItem applyTo(VideoItem v) => VideoItem(
        id: v.id,
        path: v.path,
        title: title ?? v.title,
        collection: collection ?? v.collection,
        year: cleared.contains('year') ? null : (year ?? v.year),
        genre: cleared.contains('genre') ? null : (genre ?? v.genre),
        description: cleared.contains('description') ? null : (description ?? v.description),
        duration: v.duration,
        width: v.width,
        height: v.height,
        modifiedMs: v.modifiedMs,
        sizeBytes: v.sizeBytes,
        thumb: v.thumb,
        addedMs: v.addedMs,
      );

  /// The edit that turns [original] into the details typed in the editor: only what differs from
  /// the file is kept, and an emptied year, genre or description is remembered as cleared.
  static VideoEdit fromForm(
    VideoItem original, {
    required String title,
    required String collection,
    required int? year,
    required String genre,
    required String description,
  }) {
    String? differs(String typed, String? was) {
      final t = typed.trim();
      return t.isEmpty || t == (was ?? '') ? null : t;
    }

    final g = genre.trim(), d = description.trim();
    return VideoEdit(
      title: title.trim().isEmpty ? null : differs(title, original.title),
      collection: collection.trim().isEmpty ? null : differs(collection, original.collection),
      year: year == original.year ? null : year,
      genre: differs(g, original.genre),
      description: differs(d, original.description),
      cleared: {
        if (year == null && original.year != null) 'year',
        if (g.isEmpty && original.genre != null) 'genre',
        if (d.isEmpty && original.description != null) 'description',
      },
    );
  }

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (collection != null) 'collection': collection,
        if (year != null) 'year': year,
        if (genre != null) 'genre': genre,
        if (description != null) 'description': description,
        if (cleared.isNotEmpty) 'cleared': cleared.toList()..sort(),
      };

  factory VideoEdit.fromJson(Map<String, dynamic> j) => VideoEdit(
        title: j['title'] as String?,
        collection: j['collection'] as String?,
        year: j['year'] as int?,
        genre: j['genre'] as String?,
        description: j['description'] as String?,
        cleared: {...(j['cleared'] as List? ?? const []).cast<String>()},
      );
}

/// How far into a video the user got.
class VideoPlace {
  final Duration position;
  final bool watched;

  /// When this was last changed (ms since 1970), for "Continue watching" order and merging backups.
  final int updatedMs;

  const VideoPlace({required this.position, this.watched = false, required this.updatedMs});

  /// 0 to 1, for the bar under a thumbnail.
  double progress(Duration total) =>
      total <= Duration.zero ? 0 : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

  /// Started but not finished.
  bool get inProgress => !watched && position > const Duration(seconds: 5);

  Map<String, dynamic> toJson() => {
        'positionMs': position.inMilliseconds,
        if (watched) 'watched': true,
        'updatedMs': updatedMs,
      };

  factory VideoPlace.fromJson(Map<String, dynamic> j) => VideoPlace(
        position: Duration(milliseconds: (j['positionMs'] as int?) ?? 0),
        watched: (j['watched'] as bool?) ?? false,
        updatedMs: (j['updatedMs'] as int?) ?? 0,
      );
}
