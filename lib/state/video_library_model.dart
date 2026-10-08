// Videos (0.1.40): the Videos tab's live data.
//
// Owns videos.json: the videos found in the video folders (VideoItem), the user's edits to their
// details (VideoEdit) and how far into each one they got (VideoPlace). The folders themselves
// are a setting in LibraryModel (videoFolders, in settings.json, shown on Settings › Folders &
// scanning); this model listens to LibraryModel and scans when a folder is added, and drops a
// removed folder's videos straight away. After each scan it makes the missing thumbnails in the
// background (services/video_thumbnails.dart), one video at a time.
// Like LibraryModel, a folder that can't be reached (unplugged drive) keeps its videos as they were.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/video_item.dart';
import '../services/music_permission.dart';
import '../services/path_safety.dart';
import '../services/storage.dart';
import '../services/video_names.dart' show describeVideoPath, videoCategoryNames;
import '../services/video_nfo.dart';
import '../services/video_scanner.dart';
import '../services/video_thumbnails.dart';
import 'book_index.dart' show isInside;
import 'library_model.dart';
import 'media_folders.dart';
import 'video_filters.dart';

class VideoLibraryModel extends ChangeNotifier {
  final Storage storage;
  final LibraryModel library;

  /// The data file this model owns.
  static const fileName = 'videos.json';

  /// Makes thumbnails after a scan. Null (no thumbnails) unless main.dart sets one: tests have
  /// no video engine.
  VideoThumbnailer? thumbnailer;

  /// Whether video files may be read (Android's "Photos and videos"). Replaceable for tests.
  Future<MusicAccess> Function() checkAccess = MusicPermission.checkVideos;

  /// Whether a folder can be listed right now. Replaceable for tests.
  Future<bool> Function(String folder) folderReachable = canListFolder;

  final VideoScanner _scanner = VideoScanner();

  VideoLibraryModel(this.storage, this.library) {
    _knownFolders = List.of(library.videoFolders);
    _knownHidden = _hiddenKey();
    library.addListener(_onLibraryChanged);
  }

  // What the scan found (the files' own details), the user's edits and places, by video id.
  List<VideoItem> _scanned = [];
  Map<String, VideoEdit> _edits = {};
  Map<String, VideoPlace> _places = {};

  /// Every video with the user's edits laid over it, A–Z by title.
  List<VideoItem> videos = const [];
  Map<String, VideoItem> _byId = {};
  Map<String, VideoItem> _rawById = {};

  /// A scan is running.
  bool busy = false;

  /// What's happening now ("Looking for videos…"), or null.
  String? status;

  /// Why the last scan couldn't finish, or null.
  String? error;

  /// Video folders that couldn't be reached at the last scan; their videos are kept.
  List<String> offlineFolders = [];

  late List<String> _knownFolders;

  // ---- reading ----

  VideoItem? byId(String id) => _byId[id];

  /// The video as the file has it, before the user's edits (the editor shows these).
  VideoItem? rawById(String id) => _rawById[id];

  VideoEdit? editOf(String id) => _edits[id];
  VideoPlace? placeOf(String id) => _places[id];
  Map<String, VideoPlace> get places => Map.unmodifiable(_places);

  /// Started and not finished, most recently watched first.
  List<VideoItem> get continueWatching {
    final list = [for (final v in videos) if (_places[v.id]?.inProgress ?? false) v];
    list.sort((a, b) => _places[b.id]!.updatedMs.compareTo(_places[a.id]!.updatedMs));
    return list;
  }

  /// Every collection name, A–Z (for the editor's suggestions).
  List<String> get collectionNames => [for (final c in collections) c.name];

  /// The collections (like albums), A–Z by name, each with its videos in watching order.
  List<VideoCollection> collections = const [];
  Map<String, VideoCollection> _collectionByKey = {};

  /// The collection called [name] (any case).
  VideoCollection? collectionNamed(String name) => _collectionByKey[VideoCollection.keyFor(name)];

  /// The collection a video is in.
  VideoCollection? collectionOf(VideoItem v) => collectionNamed(v.collection);

  // Favourite collections, descriptions the user wrote for collections, and the audio /
  // subtitle choice last made in each, all by collection key (lower-case name).
  Set<String> _favourites = {};
  Map<String, String> _descriptions = {};
  Map<String, ({TrackPick? audio, TrackPick? subtitles})> _trackChoices = {};

  bool isFavourite(VideoCollection c) => _favourites.contains(c.key);

  /// Favourite collections, A–Z.
  List<VideoCollection> get favouriteCollections => [for (final c in collections) if (_favourites.contains(c.key)) c];

  Future<void> setFavourite(VideoCollection c, bool favourite) async {
    favourite ? _favourites.add(c.key) : _favourites.remove(c.key);
    notifyListeners();
    await _save();
  }

  /// The audio and subtitle choice to start [collection]'s videos with (null: the file's own).
  ({TrackPick? audio, TrackPick? subtitles}) trackChoiceFor(String collection) =>
      _trackChoices[VideoCollection.keyFor(collection)] ?? (audio: null, subtitles: null);

