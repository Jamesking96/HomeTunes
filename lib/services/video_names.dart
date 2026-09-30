// Videos (0.1.32): what a video's folders and file name say about it.
//
// Video libraries are usually laid out like this (checked against a real one on 30 Sep):
//   <video folder>\TV\South Park - Complete\Season 01\South Park (1997) - S01E01 - Cartman Gets an Anal Probe [WEBDL-1080p][AC3 5.1].mkv
//   <video folder>\Anime\Claymore 1-26 DVDRip (Dual Audio)\Claymore Ep. 11 - Those Who Rend Asunder III.mkv
//   <video folder>\Films\Mickey.17.2025.2160p.HDR10Plus.DV.WEBRip.DDP5 1.Atmos.X265.HEVC-PSA\Mickey.17...mkv
// so:
//  * a first folder with a name like TV, Anime or Films is a **category**;
//  * the folder under it (or the first folder, when there's no category) is the **collection**,
//    like an album: its name is tidied of release details ("South Park - Complete" → "South Park",
//    "Battlestar Galactica (2003) Season 1-4 S01-S04 (1080p BluRay…)" → "Battlestar Galactica", 2003);
//  * a video loose in a category folder (a film) is a collection of its own;
//  * folders inside the collection give the **season** ("Season 01", "S02", "Book Two - Earth"),
//    "Specials" (season 0) or **extras** (Featurettes, Extras, NCOP…), or else a named part
//    ("Sword Art Online II");
//  * the file name gives the season and **episode** (S01E05, "S02 E02", "Season 2 Episode 7",
//    "Ep. 11", "Episode 21", "- 06") and the episode's title, if it has one.
// Everything here only looks at the text of the paths (no disk), so it's unit tested with real
// names (test/video_names_test.dart). The user can change any of it (VideoEdit).
import 'package:path/path.dart' as p;

/// First-level folder names that are categories rather than collections (lower case).
const videoCategoryNames = {
  'tv', 'tv shows', 'shows', 'series', 'tv series', 'anime', 'films', 'movies', 'film', 'movie',
  'cartoons', 'documentaries', 'docs', 'kids', 'music videos', 'home videos', 'clips', 'videos', 'concerts',
};

/// Categories whose videos are films: a film's name isn't read for episode numbers
/// ("Mickey 17" isn't episode 17).
const _filmCategories = {'films', 'movies', 'film', 'movie'};

/// Folder names that hold extras rather than episodes (matched as whole words, lower case).
const _extraWords = {
  'extras', 'extra', 'featurettes', 'featurette', 'bonus', 'behind the scenes', 'deleted scenes', 'nc', 'ncop',
  'nced', 'interviews', 'trailers', 'trailer', 'samples', 'sample', 'screenshots', 'ost', 'osts', 'soundtrack',
};

/// Words that start the release details in a name; the title is cut before the first one.
final _junk = RegExp(
  r'(?:^|[\s\-_.\[\(])(?:complete|collection|batch|season\s*\d|seasons|s\d{1,2}(?:\s*-\s*s?\d{1,2})?(?![a-z0-9])|'
  r'\d{1,3}\s*-\s*\d{1,3}(?![0-9])|\d{3,4}p|4k|uhd|hdr\w*|bluray|blu-ray|bdrip|brrip|bd|dvdrip|dvd|web-?dl|webrip|'
  r'web|hdtv|x26[45]|h\.?26[45]|hevc|avc|av1|10bit|8bit|dual[\s\-]?audio|multi|aac\w*|ac3|eac3|ddp?\d|dts\w*|'
  r'atmos|remux|proper|repack|primewire|rarbg|eztv\w*|galaxytv|yts\w*|mp4)(?![a-z])',
  caseSensitive: false,
);

