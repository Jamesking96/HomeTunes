/// Where a track comes from.
enum TrackSource { local, server }

/// One playable song, either a file on disk or a song on a Subsonic server.
class Track {
  /// Stable id. Local tracks: `local:<absolute path>`. Server tracks: `server:<subsonic id>`.
  final String id;
  final TrackSource source;

  final String title;
  final String artist;
  final String album;

  /// Artist used for grouping albums (falls back to [artist]).
  final String albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final String? genre;
  final Duration duration;

  /// Local file path (local tracks only).
  final String? path;

  /// Subsonic song id (server tracks only).
  final String? remoteId;

  /// Local tracks: path to a cached cover image. Server tracks: Subsonic coverArt id.
  final String? art;

  /// Last-modified time of the file, used to skip unchanged files when rescanning.
  final int? modifiedMs;

  /// Chapter markers inside the file (audiobooks), in order. Usually empty.
  final List<Chapter> chapters;

  const Track({
    required this.id,
    required this.source,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genre,
    this.duration = Duration.zero,
    this.path,
    this.remoteId,
    this.art,
    this.modifiedMs,
    this.chapters = const [],
  });

  bool get isLocal => source == TrackSource.local;

  /// Some files don't say how long they are; the length is then learned the
  /// first time the song plays.
  bool get hasDuration => duration > Duration.zero;

  /// Key that groups tracks into an album.
  String get albumKey => '${albumArtist.toLowerCase()}\u0000${album.toLowerCase()}';

  Track copyWith({String? art, Duration? duration, List<Chapter>? chapters}) => Track(
        id: id,
        source: source,
        title: title,
        artist: artist,
        album: album,
        albumArtist: albumArtist,
        trackNumber: trackNumber,
        discNumber: discNumber,
        year: year,
        genre: genre,
        duration: duration ?? this.duration,
        path: path,
        remoteId: remoteId,
        art: art ?? this.art,
        modifiedMs: modifiedMs,
        chapters: chapters ?? this.chapters,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'title': title,
        'artist': artist,
        'album': album,
        'albumArtist': albumArtist,
        if (trackNumber != null) 'trackNumber': trackNumber,
        if (discNumber != null) 'discNumber': discNumber,
        if (year != null) 'year': year,
        if (genre != null) 'genre': genre,
        'durationMs': duration.inMilliseconds,
        if (path != null) 'path': path,
        if (remoteId != null) 'remoteId': remoteId,
        if (art != null) 'art': art,
        if (modifiedMs != null) 'modifiedMs': modifiedMs,
        if (chapters.isNotEmpty) 'chapters': [for (final c in chapters) c.toJson()],
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        source: TrackSource.values.byName(j['source'] as String),
        title: j['title'] as String,
        artist: j['artist'] as String,
        album: j['album'] as String,
        albumArtist: j['albumArtist'] as String,
        trackNumber: j['trackNumber'] as int?,
        discNumber: j['discNumber'] as int?,
        year: j['year'] as int?,
        genre: j['genre'] as String?,
        duration: Duration(milliseconds: (j['durationMs'] as int?) ?? 0),
        path: j['path'] as String?,
        remoteId: j['remoteId'] as String?,
        art: j['art'] as String?,
        modifiedMs: j['modifiedMs'] as int?,
        chapters: [
          for (final c in (j['chapters'] as List? ?? const [])) Chapter.fromJson(c as Map<String, dynamic>),
        ],
      );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A chapter marker inside an audio file.
class Chapter {
  final Duration start;
  final String title;
  const Chapter(this.start, this.title);

  Map<String, dynamic> toJson() => {'startMs': start.inMilliseconds, 'title': title};

  factory Chapter.fromJson(Map<String, dynamic> j) =>
      Chapter(Duration(milliseconds: (j['startMs'] as int?) ?? 0), (j['title'] as String?) ?? '');

  @override
  bool operator ==(Object other) => other is Chapter && other.start == start && other.title == title;

  @override
  int get hashCode => Object.hash(start, title);
}

/// An album built by grouping tracks.
class Album {
  final String key;
  final String title;
  final String artist;
  final int? year;
  final List<Track> tracks;

  Album({required this.key, required this.title, required this.artist, this.year, required this.tracks});

  /// First track that has cover art.
  Track? get artTrack {
    for (final t in tracks) {
      if (t.art != null) return t;
    }
    return tracks.isEmpty ? null : tracks.first;
  }

  Duration get totalDuration => tracks.fold(Duration.zero, (a, t) => a + t.duration);
}

/// An artist built by grouping albums.
class Artist {
  final String name;
  final List<Album> albums;

  Artist({required this.name, required this.albums});

  List<Track> get tracks => [for (final a in albums) ...a.tracks];
}