  /// Remembers an audio or subtitle choice for the rest of [collection] (e.g. English audio for
  /// every episode of a dual-audio series).
  void rememberTrackChoice(String collection, {TrackPick? audio, TrackPick? subtitles}) {
    final key = VideoCollection.keyFor(collection);
    final old = _trackChoices[key];
    _trackChoices[key] = (audio: audio ?? old?.audio, subtitles: subtitles ?? old?.subtitles);
    _saveSoon();
  }

  /// The next thing to watch in [c]: one in progress, else the first not watched after the last
  /// one watched, else the first not watched, else the first. Extras only if there's nothing else.
  VideoItem? nextUp(VideoCollection c) {
    // Not seasons marked special (0.1.66), unless there's nothing else.
    final regular = [for (final v in c.main) if (v.specialTitle == null) v];
    final list = regular.isNotEmpty ? regular : (c.main.isEmpty ? c.videos : c.main);
    if (list.isEmpty) return null;
    for (final v in list) {
      if (_places[v.id]?.inProgress ?? false) return v;
    }
    var lastWatched = -1;
    for (var i = 0; i < list.length; i++) {
      if (_places[list[i].id]?.watched ?? false) lastWatched = i;
    }
    for (var i = lastWatched + 1; i < list.length; i++) {
      if (!(_places[list[i].id]?.watched ?? false)) return list[i];
    }
    for (final v in list) {
      if (!(_places[v.id]?.watched ?? false)) return v;
    }
    return list.first;
  }

  /// The video after [v] in its collection (for playing on), or null at the end.
  VideoItem? after(VideoItem v) {
    final c = collectionOf(v);
    if (c == null) return null;
    final i = c.videos.indexWhere((x) => x.id == v.id);
    if (i < 0 || i + 1 >= c.videos.length) return null;
    final next = c.videos[i + 1];
    // Don't run on from the last episode into the extras, or into a season marked special
    // (0.1.66); within the specials it plays on.
    if (next.extra && !v.extra) return null;
    if (next.specialTitle != null && v.specialTitle == null) return null;
    return next;
  }

  /// The video before [v] in its collection (the previous-video button), or null at the start.
  /// From an extra it goes back through the extras, then to the last episode.
  VideoItem? before(VideoItem v) {
    final c = collectionOf(v);
    if (c == null) return null;
    final i = c.videos.indexWhere((x) => x.id == v.id);
    return i <= 0 ? null : c.videos[i - 1];
  }

  /// How many of [c]'s episodes (not extras) are watched.
  int watchedCount(VideoCollection c) => c.main.where((v) => _places[v.id]?.watched ?? false).length;

  /// The last time anything in [c] was watched (ms), or 0.
  int lastWatchedMs(VideoCollection c) =>
      c.videos.fold<int>(0, (m, v) => (_places[v.id]?.updatedMs ?? 0) > m ? _places[v.id]!.updatedMs : m);

  /// The collection's picture: the one the user chose, its poster, else its first video's
  /// thumbnail.
  String? coverFile(VideoCollection c) {
    final own = _ownPicture(_posters[c.key]);
    if (own != null) return own;
    final cover = c.cover;
    if (cover != null && library.videoFolders.any((f) => isInsideAny(cover, [f]))) return cover;
    for (final v in c.main.isEmpty ? c.videos : c.main) {
      final t = thumbFile(v);
      if (t != null) return t;
    }
    return null;
  }

  /// Edits a whole collection, like editing an album: a new name, year, genre or category is
  /// saved as an edit on every video in it; the description is the collection's own. Renaming
  /// keeps its favourite, description and track choices.
  Future<void> editCollection(
    VideoCollection c, {
    String? name,
    int? year,
    bool clearYear = false,
    String? genre,
    bool clearGenre = false,
    String? category,
    bool clearCategory = false,
    String? description,
  }) async {
    final newName = name?.trim();
    for (final v in c.videos) {
      final raw = _rawById[v.id] ?? v;
      final old = _edits[v.id] ?? const VideoEdit();
      var edit = old.merge(
        year: year,
        genre: genre,
        category: category,
        clear: {if (clearYear) 'year', if (clearGenre) 'genre', if (clearCategory) 'category'},
      );
      if (newName != null && newName.isNotEmpty) {
        edit = VideoEdit(
          title: edit.title,
          collection: newName == raw.collection ? null : newName,
          category: edit.category,
          season: edit.season,
          episode: edit.episode,
          subSeason: edit.subSeason,
          year: edit.year,
          genre: edit.genre,
          description: edit.description,
          cleared: edit.cleared,
        );
      }
      if (edit.isEmpty) {
        _edits.remove(v.id);
      } else {
        _edits[v.id] = edit;
      }
    }
    final oldKey = c.key;
    final newKey = newName == null || newName.isEmpty ? oldKey : VideoCollection.keyFor(newName);
    if (description != null) {
      description.trim().isEmpty ? _descriptions.remove(oldKey) : _descriptions[oldKey] = description.trim();
    }
    if (newKey != oldKey) {
      if (_favourites.remove(oldKey)) _favourites.add(newKey);
      final d = _descriptions.remove(oldKey);
      if (d != null) _descriptions[newKey] = d;
      final t = _trackChoices.remove(oldKey);
      if (t != null) _trackChoices[newKey] = t;
      final poster = _posters.remove(oldKey);
      if (poster != null) _posters[newKey] = poster;
      final shape = _collectionShapes.remove(oldKey);
      if (shape != null) _collectionShapes[newKey] = shape;
      final speed = _speeds.remove(oldKey);
      if (speed != null) _speeds[newKey] = speed;
      final titles = _seasonTitles.remove(oldKey);
      if (titles != null) _seasonTitles[newKey] = titles;
      final specials = _specialSeasons.remove(oldKey);
      if (specials != null) _specialSeasons[newKey] = specials;
    }
    _rebuild();
    await _save();
  }