/// A tidied title and the year found in it, from a folder or file name.
/// "Battlestar Galactica (2003) Season 1-4 S01-S04 (1080p BluRay x265)" → ("Battlestar Galactica", 2003)
/// "Mickey.17.2025.2160p.HDR10Plus.DV.WEBRip" → ("Mickey 17", 2025)
({String title, int? year}) cleanVideoName(String name) {
  var t = spacedName(name);
  // Release groups in brackets at the start: "[Anime Time] Black Lagoon", "[DeadFish] Steins;Gate".
  t = t.replaceFirst(RegExp(r'^(?:\s*[\[\{][^\]\}]*[\]\}]\s*)+'), '');
  int? year;
  final bracket = RegExp(r'[\(\[\{]').firstMatch(t);
  final junk = _junk.firstMatch(t);
  final junkAt = junk != null && junk.start > 0 ? junk.start : null;
  final bracketAt = bracket != null && bracket.start > 0 ? bracket.start : null;
  // A year in the first bracket, e.g. "(2003)", "(2007-2010)", "(TV Series 2006-2007)", when that
  // bracket comes before the release details.
  final inBracket = bracketAt == null
      ? null
      : RegExp(r'(?:19|20)\d\d').firstMatch(t.substring(bracketAt).split(RegExp(r'[\)\]\}]')).first);
  if (bracketAt != null && inBracket != null && (junkAt == null || bracketAt <= junkAt)) {
    year = int.parse(inBracket.group(0)!);
    t = t.substring(0, bracketAt);
  } else {
    final cut = [?junkAt, ?bracketAt].fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    // A dotted release name ending in a year ("Film.2012") has its year at the end.
    final dotted = spacedName(name) != name;
    if (cut != null || dotted) {
      if (cut != null) t = t.substring(0, cut);
      // Release details were cut off: a year just before them is the year
      // ("Mickey 17 2025 2160p" → "Mickey 17", 2025; "Blade Runner 2049" alone keeps its number).
      final y = RegExp(r'^(.*\S)\s+((?:19|20)\d\d)[\s\-]*$').firstMatch(t);
      if (y != null) {
        year = int.parse(y.group(2)!);
        t = y.group(1)!;
      }
    }
  }
  t = t
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+v\d$'), '') // "Toradora! v2"
      .replaceAll(RegExp(r'[\s\-–_.,:+]+$'), '')
      .trim();
  return (title: t.isEmpty ? name.trim() : t, year: year);
}

/// Dots or underscores used instead of spaces become spaces: when there are more of them than
/// spaces ("Mickey.17.2025.2160p.DDP5 1.Atmos"), or any underscores ("Black_Rock_Shooter_06").
String spacedName(String name) {
  final dots = '.'.allMatches(name).length, spaces = ' '.allMatches(name).length;
  if (dots > spaces || name.contains('_')) return name.replaceAll(RegExp(r'[._]+'), ' ');
  return name;
}

/// True when [text] starts straight away with release details ("1080p BluRay x265-RARBG").
bool _isOnlyJunk(String text) {
  final t = text.trim();
  if (t.isEmpty) return true;
  final j = _junk.firstMatch(t);
  return j != null && j.start == 0;
}

/// What a video's place in the folders says about it.
class VideoPathInfo {
  final String collection;
  /// The collection's folder (where a poster picture is looked for).
  final String collectionFolder;
  final String? category;
  final int? season;
  final int? episode;
  final String title;
  final int? year;
  final bool extra;

  /// A named part of the collection when there's no season number ("Sword Art Online II").
  final String? part;

  /// The season's own title from its folder: "Season 1 - Offline News" → "Offline News".
  final String? seasonTitle;

  /// The season's sub number from its folder: "Season 1.2" → 2.
  final int? subSeason;

  const VideoPathInfo({
    required this.collection,
    required this.collectionFolder,
    required this.title,
    this.category,
    this.season,
    this.episode,
    this.year,
    this.extra = false,
    this.part,
    this.seasonTitle,
    this.subSeason,
  });
}

/// "Season 1.2" / "S01.2" / "Series 3.1": the season and its sub number, as written.
final _subSeason = RegExp(r'((?:^|[\s\-_.])(?:season|series|book|s)[\s_]*\d{1,2})\.(\d{1,2})(?![0-9a-z])', caseSensitive: false);

