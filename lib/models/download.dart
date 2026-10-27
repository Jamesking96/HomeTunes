// Downloads (0.2.3, step 3 of the Servers & Downloads plan): the shapes kept in downloads.json.
//
// A DownloadEntry is one song (or audiobook file) or one video from a server that the user asked
// to have on this device, with how far its download has got. A KeepOffline is an album, playlist,
// Liked Songs, audiobook, collection or season the user asked to keep offline: whatever is in it
// now and later is downloaded by itself. DownloadQuality is the copy chosen: the original file, or
// a smaller one the server converts (a picture height for videos, a bitrate for music).
//
// The state machine (queued → running ↔ paused → done, or failed / noRoom) is run by
// state/downloads_model.dart; only these values are saved (a download that was running when the
// app closed is put back as queued).

/// Which copy to download.
class DownloadQuality {
  /// For a video: the tallest picture (1080, 720, 480). For music: the bitrate in kbit/s (320,
  /// 192, 128). Null for the original file.
  final int? limit;
  final bool video;
  const DownloadQuality.original({this.video = false}) : limit = null;
  const DownloadQuality.videoHeight(int height)
      : limit = height,
        video = true;
  const DownloadQuality.audioBitrate(int kbps)
      : limit = kbps,
        video = false;

  bool get isOriginal => limit == null;

  /// "Original file", "720p", "192 kbit/s".
  String get label => isOriginal ? 'Original file' : (video ? '${limit}p' : '$limit kbit/s');

  /// Saved as "original", "v720" or "a192".
  String get code => isOriginal ? 'original' : '${video ? 'v' : 'a'}$limit';

  static DownloadQuality parse(Object? code, {bool video = false}) {
    if (code is! String || code == 'original') return DownloadQuality.original(video: video);
    final n = int.tryParse(code.substring(1));
    if (n == null || n <= 0) return DownloadQuality.original(video: video);
    return code.startsWith('v') ? DownloadQuality.videoHeight(n) : DownloadQuality.audioBitrate(n);
  }

  /// The smaller copies offered.
  static const videoHeights = [1080, 720, 480];
  static const audioBitrates = [320, 192, 128];

  /// About how big a copy of [length] is, in bytes (for the space limit before the real size is
  /// known). [originalBytes] when the server said.
  int estimate(Duration length, {int? originalBytes}) {
    if (isOriginal) {
      return originalBytes ?? (length.inSeconds * (video ? 1000000 : 40000));
    }
    final bitsPerSecond = video
        ? switch (limit!) { >= 1080 => 10000000, >= 720 => 4000000, _ => 1500000 } + 192000
        : limit! * 1000;
    return length.inSeconds * bitsPerSecond ~/ 8;
  }

  @override
  bool operator ==(Object other) => other is DownloadQuality && other.code == code && other.video == video;

  @override
  int get hashCode => Object.hash(code, video);
}

enum DownloadKind { song, video }

/// Why it was downloaded.
enum DownloadOrigin {
  /// The user chose Download.
  manual,

  /// It's in something kept offline.
  keep,

  /// An episode downloaded ahead while watching the one before (removed once watched).
  ahead,
}

enum DownloadState {
  /// Waiting its turn (or for Wi-Fi).
  queued,
  running,
  paused,

  /// Couldn't be downloaded; [DownloadEntry.error] says why. Retry tries again.
  failed,

  /// Waiting because the space for downloads is full.
  noRoom,

  /// On this device.
  done,
}

/// One song, audiobook file or video to have on this device.
class DownloadEntry {
  /// The song's or video's id (`server:…` or `jf:<server>:<item>`).
  final String id;
  final DownloadKind kind;
  final String title;

  /// "Artist · Album", "Silo · S1 E2".
  final String subtitle;
  final DownloadQuality quality;
  final DownloadOrigin origin;
  final DownloadState state;

  /// Where the file is (once done), and its subtitle files (videos), absolute paths.
  final String? file;
  final List<String> subtitles;

  /// Its size once done (or so far), and the expected size if known.
  final int bytes;
  final int? expected;

  /// 0–1 while downloading.
  final double progress;
  final String? error;
  final int addedMs;
  final int? doneMs;

  /// Is it an audiobook file (for the Downloads page's groups).
  final bool book;