  /// The file to play, if it's still there and inside a video folder (a restored backup could
  /// name any path; 0.1.21 security review #3).
  String? playableFile(VideoItem v) =>
      isUsableLocalFile(v.path, roots: library.videoFolders, extensions: videoFileExtensions) ? v.path : null;

  // ---- .nfo files (services/video_nfo.dart) ----

  /// Whether the editors also save the details into .nfo files beside the videos (remembered;
  /// on unless the user turned it off). Not offered on Android, which can't write there.
  bool saveNfo = true;

  Future<void> setSaveNfo(bool on) async {
    if (saveNfo == on) return;
    saveNfo = on;
    notifyListeners();
    await _save();
  }

  /// Writes the details of [items] (as edited) into `<video>.nfo` beside each one, and a
  /// tvshow.nfo into the folder of each series they belong to. Only files inside the video
  /// folders are touched. Returns how many were written and what went wrong.
  Future<({int written, List<String> errors})> saveNfoFiles(Iterable<VideoItem> items) async {
    final roots = library.videoFolders;
    final jobs = <NfoJob>[];
    final touched = <String, VideoCollection>{};
    for (final item in items) {
      final v = _byId[item.id] ?? item;
      if (playableFile(v) == null) continue;
      final c = collectionOf(v);
      final series = c != null && c.videos.any((x) => x.season != null || x.episode != null);
      jobs.add(NfoJob(
        nfoPathFor(v.path),
        series ? 'episodedetails' : 'movie',
        {
          'title': v.title,
          if (series) 'showtitle': v.collection,
          if (series) 'season': v.season?.toString(),
          if (series) 'episode': v.episode?.toString(),
          // A film on its own is its own collection: no set then.
          if (!series) 'set': (c != null && c.videos.length > 1) || v.collection != v.title ? v.collection : null,
          'year': v.year?.toString(),
          'genre': v.genre,
          'plot': v.description,
        },
      ));
      if (series) touched[c.key] = c;
    }
    for (final c in touched.values) {
      final folder = _seriesFolder(c, roots);
      if (folder == null) continue;
      jobs.add(NfoJob(p.join(folder, showNfoName), 'tvshow', {
        'title': c.name,
        'year': c.year?.toString(),
        'genre': c.genre,
        'plot': c.description,
      }));
    }
    if (jobs.isEmpty) return (written: 0, errors: const <String>[]);
    final errors = await writeNfoFilesInBackground(jobs);
    return (written: jobs.length - errors.length, errors: errors);
  }

  /// The folder a series lives in (where its tvshow.nfo goes): the folder its name comes from,
  /// if every video in it is inside that folder, it isn't a category folder ("TV", "Films") and
  /// it isn't a video folder with other things loose in it. Null otherwise.
  String? _seriesFolder(VideoCollection c, List<String> roots) {
    String? folder;
    for (final v in c.videos) {
      final root = roots.where((r) => isInside(v.path, r)).firstOrNull;
      if (root == null) return null;
      final f = describeVideoPath(root, v.path).collectionFolder;
      if (folder != null && !p.equals(folder, f)) return null;
      folder = f;
      // Loose in a video folder: that folder holds other things too.
      if (roots.any((r) => p.equals(r, p.dirname(v.path)) && p.equals(r, f)) && v.season == null) return null;
    }
    if (folder == null || videoCategoryNames.contains(p.basename(folder).toLowerCase().trim())) return null;
    return folder;
  }

  /// The video's picture: the one the user chose, else its thumbnail (if it's inside the app's
  /// own art folder).
  String? thumbFile(VideoItem v) {
    final own = _ownPicture(_pictures[v.id]);
    if (own != null) return own;
    final t = v.thumb;
    return t != null && isInsideAny(t, [storage.artDir]) ? t : null;
  }

  // ---- picture shapes and speeds (Settings › Videos sets the usual ones) ----

  // A video's own picture shape (by id), a collection's own (by key), and each collection's
  // playing speed (by key).
  Map<String, PictureShape> _shapes = {};
  Map<String, PictureShape> _collectionShapes = {};
  Map<String, double> _speeds = {};

  /// The shape of [v]'s picture: its own, else the usual one.
  PictureShape shapeOf(VideoItem v) => _shapes[v.id] ?? library.videoPictureShape;

  /// [v]'s own shape, or null when it uses the usual one.
  PictureShape? ownShapeOf(VideoItem v) => _shapes[v.id];

  PictureShape collectionShapeOf(VideoCollection c) => _collectionShapes[c.key] ?? library.collectionPictureShape;
  PictureShape? ownCollectionShapeOf(VideoCollection c) => _collectionShapes[c.key];

