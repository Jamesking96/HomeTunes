// Videos (0.1.32): the Videos tab's live data.
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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/video_item.dart';
import '../services/music_permission.dart';
import '../services/path_safety.dart';
import '../services/storage.dart';
import '../services/video_scanner.dart';
import '../services/video_thumbnails.dart';
import 'book_index.dart' show isInside;
import 'library_model.dart';
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
  Future<bool> Function(String folder) folderReachable = _canList;

  final VideoScanner _scanner = VideoScanner();

  VideoLibraryModel(this.storage, this.library) {
    _knownFolders = List.of(library.videoFolders);
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
  List<String> get collections =>
      ({for (final v in videos) v.collection}.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));

  /// The file to play, if it's still there and inside a video folder (a restored backup could
  /// name any path; 0.1.21 security review #3).
  String? playableFile(VideoItem v) =>
      isUsableLocalFile(v.path, roots: library.videoFolders, extensions: videoFileExtensions) ? v.path : null;

  /// The thumbnail, if it's inside the app's own art folder.
  String? thumbFile(VideoItem v) {
    final t = v.thumb;
    return t != null && isInsideAny(t, [storage.artDir]) ? t : null;
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
    if (damaged) await storage.keepCopy(fileName);
    _scanned = scanned;
    _edits = edits;
    _places = places;
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

  void _rebuild() {
    _rawById = {for (final v in _scanned) v.id: v};
    final all = [for (final v in _scanned) _edits[v.id]?.applyTo(v) ?? v]
      ..sort((a, b) {
        final t = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return t != 0 ? t : a.path.compareTo(b.path);
      });
    videos = all;
    _byId = {for (final v in all) v.id: v};
    notifyListeners();
  }

  // ---- folders and scanning ----

  void _onLibraryChanged() {
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
      final reachable = <String>[];
      final unreachable = <String>[];
      for (final f in folders) {
        (await folderReachable(f) ? reachable : unreachable).add(f);
      }
      offlineFolders = [for (final f in unreachable) if (!reachable.any((r) => isInside(f, r))) f];
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

  static Future<bool> _canList(String folder) async {
    try {
      final dir = Directory(folder);
      if (!await dir.exists()) return false;
      await dir.list(followLinks: false).take(1).toList().timeout(const Duration(seconds: 10));
      return true;
    } catch (_) {
      return false;
    }
  }
}