  const DownloadEntry({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle = '',
    required this.quality,
    this.origin = DownloadOrigin.manual,
    this.state = DownloadState.queued,
    this.file,
    this.subtitles = const [],
    this.bytes = 0,
    this.expected,
    this.progress = 0,
    this.error,
    required this.addedMs,
    this.doneMs,
    this.book = false,
  });

  bool get isDone => state == DownloadState.done;

  /// Not finished, and not given up on.
  bool get isWaiting => state == DownloadState.queued || state == DownloadState.running || state == DownloadState.paused;

  DownloadEntry copyWith({
    DownloadState? state,
    String? file,
    List<String>? subtitles,
    int? bytes,
    int? expected,
    double? progress,
    String? error,
    bool clearError = false,
    int? doneMs,
    DownloadOrigin? origin,
    DownloadQuality? quality,
    String? title,
    String? subtitle,
  }) =>
      DownloadEntry(
        id: id,
        kind: kind,
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        quality: quality ?? this.quality,
        origin: origin ?? this.origin,
        state: state ?? this.state,
        file: file ?? this.file,
        subtitles: subtitles ?? this.subtitles,
        bytes: bytes ?? this.bytes,
        expected: expected ?? this.expected,
        progress: progress ?? this.progress,
        error: clearError ? null : (error ?? this.error),
        addedMs: addedMs,
        doneMs: doneMs ?? this.doneMs,
        book: book,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        if (subtitle.isNotEmpty) 'subtitle': subtitle,
        'quality': quality.code,
        if (origin != DownloadOrigin.manual) 'origin': origin.name,
        // A download that was running is picked up again as waiting.
        'state': (state == DownloadState.running ? DownloadState.queued : state).name,
        if (file != null) 'file': file,
        if (subtitles.isNotEmpty) 'subtitles': subtitles,
        if (bytes > 0) 'bytes': bytes,
        if (expected != null) 'expected': expected,
        if (error != null) 'error': error,
        'addedMs': addedMs,
        if (doneMs != null) 'doneMs': doneMs,
        if (book) 'book': true,
      };

  static DownloadEntry? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final kind = DownloadKind.values.asNameMap()[j['kind']] ?? DownloadKind.song;
    return DownloadEntry(
      id: j['id'] as String,
      kind: kind,
      title: (j['title'] as String?) ?? '',
      subtitle: (j['subtitle'] as String?) ?? '',
      quality: DownloadQuality.parse(j['quality'], video: kind == DownloadKind.video),
      origin: DownloadOrigin.values.asNameMap()[j['origin']] ?? DownloadOrigin.manual,
      state: DownloadState.values.asNameMap()[j['state']] ?? DownloadState.queued,
      file: j['file'] as String?,
      subtitles: [for (final s in (j['subtitles'] is List ? j['subtitles'] as List : const [])) if (s is String) s],
      bytes: j['bytes'] is int ? j['bytes'] as int : 0,
      expected: j['expected'] is int ? j['expected'] as int : null,
      error: j['error'] as String?,
      addedMs: j['addedMs'] is int ? j['addedMs'] as int : 0,
      doneMs: j['doneMs'] as int?,
      book: j['book'] == true,
    );
  }
}

/// What can be kept offline.
enum KeepKind {
  album('Album'),
  playlist('Playlist'),
  liked('Liked Songs'),
  book('Audiobook'),
  collection('Collection'),
  season('Season');

  final String label;
  const KeepKind(this.label);
}

/// Something kept offline: everything in it is downloaded, now and as more is added.
class KeepOffline {
  final KeepKind kind;

  /// An album's key, a playlist's id, a book's id, a collection's key, or for a season
  /// `<collection key>|<season heading>` ("silo|Season 1"). Empty for Liked Songs.
  final String key;

  /// The name shown ("Silo · Season 1").
  final String label;
  final DownloadQuality quality;
  const KeepOffline(this.kind, this.key, this.label, this.quality);

  /// Unique per thing kept.
  String get id => '${kind.name}:$key';

  Map<String, dynamic> toJson() => {'kind': kind.name, 'key': key, 'label': label, 'quality': quality.code};

  static KeepOffline? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = KeepKind.values.asNameMap()[j['kind']];
    if (kind == null || j['key'] is! String) return null;
    final video = kind == KeepKind.collection || kind == KeepKind.season;
    return KeepOffline(kind, j['key'] as String, (j['label'] as String?) ?? kind.label,
        DownloadQuality.parse(j['quality'], video: video));
  }
}