  /// Gives videos [ids] their own picture shape, or with null the usual one.
  Future<void> setShapes(Iterable<String> ids, PictureShape? shape) async {
    for (final id in ids) {
      shape == null ? _shapes.remove(id) : _shapes[id] = shape;
    }
    notifyListeners();
    await _save();
  }

  Future<void> setCollectionShape(VideoCollection c, PictureShape? shape) async {
    shape == null ? _collectionShapes.remove(c.key) : _collectionShapes[c.key] = shape;
    notifyListeners();
    await _save();
  }

  // ---- season titles ("Season 1 - Offline News") ----

  // Titles the user gave seasons, by collection key then season ("1", or "1.2" for a sub
  // number; "" = no title, on purpose).
  Map<String, Map<String, String>> _seasonTitles = {};

  bool _inSeason(VideoItem v, int season, int? sub) => v.season == season && v.subSeason == sub;

  /// The title shown after "Season n" (or "Season n.[sub]"): the user's own, else what the
  /// season folder or the series' tvshow.nfo says (the most common among its videos). Null when
  /// there's none.
  String? seasonTitleOf(VideoCollection c, int season, [int? sub]) {
    final own = _seasonTitles[c.key]?[seasonText(season, sub)];
    if (own != null) return own.isEmpty ? null : own;
    return mostCommon([for (final v in c.videos) if (_inSeason(v, season, sub)) v.seasonTitle]);
  }

  /// The title the season's folder name gives ("Season 1 - Offline News" → "Offline News"),
  /// ignoring the user's own and any .nfo.
  String? folderSeasonTitle(VideoCollection c, int season, [int? sub]) {
    final roots = library.videoFolders;
    return mostCommon([
      for (final v in c.videos)
        if (_inSeason(v, season, sub))
          if (roots.where((r) => isInside(v.path, r)).firstOrNull case final root?)
            describeVideoPath(root, v.path).seasonTitle,
    ]);
  }

  /// Whether the user gave the season its own title (or cleared it).
  bool hasOwnSeasonTitle(VideoCollection c, int season, [int? sub]) =>
      _seasonTitles[c.key]?.containsKey(seasonText(season, sub)) ?? false;

  /// Gives a season its own title; '' shows none, null goes back to what the files say. With
  /// [writeNfo], the series' tvshow.nfo gets it too (`<namedseason>`; none removes it), so it
  /// survives a new install and other programs see it — whole seasons only, as .nfo files have
  /// no sub numbers. Returns what went wrong writing.
  Future<List<String>> setSeasonTitle(VideoCollection c, int season, String? title,
      {int? sub, bool writeNfo = false}) async {
    final t = title?.trim();
    final key = seasonText(season, sub);
    if (t == null) {
      _seasonTitles[c.key]?.remove(key);
      if (_seasonTitles[c.key]?.isEmpty ?? false) _seasonTitles.remove(c.key);
    } else {
      (_seasonTitles[c.key] ??= {})[key] = t;
    }
    notifyListeners();
    await _save();
    if (!writeNfo || sub != null) return const [];
    final folder = _seriesFolder(c, library.videoFolders);
    if (folder == null) return const [];
    return writeNfoFilesInBackground([
      NfoJob(p.join(folder, showNfoName), 'tvshow', {namedSeasonKey(season): t}),
    ]);
  }

  // ---- special seasons (0.1.66) ----

  // Seasons the user marked special, by collection key then season ("3", "1.2"), with the
  // title they chose ("OVA"). Kept in videos.json as specialSeasons.
  Map<String, Map<String, String>> _specialSeasons = {};

  /// The special title of a season, or null when it's a normal season.
  String? specialTitleOf(VideoCollection c, int season, [int? sub]) =>
      _specialSeasons[c.key]?[seasonText(season, sub)];

  /// Marks a season special with [title] (from Settings › Videos › Special season titles, or
  /// typed), or back to a normal season with null. Season 0 is already "Specials".
  Future<void> setSpecialSeason(VideoCollection c, int season, String? title, {int? sub}) async {
    final t = title?.trim();
    final key = seasonText(season, sub);
    if (t == null || t.isEmpty) {
      _specialSeasons[c.key]?.remove(key);
      if (_specialSeasons[c.key]?.isEmpty ?? false) _specialSeasons.remove(c.key);
    } else {
      (_specialSeasons[c.key] ??= {})[key] = t;
    }
    _rebuild();
    await _save();
  }

  /// Whether a group on a collection's page is a season the user marked special (for its badge).
  static bool isSpecialGroup(List<VideoItem> list) => list.firstOrNull?.specialTitle != null;

  /// Heading text for a group on a collection's page: "Season 1 – Offline News",
  /// "Season 1.2 – Outside".
  String groupLabel(VideoCollection c, String heading, List<VideoItem> list) {
    final first = list.firstOrNull;
    final season = first?.season;
    if (first == null || season == null || season == 0 || heading != 'Season ${first.seasonLabel}') return heading;
    final title = seasonTitleOf(c, season, first.subSeason);
    return title == null ? heading : '$heading – $title';
  }

  /// The speed videos in [collection] play at: the last one chosen there, else the usual one.
  double speedFor(String collection) => _speeds[VideoCollection.keyFor(collection)] ?? library.defaultVideoSpeed;

