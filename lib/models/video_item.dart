// Videos (0.1.40): the Videos tab's data shapes.
//
// VideoItem is one video file found in the video folders (Settings › Folders & scanning), made
// by services/video_scanner.dart and saved in videos.json. Its collection, category, season,
// episode and title come from its folders and file name (services/video_names.dart) or its tags.
// VideoEdit is the user's changes to those details, kept apart from the file and laid over it,
// like TrackEdit for songs. VideoPlace is where the user got to in it, so it can carry on from
// there, and whether it's been watched. VideoCollection is a collection of videos, like an album
// (a series, a film, a folder of home videos), built from the videos by VideoLibraryModel.
import 'package:path/path.dart' as p;

/// The shape of a video's or a collection's picture on the Videos tab (Settings › Videos sets
/// the usual one; Edit details / Edit collection can give each its own; 0.1.40).
enum PictureShape {
  wide('Wide', 16 / 9),
  tall('Tall', 2 / 3),
  square('Square', 1);

  final String label;

  /// Width / height.
  final double aspect;
  const PictureShape(this.label, this.aspect);

  static PictureShape? byName(Object? name) => name is String ? values.asNameMap()[name] : null;
}

/// One video file.
class VideoItem {
  /// `video:<absolute path>`.
  final String id;
  final String path;
  final String title;

  /// The collection the video belongs to, like an album ("South Park", "Holiday 2024").
  final String collection;

  /// The category folder it's in ("TV", "Anime", "Films"), if any.
  final String? category;

  /// Season number (0 = specials) and episode number, when known.
  final int? season;
  final int? episode;

  /// A part of a season: season 1.2 is [season] 1, [subSeason] 2 (30 Sep; from folders like
  /// "Season 1.2", or Edit details). Null for a plain season.
  final int? subSeason;

  /// A named part of the collection that has no season number ("Alicization").
  final String? part;

  /// The season's own title, as its folder ("Season 1 - Offline News") or the series'
  /// tvshow.nfo names it. The user can give a season another one (VideoLibraryModel.seasonTitleOf).
  final String? seasonTitle;

  /// An extra (featurette, opening, deleted scene) rather than an episode.
  final bool extra;

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

  /// A poster picture in the collection's folder (poster.jpg, folder.jpg…), if there is one.
  final String? cover;

  /// Subtitle files beside the video (same name, or in a Subs folder); offered as choices.
  final List<String> subtitles;

  /// When HomeTunes first found the file (for "Recently added").
  final int? addedMs;

  /// Which version of the name-reading rules made this (the scanner re-reads older ones once).
  final int scan;

  /// The collection's description from a tvshow.nfo in its folder, if there is one.
  final String? showPlot;

  /// When the .nfo files it was read with were last changed (the scanner re-reads it when they
  /// change, even if the video didn't).
  final int? nfoMs;

  const VideoItem({
    required this.id,
    required this.path,
    required this.title,
    required this.collection,
    this.category,
    this.season,
    this.episode,
    this.subSeason,
    this.part,
    this.seasonTitle,
    this.extra = false,
    this.year,
    this.genre,
    this.description,
    this.duration = Duration.zero,
    this.width,
    this.height,
    this.modifiedMs,
    this.sizeBytes,
    this.thumb,
    this.cover,
    this.subtitles = const [],
    this.addedMs,
    this.scan = 0,
    this.showPlot,
    this.nfoMs,
  });

  static String idFor(String path) => 'video:$path';

  /// "MKV", "MP4"…
  String get format => p.extension(path).replaceFirst('.', '').toUpperCase();

  /// "1920×1080", or null when not known yet.
  String? get resolution => (width != null && height != null && width! > 0) ? '$width×$height' : null;

  /// "1", "1.2" (a season with a sub number), or null.
  String? get seasonLabel => season == null ? null : seasonText(season!, subSeason);

  /// "S1 E4", "S1.2 E3", "Special 3", "E12", or null.
  String? get episodeLabel {
    if (extra) return null;
    if (season == 0) return episode != null ? 'Special $episode' : 'Special';
    if (season != null && episode != null) return 'S$seasonLabel E$episode';
    if (episode != null) return 'E$episode';
    return null;
  }