/// The sub number of a season folder: "Season 1.2" → 2, "S01.1" → 1; null for a plain season
/// ("Season 1", "Ghosts.2021.S01.1080p").
int? subSeasonOfFolder(String name) {
  final m = _subSeason.firstMatch(name);
  return m == null ? null : int.parse(m[2]!);
}

const _wordNumbers = {
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
};

/// The season a folder name stands for: "Season 01", "S02", "1c. Season 2 (2009)", "Book Two - Earth",
/// "Ghosts.2021.S01.1080p…"; 0 for "Specials". Null when it doesn't name one.
int? seasonOfFolder(String name) {
  final n = name.toLowerCase().replaceAll(RegExp(r'[._]+'), ' ');
  if (RegExp(r'(?:^|[\s\.\-])specials?(?:$|[\s\(\-])').hasMatch(n) || n == 'season 00' || n == 's00') return 0;
  final m = RegExp(r'(?:^|[\s\-])(?:season|series)\s*(\d{1,2})(?!\d)').firstMatch(n) ??
      RegExp(r'(?:^|[\s\-])s(\d{1,2})(?![\de])').firstMatch(n) ??
      RegExp(r'(?:^|[\s\-])s(\d{1,2})$').firstMatch(n) ??
      RegExp(r'(?:^|[\s\-])book\s*(\d{1,2})(?!\d)').firstMatch(n);
  if (m != null) return int.parse(m.group(1)!);
  final w = RegExp(r'(?:^|[\s\-])(?:book|season)\s+(one|two|three|four|five|six|seven|eight|nine|ten)\b').firstMatch(n);
  if (w != null) return _wordNumbers[w.group(1)!];
  return null;
}

/// The title a season folder gives after its number: "Season 1 - Offline News" → "Offline News",
/// "Book Two - Earth" → "Earth". Null when there's none, or only a year or release details
/// ("Season 01", "1c. Season 2 (2009)", "Ghosts.2021.S01.1080p.WEB").
String? seasonTitleOfFolder(String name) {
  // "Season 1.2 - X": the sub number isn't part of the title.
  final n = name.replaceFirstMapped(_subSeason, (m) => m[1]!).replaceAll(RegExp(r'[._]'), ' ');
  final m = RegExp(
        r'(?:^|[\s\-])(?:season|series|book)\s*(?:\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten)(?![0-9a-z])',
        caseSensitive: false,
      ).firstMatch(n) ??
      RegExp(r'(?:^|[\s\-])s\d{1,2}(?![0-9a-z])', caseSensitive: false).firstMatch(n);
  if (m == null) return null;
  var rest = n
      .substring(m.end)
      .replaceFirst(RegExp(r'^\s*[\(\[]\s*(?:19|20)\d\d(?:\s*-\s*(?:19|20)?\d\d)?\s*[\)\]]'), '')
      .replaceFirst(RegExp(r'^[\s\-–—:~|]+'), '');
  if (_isOnlyJunk(rest)) return null;
  rest = cleanVideoName(rest).title;
  if (rest.isEmpty || RegExp(r'^[\d\s\-]+$').hasMatch(rest)) return null;
  if (RegExp(r'^(?:episodes?|eps?|complete)\b', caseSensitive: false).hasMatch(rest)) return null;
  return rest;
}

/// Whether a folder holds extras rather than episodes.
bool isExtrasFolder(String name) {
  final n = name.toLowerCase().replaceAll(RegExp(r'^[\d\w]{1,3}\.\s+'), '').replaceAll(RegExp(r'[._]+'), ' ');
  if (_extraWords.contains(n.trim())) return true;
  return _extraWords.any((w) => RegExp('(?:^|[\\s\\-\\(\\[])${RegExp.escape(w)}(?:\$|[\\s\\-\\)\\]])').hasMatch(n));
}