  void rememberSpeed(String collection, double speed) {
    final key = VideoCollection.keyFor(collection);
    if (_speeds[key] == speed) return;
    _speeds[key] = speed;
    _saveSoon();
  }

  // ---- pictures the user chose (Change picture… / Change poster…) ----

  // By video id, and by collection key: files in art/video/custom/.
  Map<String, String> _pictures = {};
  Map<String, String> _posters = {};

  /// Where chosen pictures are kept (inside the thumbnail folder, whose tidy-up only looks at
  /// its own files, not sub-folders).
  String get customPictureDir => p.join(thumbDir, 'custom');

  String? _ownPicture(String? path) => path != null && isInsideAny(path, [storage.artDir]) ? path : null;

  bool hasOwnPicture(VideoItem v) => _pictures.containsKey(v.id);
  bool hasOwnPoster(VideoCollection c) => _posters.containsKey(c.key);

  /// Whether the user wrote [c]'s description (Edit collection), rather than its tvshow.nfo.
  bool hasOwnDescription(VideoCollection c) => _descriptions.containsKey(c.key);

  /// Gives [v] the picture [bytes] (a JPEG or PNG, already made a sensible size), or with null
  /// goes back to the automatic one.
  Future<void> setPicture(VideoItem v, List<int>? bytes) async {
    if (bytes == null) {
      _pictures.remove(v.id);
    } else {
      _pictures[v.id] = await _keep(bytes);
    }
    await _afterPictureChange();
  }

  /// Gives collection [c] the poster [bytes], or with null goes back to the automatic one.
  Future<void> setPoster(VideoCollection c, List<int>? bytes) async {
    if (bytes == null) {
      _posters.remove(c.key);
    } else {
      _posters[c.key] = await _keep(bytes);
    }
    await _afterPictureChange();
  }

  /// Saves a chosen picture under a name made from its contents (so the same one is kept once,
  /// and a changed picture never shows an old cached copy).
  Future<String> _keep(List<int> bytes) async {
    final png = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final dir = Directory(customPictureDir);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${md5.convert(bytes)}${png ? '.png' : '.jpg'}'));
    if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _afterPictureChange() async {
    notifyListeners();
    await _save();
    // Pictures no longer used by anything go.
    final dir = Directory(customPictureDir);
    if (!await dir.exists()) return;
    final used = {for (final f in [..._pictures.values, ..._posters.values]) p.normalize(f)};
    await for (final e in dir.list()) {
      if (e is File && !used.contains(p.normalize(e.path))) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  }

  // ---- loading and saving ----

  Future<void> load() async {
    final j = await storage.read(fileName);
    if (j is! Map) return;
    var damaged = false;
    final scanned = <VideoItem>[];
    for (final v in (j['videos'] is List ? j['videos'] as List : const [])) {
      try {
        scanned.add(VideoItem.fromJson(Map<String, dynamic>.from(v as Map)));
      } catch (_) {
        damaged = true;
      }
    }
    final edits = <String, VideoEdit>{};
    final e = j['edits'];
    if (e is Map) {
      for (final entry in e.entries) {
        try {
          edits[entry.key as String] = VideoEdit.fromJson(Map<String, dynamic>.from(entry.value as Map));
        } catch (_) {
          damaged = true;
        }
      }
    }
    final places = <String, VideoPlace>{};
    final pl = j['places'];
    if (pl is Map) {
      for (final entry in pl.entries) {
        try {
          places[entry.key as String] = VideoPlace.fromJson(Map<String, dynamic>.from(entry.value as Map));
        } catch (_) {
          damaged = true;
        }
      }
    }
    // Collections: favourites, descriptions, audio / subtitle choices.
    final favourites = <String>{};
    final descriptions = <String, String>{};
    final choices = <String, ({TrackPick? audio, TrackPick? subtitles})>{};
    try {
      favourites.addAll((j['favourites'] as List? ?? const []).cast<String>());
      final d = j['descriptions'];
      if (d is Map) descriptions.addAll(d.cast<String, String>());
      final t = j['trackChoices'];
      if (t is Map) {
        for (final e in t.entries) {
          final m = e.value as Map;
          TrackPick? pick(String k) => m[k] is Map ? TrackPick.fromJson(Map<String, dynamic>.from(m[k] as Map)) : null;
          choices[e.key as String] = (audio: pick('audio'), subtitles: pick('subtitles'));
        }
      }
    } catch (_) {
      damaged = true;
    }
    if (damaged) await storage.keepCopy(fileName);
    _scanned = scanned;
    _edits = edits;
    _places = places;
    _favourites = favourites;
    _descriptions = descriptions;
    _trackChoices = choices;
    saveNfo = j['saveNfo'] != false;
    Map<String, String> strings(Object? m) =>
        m is Map ? {for (final e in m.entries) if (e.key is String && e.value is String) e.key as String: e.value as String} : {};
    _pictures = strings(j['pictures']);
    _posters = strings(j['posters']);
    Map<String, PictureShape> shapes(Object? m) => {
          for (final e in strings(m).entries)
            if (PictureShape.byName(e.value) != null) e.key: PictureShape.byName(e.value)!
        };
    _shapes = shapes(j['shapes']);
    _collectionShapes = shapes(j['collectionShapes']);
    final sp = j['speeds'];
    _speeds = sp is Map
        ? {
            for (final e in sp.entries)
              if (e.key is String && e.value is num && (e.value as num) > 0 && (e.value as num) <= 4)
                e.key as String: (e.value as num).toDouble()
          }
        : {};
    // Season titles: {"silo": {"1": "Offline News", "1.2": "Outside"}}.
    final st = j['seasonTitles'];
    final seasonKey = RegExp(r'^\d{1,3}(\.\d{1,3})?$');
    _seasonTitles = {
      if (st is Map)
        for (final e in st.entries)
          if (e.key is String && e.value is Map)
            e.key as String: {
              for (final s in (e.value as Map).entries)
                if (s.key is String && seasonKey.hasMatch(s.key as String) && s.value is String)
                  s.key as String: s.value as String,
            },
    }..removeWhere((_, v) => v.isEmpty);
    // Special seasons (0.1.66): {"silo": {"3": "OVA"}}.
    final sp2 = j['specialSeasons'];
    _specialSeasons = {
      if (sp2 is Map)
        for (final e in sp2.entries)
          if (e.key is String && e.value is Map)
            e.key as String: {
              for (final s in (e.value as Map).entries)
                if (s.key is String &&
                    seasonKey.hasMatch(s.key as String) &&
                    s.value is String &&
                    (s.value as String).trim().isNotEmpty)
                  s.key as String: (s.value as String).trim(),
            },
    }..removeWhere((_, v) => v.isEmpty);
    _rebuild();
  }

  Timer? _saveTimer;

  Future<bool> _save() {
    _saveTimer?.cancel();
    _saveTimer = null;
    return storage.write(fileName, {
      'videos': [for (final v in _scanned) v.toJson()],
      'edits': {for (final e in _edits.entries) e.key: e.value.toJson()},
      'places': {for (final e in _places.entries) e.key: e.value.toJson()},
      if (!saveNfo) 'saveNfo': false,
      if (_pictures.isNotEmpty) 'pictures': _pictures,
      if (_posters.isNotEmpty) 'posters': _posters,
      if (_shapes.isNotEmpty) 'shapes': {for (final e in _shapes.entries) e.key: e.value.name},
      if (_collectionShapes.isNotEmpty) 'collectionShapes': {for (final e in _collectionShapes.entries) e.key: e.value.name},
      if (_speeds.isNotEmpty) 'speeds': _speeds,
      if (_seasonTitles.isNotEmpty)
        'seasonTitles': {
          for (final e in _seasonTitles.entries) e.key: {for (final s in e.value.entries) s.key: s.value},
        },
      if (_specialSeasons.isNotEmpty)
        'specialSeasons': {
          for (final e in _specialSeasons.entries) e.key: {for (final s in e.value.entries) s.key: s.value},
        },
      if (_favourites.isNotEmpty) 'favourites': _favourites.toList()..sort(),
      if (_descriptions.isNotEmpty) 'descriptions': _descriptions,
      if (_trackChoices.isNotEmpty)
        'trackChoices': {
          for (final e in _trackChoices.entries)
            e.key: {
              if (e.value.audio != null) 'audio': e.value.audio!.toJson(),
              if (e.value.subtitles != null) 'subtitles': e.value.subtitles!.toJson(),
            }
        },
    });
  }

  /// Saves a couple of seconds from now (places change often while a video plays).
  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _save);
  }