  VideoItem _with({
    String? thumb,
    Duration? duration,
    int? width,
    int? height,
    String? title,
    String? collection,
    String? category,
    int? season,
    int? episode,
    int? subSeason,
    int? year,
    String? genre,
    String? description,
    bool? extra,
    Set<String> clear = const {},
  }) {
    final newSeason = clear.contains('season') ? null : (season ?? this.season);
    // Emptying the season empties its sub number too; a new season number without one keeps the
    // old sub number only if the edit doesn't say otherwise.
    final newSub = newSeason == null || clear.contains('subSeason') ? null : (subSeason ?? this.subSeason);
    return VideoItem(
        id: id,
        path: path,
        title: title ?? this.title,
        collection: collection ?? this.collection,
        category: clear.contains('category') ? null : (category ?? this.category),
        season: newSeason,
        episode: clear.contains('episode') ? null : (episode ?? this.episode),
        subSeason: newSub,
        part: part,
        // A season number changed by an edit: the old season's title no longer applies.
        seasonTitle: newSeason != this.season || newSub != this.subSeason ? null : seasonTitle,
        extra: extra ?? this.extra,
        year: clear.contains('year') ? null : (year ?? this.year),
        genre: clear.contains('genre') ? null : (genre ?? this.genre),
        description: clear.contains('description') ? null : (description ?? this.description),
        duration: duration ?? this.duration,
        width: width ?? this.width,
        height: height ?? this.height,
        modifiedMs: modifiedMs,
        sizeBytes: sizeBytes,
        thumb: thumb ?? this.thumb,
        cover: cover,
        subtitles: subtitles,
        addedMs: addedMs,
        scan: scan,
        showPlot: showPlot,
        nfoMs: nfoMs,
      );
  }