/// Season, episode and title from a file name. [film] skips the looser episode patterns.
({int? season, int? episode, String? title}) parseEpisodeName(String name, {bool film = false}) {
  var t = spacedName(name);
  t = t.replaceFirst(RegExp(r'^(?:\s*[\[\{][^\]\}]*[\]\}]\s*)+'), '');
  RegExpMatch? m;
  int? season, episode;
  String rest = '';
  if ((m = RegExp(r'(?:^|[\s\-\.\[\(])s(\d{1,2})\s?e(\d{1,3})(?:-?e\d{1,3})?(?![0-9])', caseSensitive: false).firstMatch(t)) !=
      null) {
    season = int.parse(m!.group(1)!);
    episode = int.parse(m.group(2)!);
    rest = t.substring(m.end);
  } else if ((m = RegExp(r'season\s*(\d{1,2})\s*episode\s*(\d{1,3})', caseSensitive: false).firstMatch(t)) != null) {
    season = int.parse(m!.group(1)!);
    episode = int.parse(m.group(2)!);
    rest = t.substring(m.end);
  } else if ((m = RegExp(r'(\d{1,2})x(\d{2,3})(?![0-9])').firstMatch(t)) != null && !film) {
    season = int.parse(m!.group(1)!);
    episode = int.parse(m.group(2)!);
    rest = t.substring(m.end);
  } else if (!film && (m = RegExp(r'(?:^|\s)(?:episode|ep\.?)\s*(\d{1,3})(?![0-9])', caseSensitive: false).firstMatch(t)) != null) {
    episode = int.parse(m!.group(1)!);
    rest = t.substring(m.end);
  } else if (!film && (m = RegExp(r'\s-\s(\d{1,3})(?:v\d)?(?=\s|$)').firstMatch(t)) != null) {
    episode = int.parse(m!.group(1)!);
    rest = ''; // "Toradora! - 03 v2 [1080p]": what follows is release details
  } else if (!film && (m = RegExp(r'^(.*\D)\s(\d{1,3})$').firstMatch(cleanVideoName(t).title)) != null &&
      !RegExp(r'(?:op|ed|nc|ova|part|vol|volume|chapter|#)$', caseSensitive: false).hasMatch(m!.group(1)!.trim())) {
    // "Fullmetal Alchemist BrotherHood 16", "Black Rock Shooter 01".
    episode = int.parse(m.group(2)!);
    rest = '';
  } else if (!film && (m = RegExp(r'^(\d{1,3})\s*[-.)]?\s+(\D.*)$').firstMatch(t)) != null) {
    // "01 Pilot", "03 - Lanterns".
    episode = int.parse(m!.group(1)!);
    rest = m.group(2)!;
  } else {
    return (season: null, episode: null, title: null);
  }
  var title = rest.replaceFirst(RegExp(r'^[\s\-–:.]+'), '');
  title = _isOnlyJunk(title) ? '' : cleanVideoName(title).title;
  if (title.isEmpty || RegExp(r'^[\s\-]*$').hasMatch(title)) return (season: season, episode: episode, title: null);
  return (season: season, episode: episode, title: title);
}