  /// Saves anything waiting now (the app is going into the background or closing).
  Future<void> flushPendingSaves() async {
    if (_saveTimer != null) await _save();
  }

  // ---- one folder's options (Settings › Folders & scanning › Folder options) ----

  /// The video folder whose options apply to [path]: the innermost one holding it (the most
  /// folders deep, counted the same way as LibraryModel.ownerFolder; refactor phase 1: it
  /// compared the paths' text length before).
  String? ownerFolder(String path) => owningFolder(path, library.videoFolders);

  /// Left out by its folder's File types (switched off types are kept in LibraryModel's
  /// hiddenFormats, the same setting the music and audiobook folders use).
  bool _formatHidden(VideoItem v) {
    final owner = ownerFolder(v.path);
    return owner != null && !library.formatShown(owner, LibraryModel.formatOf(v.path));
  }

  /// The file types found in [folder] at the last scan (switched off ones included), with how
  /// many videos of each, A–Z.
  Map<String, int> formatsIn(String folder) =>
      formatCounts([for (final v in _scanned) v.path], folder, library.videoFolders);

  /// The switched-off types of the video folders, to notice a change.
  String _hiddenKey() => [for (final f in library.videoFolders) '$f=${library.hiddenFormats[f]?.join(',')}'].join('|');
  String _knownHidden = '';

  /// Rescans just [folder] (its options window). Videos elsewhere are left as they are.
  Future<void> scanFolder(String folder) {
    final next = _jobs.then((_) => _scanOne(folder));
    _jobs = next.catchError((_) {});
    return next;
  }