  /// A copy with things learned after the scan: its thumbnail, length and picture size.
  VideoItem copyWith({String? thumb, Duration? duration, int? width, int? height}) =>
      _with(thumb: thumb, duration: duration, width: width, height: height);

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'title': title,
        'collection': collection,
        if (category != null) 'category': category,
        if (season != null) 'season': season,
        if (episode != null) 'episode': episode,
        if (subSeason != null) 'subSeason': subSeason,
        if (part != null) 'part': part,
        if (seasonTitle != null) 'seasonTitle': seasonTitle,
        if (extra) 'extra': true,
        if (year != null) 'year': year,
        if (genre != null) 'genre': genre,
        if (description != null) 'description': description,
        'durationMs': duration.inMilliseconds,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (modifiedMs != null) 'modifiedMs': modifiedMs,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (thumb != null) 'thumb': thumb,
        if (cover != null) 'cover': cover,
        if (subtitles.isNotEmpty) 'subtitles': subtitles,
        if (addedMs != null) 'addedMs': addedMs,
        if (scan != 0) 'scan': scan,
        if (showPlot != null) 'showPlot': showPlot,
        if (nfoMs != null) 'nfoMs': nfoMs,
      };

  /// Reads one back from videos.json. Throws on a wrong shape (the model skips that entry).
  factory VideoItem.fromJson(Map<String, dynamic> j) {
    final path = j['path'] as String;
    return VideoItem(
      id: (j['id'] as String?) ?? idFor(path),
      path: path,
      title: (j['title'] as String?) ?? p.basenameWithoutExtension(path),
      collection: (j['collection'] as String?) ?? p.basename(p.dirname(path)),
      category: j['category'] as String?,
      season: j['season'] as int?,
      episode: j['episode'] as int?,
      subSeason: j['subSeason'] as int?,
      part: j['part'] as String?,
      seasonTitle: j['seasonTitle'] as String?,
      extra: (j['extra'] as bool?) ?? false,
      year: j['year'] as int?,
      genre: j['genre'] as String?,
      description: j['description'] as String?,
      duration: Duration(milliseconds: (j['durationMs'] as int?) ?? 0),
      width: j['width'] as int?,
      height: j['height'] as int?,
      modifiedMs: j['modifiedMs'] as int?,
      sizeBytes: j['sizeBytes'] as int?,
      thumb: j['thumb'] as String?,
      cover: j['cover'] as String?,
      subtitles: (j['subtitles'] as List? ?? const []).cast<String>(),
      addedMs: j['addedMs'] as int?,
      scan: (j['scan'] as int?) ?? 0,
      showPlot: j['showPlot'] as String?,
      nfoMs: j['nfoMs'] as int?,
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
  final String? category;
  final int? season;
  final int? episode;

  /// The season's sub number (season 1.2 → 2).
  final int? subSeason;
  final int? year;
  final String? genre;
  final String? description;

  /// Details the user emptied on purpose ('year', 'genre', 'description', 'category', 'season',
  /// 'episode', 'subSeason').
  final Set<String> cleared;

  const VideoEdit({
    this.title,
    this.collection,
    this.category,
    this.season,
    this.episode,
    this.subSeason,
    this.year,
    this.genre,
    this.description,
    this.cleared = const {},
  });

  bool get isEmpty =>
      title == null &&
      collection == null &&
      category == null &&
      season == null &&
      episode == null &&
      subSeason == null &&
      year == null &&
      genre == null &&
      description == null &&
      cleared.isEmpty;

  /// The video as the user wants to see it.
  VideoItem applyTo(VideoItem v) => v._with(
        title: title,
        collection: collection,
        category: category,
        season: season,
        episode: episode,
        subSeason: subSeason,
        year: year,
        genre: genre,
        description: description,
        // Given a season or episode number, an extra becomes an episode like the others.
        extra: season != null || episode != null ? false : null,
        clear: cleared,
      );

  /// This edit with some details changed on top (null = keep this edit's own value). A value set
  /// here is no longer "cleared"; names in [clear] become cleared.
  VideoEdit merge({
    String? title,
    String? collection,
    String? category,
    int? season,
    int? episode,
    int? subSeason,
    int? year,
    String? genre,
    String? description,
    Set<String> clear = const {},
  }) {
    final set = {
      if (category != null) 'category',
      if (season != null) 'season',
      if (episode != null) 'episode',
      if (subSeason != null) 'subSeason',
      if (year != null) 'year',
      if (genre != null) 'genre',
      if (description != null) 'description',
    };
    return VideoEdit(
      title: title ?? this.title,
      collection: collection ?? this.collection,
      category: clear.contains('category') ? null : (category ?? this.category),
      season: clear.contains('season') ? null : (season ?? this.season),
      episode: clear.contains('episode') ? null : (episode ?? this.episode),
      subSeason: clear.contains('subSeason') ? null : (subSeason ?? this.subSeason),
      year: clear.contains('year') ? null : (year ?? this.year),
      genre: clear.contains('genre') ? null : (genre ?? this.genre),
      description: clear.contains('description') ? null : (description ?? this.description),
      cleared: {for (final c in cleared) if (!set.contains(c)) c, ...clear},
    );
  }

  /// The edit that turns [original] into the details typed in the editor: only what differs from
  /// the file is kept, and an emptied detail is remembered as cleared.
  static VideoEdit fromForm(
    VideoItem original, {
    required String title,
    required String collection,
    required int? year,
    required String genre,
    required String description,
    int? season,
    int? episode,
    int? subSeason,
    bool seasonKnown = false,
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
      season: !seasonKnown || season == original.season ? null : season,
      episode: !seasonKnown || episode == original.episode ? null : episode,
      subSeason: !seasonKnown || season == null || subSeason == original.subSeason ? null : subSeason,
      cleared: {
        if (year == null && original.year != null) 'year',
        if (g.isEmpty && original.genre != null) 'genre',
        if (d.isEmpty && original.description != null) 'description',
        if (seasonKnown && season == null && original.season != null) 'season',
        if (seasonKnown && episode == null && original.episode != null) 'episode',
        if (seasonKnown && season != null && subSeason == null && original.subSeason != null) 'subSeason',
      },
    );
  }

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (collection != null) 'collection': collection,
        if (category != null) 'category': category,
        if (season != null) 'season': season,
        if (episode != null) 'episode': episode,
        if (subSeason != null) 'subSeason': subSeason,
        if (year != null) 'year': year,
        if (genre != null) 'genre': genre,
        if (description != null) 'description': description,
        if (cleared.isNotEmpty) 'cleared': cleared.toList()..sort(),
      };

  factory VideoEdit.fromJson(Map<String, dynamic> j) => VideoEdit(
        title: j['title'] as String?,
        collection: j['collection'] as String?,
        category: j['category'] as String?,
        season: j['season'] as int?,
        episode: j['episode'] as int?,
        subSeason: j['subSeason'] as int?,
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

/// A collection of videos, like an album: a series, a film, a folder of home videos.
class VideoCollection {
  final String name;

  /// In watching order: seasons, then named parts, then specials, then extras (see [groups]).
  final List<VideoItem> videos;
  final String? category;
  final int? year;
  final String? genre;

  /// The user's description of the collection (Edit collection).
  final String? description;

  /// A poster picture from the collection's folder, if there is one.
  final String? cover;

  const VideoCollection({
    required this.name,
    required this.videos,
    this.category,
    this.year,
    this.genre,
    this.description,
    this.cover,
  });

  /// Lower-case name: favourites, descriptions and track choices are kept under it.
  String get key => keyFor(name);
  static String keyFor(String name) => name.trim().toLowerCase();

  /// Episodes and films, not extras.
  List<VideoItem> get main => [for (final v in videos) if (!v.extra) v];

  Duration get totalDuration => videos.fold(Duration.zero, (a, v) => a + v.duration);

  /// The newest "added" time among its videos.
  int get addedMs => videos.fold<int>(0, (m, v) => (v.addedMs ?? 0) > m ? (v.addedMs ?? 0) : m);

  /// The videos split into headed groups, in order: "Season 1"…, named parts, the rest
  /// ("Episodes"), "Specials", "Extras". One group with no heading when there's only one.
  List<(String?, List<VideoItem>)> get groups {
    final out = <String, List<VideoItem>>{};
    for (final v in videos) {
      (out[groupOf(v)] ??= []).add(v);
    }
    if (out.length == 1) return [(null, out.values.single)];
    return [for (final e in out.entries) (e.key, e.value)];
  }

  /// The heading a video is listed under on the collection's page.
  static String groupOf(VideoItem v) {
    if (v.extra) return 'Extras';
    if (v.season == 0) return 'Specials';
    if (v.season != null) return 'Season ${v.seasonLabel}';
    return v.part ?? 'Episodes';
  }
}

/// "1", or "1.2" for a season with a sub number.
String seasonText(int season, int? subSeason) => subSeason == null ? '$season' : '$season.$subSeason';

/// The order videos are listed in within a collection: seasons (by number), then named parts
/// and loose episodes (in folder order), then specials, then extras; within each by episode
/// number, then title.
List<VideoItem> sortForCollection(Iterable<VideoItem> videos) {
  final list = videos.toList();
  // Where each part / "Episodes" group starts in folder order.
  final partStart = <String, String>{};
  for (final v in list) {
    final g = VideoCollection.groupOf(v);
    final seen = partStart[g];
    if (seen == null || v.path.compareTo(seen) < 0) partStart[g] = v.path;
  }
  int rank(VideoItem v) => v.extra ? 3 : v.season == 0 ? 2 : v.season != null ? 0 : 1;
  list.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    if (rank(a) == 0 && a.season != b.season) return a.season!.compareTo(b.season!);
    // Season 1, then 1.1, 1.2… (a plain season before its sub numbers).
    if (rank(a) == 0 && a.subSeason != b.subSeason) return (a.subSeason ?? -1).compareTo(b.subSeason ?? -1);
    if (rank(a) == 1) {
      final ga = VideoCollection.groupOf(a), gb = VideoCollection.groupOf(b);
      if (ga != gb) return partStart[ga]!.toLowerCase().compareTo(partStart[gb]!.toLowerCase());
    }
    final ea = a.episode, eb = b.episode;
    if (ea != null && eb != null && ea != eb) return ea.compareTo(eb);
    if (ea != null && eb == null) return -1;
    if (ea == null && eb != null) return 1;
    final t = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return t != 0 ? t : a.path.compareTo(b.path);
  });
  return list;
}

/// Which audio and subtitle track to pick for a collection's videos (remembered from the last
/// choice made while watching one of them). Matched by language, then by title.
class TrackPick {
  /// Turned off.
  final bool off;
  final String? language;
  final String? title;
  const TrackPick({this.off = false, this.language, this.title});

  static const none = TrackPick(off: true);

  Map<String, dynamic> toJson() => {if (off) 'off': true, if (language != null) 'language': language, if (title != null) 'title': title};

  factory TrackPick.fromJson(Map<String, dynamic> j) =>
      TrackPick(off: (j['off'] as bool?) ?? false, language: j['language'] as String?, title: j['title'] as String?);
}