/// Works out a video's collection, category, season, episode and title from where it is
/// under the video folder [root].
VideoPathInfo describeVideoPath(String root, String path) {
  final rel = p.split(p.relative(path, from: root));
  final dirs = rel.sublist(0, rel.length - 1);
  final fileName = p.basenameWithoutExtension(path);
  String? category;
  var rest = dirs;
  if (dirs.isNotEmpty && videoCategoryNames.contains(dirs.first.toLowerCase().trim())) {
    category = dirs.first;
    rest = dirs.sublist(1);
  } else if (videoCategoryNames.contains(p.basename(root).toLowerCase().trim())) {
    category = p.basename(root);
  }
  final film = category != null && _filmCategories.contains(category.toLowerCase().trim());
  final fromName = cleanVideoName(fileName);

  // Loose in the video folder or a category folder.
  if (rest.isEmpty) {
    if (category != null) {
      // A film (or a clip) on its own: its own collection.
      final ep = film ? null : parseEpisodeName(fileName);
      return VideoPathInfo(
        collection: fromName.title,
        collectionFolder: p.dirname(path),
        category: category,
        title: ep?.title ?? fromName.title,
        season: ep?.season,
        episode: ep?.episode,
        year: fromName.year,
      );
    }
    final ep = parseEpisodeName(fileName);
    return VideoPathInfo(
      collection: cleanVideoName(p.basename(root)).title,
      collectionFolder: root,
      title: ep.title ?? (ep.episode != null ? 'Episode ${ep.episode}' : fromName.title),
      season: ep.season,
      episode: ep.episode,
      year: fromName.year,
    );
  }

  // The video folder is itself one show ("…\Silo" holding "Season 1", "Season 2"): its first
  // folders are seasons, not collections, so the collection is the video folder.
  final seasonOnly = category == null &&
      seasonOfFolder(rest.first) != null &&
      (RegExp(r'^(?:season|series|s|book|specials?)\s*\d*(?:\.\d{1,2})?$', caseSensitive: false)
              .hasMatch(cleanVideoName(rest.first).title) ||
          // "Season 1 - Offline News": a season with its own title.
          RegExp(r'^(?:season|series)\s*\d{1,2}(?:\.\d{1,2})?\s*[-:–—]', caseSensitive: false).hasMatch(rest.first.trim()));
  final collectionFolder = seasonOnly
      ? root
      : p.joinAll([root, if (category != null && dirs.isNotEmpty && dirs.first == category) category, rest.first]);
  final named = cleanVideoName(seasonOnly ? p.basename(root) : rest.first);
  final inner = seasonOnly ? rest : rest.sublist(1);
  final extra = inner.any(isExtrasFolder);
  int? folderSeason;
  String? folderSeasonTitle;
  int? folderSubSeason;
  String? part;
  for (final d in inner) {
    if (isExtrasFolder(d)) continue;
    final s = seasonOfFolder(d);
    if (s != null) {
      folderSeason = s;
      folderSeasonTitle = s == 0 ? null : seasonTitleOfFolder(d);
      folderSubSeason = s == 0 ? null : subSeasonOfFolder(d);
    } else {
      var name = cleanVideoName(d.replaceFirst(RegExp(r'^\w{1,3}\.\s+'), '')).title;
      // "Sword Art Online - Alicization" in "Sword Art Online": just "Alicization".
      final prefix = RegExp('^${RegExp.escape(named.title)}\\s*[-:\u2013]\\s*', caseSensitive: false);
      name = name.replaceFirst(prefix, '');
      part = name.toLowerCase() == named.title.toLowerCase() ? null : name;
    }
  }
  final ep = film ? parseEpisodeName(fileName, film: true) : parseEpisodeName(fileName);
  final season = extra ? null : (ep.season ?? folderSeason);
  final episode = extra ? null : ep.episode;
  final title = ep.title ??
      (episode != null && !extra ? 'Episode $episode' : fromName.title);
  return VideoPathInfo(
    collection: named.title,
    collectionFolder: collectionFolder,
    category: category,
    season: season,
    episode: episode,
    title: title,
    year: named.year ?? fromName.year,
    extra: extra,
    part: season == null && !extra ? part : null,
    seasonTitle: season != null && season == folderSeason ? folderSeasonTitle : null,
    subSeason: season != null && season == folderSeason ? folderSubSeason : null,
  );
}

/// Subtitle files HomeTunes adds as choices when a video plays.
const subtitleExtensions = {'.srt', '.ass', '.ssa', '.vtt', '.sub'};

/// A readable name for an external subtitle file: "3_English.srt" → "English",
/// "Film.en.forced.srt" (for video "Film") → "en forced".
String subtitleLabel(String subtitlePath, String videoPath) {
  var n = p.basenameWithoutExtension(subtitlePath);
  final video = p.basenameWithoutExtension(videoPath);
  if (n.toLowerCase().startsWith(video.toLowerCase())) n = n.substring(video.length);
  n = n.replaceAll(RegExp(r'^[\s._\-\d]+'), '').replaceAll(RegExp(r'[._]+'), ' ').trim();
  return n.isEmpty ? 'External' : n;
}