  Future<void> _scanOne(String folder) async {
    if (await checkAccess() != MusicAccess.allowed) {
      error = 'HomeTunes needs "Photos and videos" access to list your videos.';
      notifyListeners();
      return;
    }
    if (!await folderReachable(folder)) {
      error = 'Can\'t reach $folder right now, so the videos found there before are kept.';
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    status = 'Looking for videos in ${p.basename(folder)}…';
    notifyListeners();
    try {
      final previous = {for (final v in _scanned) v.id: v};
      final found = await _scanner.scan([folder], previous: previous);
      final foundIds = {for (final v in found) v.id};
      // Everything outside the folder stays; everything inside comes from this scan.
      _scanned = [
        for (final v in _scanned)
          if (!foundIds.contains(v.id) && !isInside(v.path, folder)) v,
        ...found,
      ];
      offlineFolders = [for (final f in offlineFolders) if (f != folder) f];
      final ids = {for (final v in _scanned) v.id};
      _places.removeWhere((id, _) => !ids.contains(id));
      _edits.removeWhere((id, _) => !ids.contains(id));
      await _save();
    } catch (e) {
      error = 'Video scan failed: $e';
    } finally {
      busy = false;
      status = null;
      _rebuild();
    }
    unawaited(makeThumbnails());
  }

  void _rebuild() {
    _rawById = {for (final v in _scanned) v.id: v};
    final all = [for (final v in _scanned) if (!_formatHidden(v)) _edits[v.id]?.applyTo(v) ?? v]
      ..sort((a, b) {
        final t = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return t != 0 ? t : a.path.compareTo(b.path);
      });
    videos = all;
    _byId = {for (final v in all) v.id: v};
    // Collections, like albums: the videos grouped by collection name (any case).
    final groups = <String, List<VideoItem>>{};
    for (final v in all) {
      (groups[VideoCollection.keyFor(v.collection)] ??= []).add(v);
    }
    // Seasons marked special (0.1.66): their videos carry the title, which decides their
    // heading and place (after the normal seasons) and keeps Up next off them.
    if (_specialSeasons.isNotEmpty) {
      for (final e in groups.entries) {
        final marks = _specialSeasons[e.key];
        if (marks == null) continue;
        e.value.setAll(0, [
          for (final v in e.value)
            v.season == null || v.season == 0 || v.extra ? v : v.withSpecial(marks[seasonText(v.season!, v.subSeason)]),
        ]);
      }
      final marked = {for (final l in groups.values) for (final v in l) v.id: v};
      videos = [for (final v in all) marked[v.id] ?? v];
      _byId = {for (final v in videos) v.id: v};
    }
    final built = <VideoCollection>[];
    for (final e in groups.entries) {
      final list = sortForCollection(e.value);
      final years = [for (final v in list) if (v.year != null) v.year!];
      built.add(VideoCollection(
        name: mostCommon(list.map((v) => v.collection))!,
        videos: list,
        category: mostCommon(list.map((v) => v.category)),
        year: years.isEmpty ? null : years.reduce((a, b) => a < b ? a : b),
        genre: mostCommon(list.map((v) => v.genre)),
        // The user's own description, else the series' tvshow.nfo one.
        description: _descriptions[e.key] ?? mostCommon(list.map((v) => v.showPlot)),
        cover: mostCommon(list.map((v) => v.cover)),
      ));
    }
    built.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    collections = built;
    _collectionByKey = {for (final c in built) c.key: c};
    notifyListeners();
  }

  // ---- folders and scanning ----

  void _onLibraryChanged() {
    // The usual picture shapes changed (Settings › Videos): the Videos tab redraws.
    final shapes = (library.videoPictureShape, library.collectionPictureShape);
    if (shapes != _knownShapes) {
      _knownShapes = shapes;
      notifyListeners();
    }
    // A video folder's File types changed: shown or left out at once, no scan needed.
    final hidden = _hiddenKey();
    if (hidden != _knownHidden) {
      _knownHidden = hidden;
      _rebuild();
    }
    final now = library.videoFolders;
    if (listEquals(now, _knownFolders)) return;
    final added = now.any((f) => !_knownFolders.contains(f));
    _knownFolders = List.of(now);
    // Removed only: drop that folder's videos at once, no scan needed.
    _scanned = [for (final v in _scanned) if (now.any((f) => isInside(v.path, f))) v];
    offlineFolders = [for (final f in offlineFolders) if (now.contains(f)) f];
    _rebuild();
    _pendingSave = _save();
    if (added) scan();
  }

  Future<void> _pendingSave = Future.value();
  late (PictureShape, PictureShape) _knownShapes = (library.videoPictureShape, library.collectionPictureShape);

  /// Waits for any scan and save in progress (tests, and before a restore).
  Future<void> settle() async {
    await _jobs;
    await _pendingSave;
    await flushPendingSaves();
  }

  Future<void> _jobs = Future.value();

  /// Looks for new, changed and removed videos in every video folder. Scans queue up.
  Future<void> scan() {
    final next = _jobs.then((_) => _scan());
    _jobs = next.catchError((_) {});
    return next;
  }

  Future<void> _scan() async {
    final folders = List.of(library.videoFolders);
    if (folders.isEmpty) {
      error = null;
      notifyListeners();
      return;
    }
    if (await checkAccess() != MusicAccess.allowed) {
      error = 'HomeTunes needs "Photos and videos" access to list your videos.';
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    status = 'Looking for videos…';
    notifyListeners();
    try {
      final (:reachable, :offline) = await checkFolders(folders, folderReachable);
      offlineFolders = offline;
      final previous = {for (final v in _scanned) v.id: v};
      final found = await _scanner.scan(reachable, previous: previous);
      final foundIds = {for (final v in found) v.id};
      final kept = [
        for (final v in _scanned)
          if (!foundIds.contains(v.id) && offlineFolders.any((f) => isInside(v.path, f))) v
      ];
      _scanned = [...found, ...kept];
      // Places and edits of videos that have gone are forgotten, unless their folder is offline.
      final ids = {for (final v in _scanned) v.id};
      _places.removeWhere((id, _) => !ids.contains(id));
      _edits.removeWhere((id, _) => !ids.contains(id));
      if (offlineFolders.isNotEmpty) {
        error = 'Can\'t reach ${offlineFolders.join(', ')} right now, so its videos are shown as they were.';
      }
      await _save();
    } catch (e) {
      error = 'Video scan failed: $e';
    } finally {
      busy = false;
      status = null;
      _rebuild();
    }
    unawaited(makeThumbnails());
  }

  // ---- thumbnails ----

  bool _thumbing = false;
  final Set<String> _thumbFailed = {};

  /// Where thumbnails are kept.
  String get thumbDir => p.join(storage.artDir, 'video');

  /// Makes a picture for every video without one, one at a time, and learns their lengths.
  Future<void> makeThumbnails() async {
    final maker = thumbnailer;
    if (maker == null || _thumbing) return;
    _thumbing = true;
    var done = 0;
    try {
      while (true) {
        VideoItem? next;
        for (final v in _scanned) {
          final t = v.thumb;
          if (!_thumbFailed.contains(v.id) && (t == null || !File(t).existsSync())) {
            next = v;
            break;
          }
        }
        if (next == null) break;
        final facts = await maker.make(next.path, modifiedMs: next.modifiedMs);
        if (facts.thumb == null) _thumbFailed.add(next.id);
        _update(next.id, (v) => v.copyWith(
              thumb: facts.thumb,
              duration: facts.duration > Duration.zero ? facts.duration : null,
              width: facts.width,
              height: facts.height,
            ));
        // Show pictures as they arrive, a few at a time.
        if (++done % 4 == 0) _rebuild();
      }
    } finally {
      _thumbing = false;
      await maker.dispose();
      if (done > 0) {
        _rebuild();
        await _save();
      }
      await _removeUnusedThumbs();
    }
  }

  /// Sets a thumbnail and length by hand (off-screen preview pictures, which have no engine).
  @visibleForTesting
  void debugSetThumb(String id, String thumb, Duration duration) {
    _update(id, (v) => v.copyWith(thumb: thumb, duration: duration));
    _rebuild();
    _pendingSave = _save();
  }

  void _update(String id, VideoItem Function(VideoItem) change) {
    final i = _scanned.indexWhere((v) => v.id == id);
    if (i >= 0) _scanned[i] = change(_scanned[i]);
  }

  Future<void> _removeUnusedThumbs() async {
    final dir = Directory(thumbDir);
    if (!await dir.exists()) return;
    final used = {for (final v in _scanned) if (v.thumb != null) p.normalize(v.thumb!)};
    await for (final e in dir.list()) {
      if (e is File && !used.contains(p.normalize(e.path))) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  }

  // ---- edits ----

  /// Sets (or with null / an empty edit, removes) the user's edit to one video.
  Future<void> setEdit(String id, VideoEdit? edit) => setEdits({id: edit});

  /// Several at once (editing several videos together).
  Future<void> setEdits(Map<String, VideoEdit?> edits) async {
    for (final e in edits.entries) {
      final edit = e.value;
      if (edit == null || edit.isEmpty) {
        _edits.remove(e.key);
      } else {
        _edits[e.key] = edit;
      }
    }
    _rebuild();
    await _save();
  }

  // ---- places ----

  /// Remembers how far into video [id] the user got. Near the end counts as watched.
  /// Also learns the length if the scan didn't know it.
  void savePlace(String id, Duration position, Duration length) {
    final old = _places[id];
    final end = isNearEnd(position, length);
    _places[id] = VideoPlace(
      position: position,
      watched: end || (old?.watched ?? false),
      updatedMs: DateTime.now().millisecondsSinceEpoch,
    );
    final raw = _rawById[id];
    if (raw != null && length > Duration.zero && (raw.duration - length).abs() > const Duration(seconds: 2)) {
      _update(id, (v) => v.copyWith(duration: length));
      _rebuild();
    } else {
      notifyListeners();
    }
    _saveSoon();
  }

  /// Marks videos as watched or not (not watched also starts them again from the beginning).
  Future<void> setWatched(Iterable<String> ids, bool watched) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in ids) {
      _places[id] = VideoPlace(
        position: watched ? (_places[id]?.position ?? Duration.zero) : Duration.zero,
        watched: watched,
        updatedMs: now,
      );
    }
    notifyListeners();
    await _save();
  }

  @override
  void dispose() {
    library.removeListener(_onLibraryChanged);
    _saveTimer?.cancel();
    super.dispose();
  }

}

/// The value found most often (nulls skipped); null when there's none.
T? mostCommon<T>(Iterable<T?> values) {
  final counts = <T, int>{};
  for (final x in values) {
    if (x != null) counts[x] = (counts[x] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}
