// Downloads (0.2.3, step 3 of the Servers & Downloads plan): songs, audiobooks and videos from
// servers, kept on this device so they play without the server.
//
// The user asked (25 Oct) for "an added option to streamed media to allow for them to be
// downloaded (along with a remove and new filter option to find these)", and chose: the quality
// each time (original or a smaller copy), Keep offline, Download next episodes, Wi-Fi only and a
// storage limit, and Make it mine. On 27 Oct: downloads go in HomeTunes' data folder unless
// another one is picked; Keep offline and next-episode downloads carry on in the background on
// the phone, with a message saying so and a switch to stop it.
//
// This model keeps the list (downloads.json: what's downloaded or waiting, what's kept offline,
// and the Downloads settings) and decides what to fetch; a DownloadEngine moves the bytes
// (services/download_engine.dart). It plugs into the rest of the app through hooks: the player
// and the video page play a downloaded copy first (LibraryModel.downloadedFile,
// VideoLibraryModel.downloadedCopy), the Source filter knows what's downloaded
// (MediaSources.downloaded), and starting a server episode downloads the next ones
// (VideoLibraryModel.onServerVideoStarted).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/download.dart';
import '../models/track.dart';
import '../models/video_item.dart';
import '../services/download_engine.dart';
import '../services/storage.dart';
import 'library_model.dart';
import 'playlists_model.dart';
import 'remote_videos.dart';
import 'server_videos.dart' show ServerVideosModel, serverSubtitle;
import 'source_filter.dart';
import 'video_library_model.dart';
import 'video_tracks.dart' show languageCodeFor;

/// Where a download comes from: its address, the headers it needs, the file type, and (videos)
/// its subtitle files.
typedef DownloadRequest = ({
  String url,
  Map<String, String> headers,
  String ext,
  List<({String url, String format})> subtitles,
});

/// What knows the servers' addresses (the app's is [AppDownloadSources]; tests use a fake).
abstract class DownloadSources {
  /// Where to fetch [e] from, or null (then [problem] says why).
  Future<DownloadRequest?> request(DownloadEntry e);
  String? problem(DownloadEntry e);
}

/// Something that can be downloaded.
class DownloadItem {
  final String id;
  final DownloadKind kind;
  final String title;
  final String subtitle;
  final Duration length;
  final int? size;
  final bool book;
  const DownloadItem(this.id, this.kind, this.title,
      {this.subtitle = '', this.length = Duration.zero, this.size, this.book = false});

  factory DownloadItem.track(Track t, {bool book = false}) => DownloadItem(t.id, DownloadKind.song, t.title,
      subtitle: book ? t.artist : '${t.artist} · ${t.album}', length: t.duration, book: book);

  factory DownloadItem.video(VideoItem v) => DownloadItem(v.id, DownloadKind.video, v.title,
      subtitle: [v.collection, ?v.episodeLabel].join(' · '), length: v.duration, size: v.sizeBytes);
}

class DownloadsModel extends ChangeNotifier {
  DownloadsModel({
    required this.storage,
    required this.library,
    required this.playlists,
    required this.videos,
    required this.engine,
    required this.sources,
    http.Client Function()? httpClient,
    bool? android,
  })  : _http = httpClient ?? http.Client.new,
        android = android ?? Platform.isAndroid {
    library.downloadedFile = fileFor;
    videos.downloadedCopy = copyOf;
    videos.onServerVideoStarted = _downloadAhead;
    MediaSources.downloaded = isDownloaded;
    library.addListener(_soon);
    playlists.addListener(_soon);
    videos.addListener(_soon);
  }

  final Storage storage;
  final LibraryModel library;
  final PlaylistsModel playlists;
  final VideoLibraryModel videos;
  final DownloadEngine engine;
  final DownloadSources sources;
  final http.Client Function() _http;

  /// Phone or TV: Wi-Fi only and "in the background" apply.
  final bool android;

  static const fileName = 'downloads.json';

  /// For tests: the clock.
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  /// Says something to the user (main.dart shows it as a notice).
  void Function(String message)? onNotice;

  // ---- what's kept ----

  final Map<String, DownloadEntry> _entries = {};
  final Map<String, KeepOffline> _kept = {};

  /// Per thing kept offline: items the user removed from it, which aren't downloaded again.
  final Map<String, Set<String>> _skipped = {};

  /// Downloads, newest first.
  List<DownloadEntry> get entries => _entries.values.toList()..sort((a, b) => b.addedMs.compareTo(a.addedMs));
  List<DownloadEntry> get waiting => [for (final e in entries) if (!e.isDone) e];
  List<DownloadEntry> get done => [for (final e in entries) if (e.isDone) e];
  List<KeepOffline> get kept => _kept.values.toList()..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  DownloadEntry? entryOf(String id) => _entries[id];

  /// Has a downloaded copy here.
  bool isDownloaded(String id) {
    final e = _entries[id];
    return e != null && e.isDone && e.file != null;
  }

  /// Is waiting or downloading.
  bool isPending(String id) => _entries[id]?.isDone == false;

  /// The downloaded file of song [id], if it's still there.
  String? fileFor(String id) {
    final e = _entries[id];
    final f = e?.file;
    if (e == null || !e.isDone || f == null) return null;
    if (!File(f).existsSync()) {
      _lost(e);
      return null;
    }
    return f;
  }

  /// The downloaded copy of video [v] to play, with its subtitle files.
  VideoAddress? copyOf(VideoItem v) {
    final f = fileFor(v.id);
    if (f == null) return null;
    final e = _entries[v.id]!;
    final subs = <({String uri, String label, String? language})>[];
    for (var i = 0; i < e.subtitles.length && i < v.subtitles.length; i++) {
      final path = e.subtitles[i];
      final info = serverSubtitle(v.subtitles[i]);
      if (path.isEmpty || info == null || !File(path).existsSync()) continue;
      subs.add((uri: path, label: info.label, language: info.language));
    }
    return VideoAddress(f, subtitles: subs);
  }

  // A downloaded file went missing (deleted by hand, drive gone): download it again.
  void _lost(DownloadEntry e) {
    _entries[e.id] = e.copyWith(state: DownloadState.queued, bytes: 0, progress: 0, clearError: true);
    scheduleMicrotask(() {
      notifyListeners();
      _pump();
      _save();
    });
  }

  bool isKept(KeepKind kind, String key) => _kept.containsKey('${kind.name}:$key');

  // ---- settings (kept in downloads.json; Settings › Servers › Downloads) ----

  /// The folder picked for downloads, or null for HomeTunes' own data folder.
  String? customFolder;

  /// Phones and TVs: only download over Wi-Fi (on to start with).
  bool wifiOnly = true;

  /// Phones and TVs: Keep offline and episodes ahead carry on while HomeTunes is in the background.
  bool background = true;
  bool _backgroundNoticeShown = false;

  /// The space downloads may take, in GB, or null for no limit.
  int? limitGb;

  /// How many episodes to download ahead while watching a series from a server (0 = none).
  int ahead = 2;

  /// The copy downloaded ahead.
  DownloadQuality aheadQuality = const DownloadQuality.original(video: true);

  /// HomeTunes' own downloads folder.
  String get defaultFolder => p.join(storage.root.path, 'downloads');
  String get folder => customFolder ?? defaultFolder;

  Future<void> setWifiOnly(bool on) async {
    wifiOnly = on;
    await engine.setWifiOnly(on && android);
    notifyListeners();
    await _save();
  }

  Future<void> setBackground(bool on) async {
    background = on;
    notifyListeners();
    await _save();
  }

  Future<void> setLimitGb(int? gb) async {
    limitGb = gb == null || gb <= 0 ? null : gb;
    // More room: what was waiting for it can go on.
    for (final e in [..._entries.values]) {
      if (e.state == DownloadState.noRoom) _entries[e.id] = e.copyWith(state: DownloadState.queued);
    }
    notifyListeners();
    await _save();
    _pump();
  }

  Future<void> setAhead(int n) async {
    ahead = n.clamp(0, 5);
    notifyListeners();
    await _save();
  }

  Future<void> setAheadQuality(DownloadQuality q) async {
    aheadQuality = q;
    notifyListeners();
    await _save();
  }

  /// Downloads go to [path] from now on (null: the data folder). With [move], what's already
  /// downloaded moves there too. Returns how many files couldn't be moved.
  Future<int> setFolder(String? path, {bool move = false}) async {
    final next = path == null || p.equals(path, defaultFolder) ? null : path;
    final before = folder;
    customFolder = next;
    var failed = 0;
    if (move && !p.equals(before, folder)) {
      status = 'Moving your downloads…';
      notifyListeners();
      for (final e in done) {
        final f = e.file;
        if (f == null || !p.isWithin(before, f)) continue;
        final to = p.join(folder, p.relative(f, from: before));
        final moved = await _move(f, to);
        if (moved == null) {
          failed++;
          continue;
        }
        final subs = <String>[];
        for (final s in e.subtitles) {
          subs.add(s.isEmpty || !p.isWithin(before, s) ? s : (await _move(s, p.join(folder, p.relative(s, from: before))) ?? ''));
        }
        _entries[e.id] = e.copyWith(file: moved, subtitles: subs);
      }
      status = null;
    }
    notifyListeners();
    await _save();
    return failed;
  }

  static Future<String?> _move(String from, String to) async {
    try {
      await Directory(p.dirname(to)).create(recursive: true);
      try {
        await File(from).rename(to);
      } on FileSystemException {
        // Another drive: copy, then delete.
        await File(from).copy(to);
        await File(from).delete();
      }
      return to;
    } catch (_) {
      return null;
    }
  }

  /// What's happening now ("Moving your downloads…"), or null.
  String? status;

  // ---- space ----

  /// How much the downloads take now (finished ones, and what's arrived of the rest).
  int get usedBytes => _entries.values.fold(0, (s, e) => s + e.bytes);

  int? get limitBytes => limitGb == null ? null : limitGb! * 1000 * 1000 * 1000;

  /// Whether [e] fits in the space left (counting what's already waiting in the engine).
  bool _fits(DownloadEntry e) {
    final limit = limitBytes;
    if (limit == null) return true;
    var taken = 0;
    for (final x in _entries.values) {
      if (x.id == e.id) continue;
      if (x.isDone) {
        taken += x.bytes;
      } else if (_inEngine.contains(x.id)) {
        taken += x.expected ?? x.bytes;
      }
    }
    return taken + (e.expected ?? 0) <= limit;
  }

  // ---- loading and saving ----

  Future<void> load() async {
    final j = await storage.read(fileName);
    if (j is Map) {
      for (final x in (j['entries'] is List ? j['entries'] as List : const [])) {
        final e = DownloadEntry.fromJson(x);
        if (e != null) _entries[e.id] = e;
      }
      for (final x in (j['kept'] is List ? j['kept'] as List : const [])) {
        final k = KeepOffline.fromJson(x);
        if (k != null) _kept[k.id] = k;
      }
      final sk = j['skipped'];
      if (sk is Map) {
        for (final e in sk.entries) {
          if (e.key is String && e.value is List) {
            _skipped[e.key as String] = {for (final s in e.value as List) if (s is String) s};
          }
        }
      }
      final s = j['settings'];
      if (s is Map) {
        customFolder = s['folder'] is String && (s['folder'] as String).isNotEmpty ? s['folder'] as String : null;
        wifiOnly = s['wifiOnly'] != false;
        background = s['background'] != false;
        _backgroundNoticeShown = s['backgroundNoticeShown'] == true;
        limitGb = s['limitGb'] is int && (s['limitGb'] as int) > 0 ? s['limitGb'] as int : null;
        ahead = s['ahead'] is int ? (s['ahead'] as int).clamp(0, 5) : 2;
        aheadQuality = DownloadQuality.parse(s['aheadQuality'], video: true);
      }
    }
    // A file deleted while HomeTunes was closed (or a backup from another device): download it
    // again.
    for (final e in [..._entries.values]) {
      if (e.isDone && (e.file == null || !File(e.file!).existsSync())) {
        _entries[e.id] = e.copyWith(state: DownloadState.queued, bytes: 0, progress: 0);
      }
    }
    notifyListeners();
  }

  Future<void> _save() => storage.write(fileName, {
        'entries': [for (final e in entries) e.toJson()],
        if (_kept.isNotEmpty) 'kept': [for (final k in kept) k.toJson()],
        if (_skipped.isNotEmpty) 'skipped': {for (final e in _skipped.entries) if (e.value.isNotEmpty) e.key: e.value.toList()},
        'settings': {
          if (customFolder != null) 'folder': customFolder,
          if (!wifiOnly) 'wifiOnly': false,
          if (!background) 'background': false,
          if (_backgroundNoticeShown) 'backgroundNoticeShown': true,
          if (limitGb != null) 'limitGb': limitGb,
          'ahead': ahead,
          if (!aheadQuality.isOriginal) 'aheadQuality': aheadQuality.code,
        },
      });

  Timer? _saveTimer;
  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _save);
  }

  StreamSubscription<EngineUpdate>? _sub;
  StreamSubscription<bool?>? _wifiSub;

  /// Whether the device is on Wi-Fi now (phones and TVs; null when it doesn't matter).
  bool? onWifi;

  /// Starts the engine and carries on with what was waiting. Called once the app is up.
  Future<void> start() async {
    _sub = engine.updates.listen(_onEngine);
    await engine.start();
    await engine.setWifiOnly(wifiOnly && android);
    onWifi = await engine.onWifi();
    _wifiSub = engine.wifiChanges.listen((w) {
      onWifi = w;
      notifyListeners();
    });
    _started = true;
    _pump();
    _soon();
  }

  bool _started = false;

  // ---- downloading ----

  /// Ids the engine has been given and hasn't finished.
  final Set<String> _inEngine = {};

  /// Downloads paused because HomeTunes went into the background (phones, background off).
  final Set<String> _heldBack = {};

  // One task id per download: the id with anything odd replaced.
  static String taskIdFor(String id) => 'ht-${id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';
  String? _entryOfTask(String taskId) {
    for (final id in _entries.keys) {
      if (taskIdFor(id) == taskId) return id;
    }
    return null;
  }

  /// Downloads [items] as [quality] (a smaller copy is a converted one). Ones already downloaded
  /// or waiting are left alone (one that failed is tried again). Returns how many were added.
  int download(Iterable<DownloadItem> items, DownloadQuality quality, {DownloadOrigin origin = DownloadOrigin.manual}) {
    var added = 0;
    for (final it in items) {
      if (!isRemoteVideoId(it.id) && !it.id.startsWith('server:')) continue; // only server things
      final old = _entries[it.id];
      if (old != null) {
        if (old.state == DownloadState.failed) {
          _entries[it.id] = old.copyWith(state: DownloadState.queued, clearError: true, progress: 0);
          added++;
        } else if (origin == DownloadOrigin.manual && old.origin != DownloadOrigin.manual) {
          // Asked for now: it stays even when watched, or when no longer kept.
          _entries[it.id] = old.copyWith(origin: DownloadOrigin.manual);
        }
        continue;
      }
      final q = it.kind == DownloadKind.video ? _videoQuality(quality) : _audioQuality(quality);
      final e = DownloadEntry(
        id: it.id,
        kind: it.kind,
        title: it.title,
        subtitle: it.subtitle,
        quality: q,
        origin: origin,
        addedMs: now() + added, // keeps their order
        book: it.book,
      );
      _entries[it.id] = e.copyWith(expected: q.estimate(it.length, originalBytes: it.size));
      // Asked for again after being taken out of something kept offline.
      if (origin == DownloadOrigin.manual) {
        for (final s in _skipped.values) {
          s.remove(it.id);
        }
      }
      added++;
    }
    if (added > 0) {
      if (origin != DownloadOrigin.manual) _sayBackground();
      notifyListeners();
      _saveSoon();
      _pump();
      if (android) unawaited(engine.askForNotifications());
    }
    return added;
  }

  static DownloadQuality _videoQuality(DownloadQuality q) =>
      q.isOriginal ? const DownloadQuality.original(video: true) : (q.video ? q : DownloadQuality.videoHeight(720));
  static DownloadQuality _audioQuality(DownloadQuality q) =>
      q.isOriginal ? const DownloadQuality.original() : (q.video ? const DownloadQuality.audioBitrate(192) : q);

  bool _pumping = false, _pumpAgain = false;

  /// Hands what's waiting to the engine (it runs two at a time).
  Future<void> _pump() async {
    if (!_started) return;
    if (_pumping) {
      _pumpAgain = true;
      return;
    }
    _pumping = true;
    try {
      do {
        _pumpAgain = false;
        for (final e in [...entries.reversed]) {
          final cur = _entries[e.id];
          if (cur == null || cur.state != DownloadState.queued || _inEngine.contains(e.id)) continue;
          if (_heldBack.contains(e.id)) continue;
          if (!_fits(cur)) {
            _entries[e.id] = cur.copyWith(state: DownloadState.noRoom);
            notifyListeners();
            continue;
          }
          final req = await sources.request(cur);
          final now2 = _entries[e.id];
          if (now2 == null || now2.state != DownloadState.queued) continue;
          if (req == null) {
            _entries[e.id] = now2.copyWith(
                state: DownloadState.failed, error: sources.problem(now2) ?? 'The server can\'t be reached right now.');
            notifyListeners();
            continue;
          }
          final dir = p.join(folder, now2.kind == DownloadKind.video ? 'videos' : 'music');
          final job = DownloadJob(
            taskId: taskIdFor(e.id),
            url: req.url,
            headers: req.headers,
            folder: dir,
            fileName: '${_safe(e.id)}.${req.ext.isEmpty ? 'download' : req.ext}',
            displayName: now2.subtitle.isEmpty ? now2.title : '${now2.title} (${now2.subtitle})',
            large: now2.kind == DownloadKind.video,
            automatic: now2.origin != DownloadOrigin.manual,
          );
          _requests[e.id] = req;
          _jobs[e.id] = job;
          await Directory(dir).create(recursive: true);
          if (await engine.enqueue(job)) {
            _inEngine.add(e.id);
          } else {
            _entries[e.id] = now2.copyWith(state: DownloadState.failed, error: 'The download couldn\'t be started.');
          }
          notifyListeners();
        }
      } while (_pumpAgain);
    } finally {
      _pumping = false;
    }
    _saveSoon();
  }

  final Map<String, DownloadRequest> _requests = {};
  final Map<String, DownloadJob> _jobs = {};
  final Set<String> _retriedSignIn = {};

  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<void> _onEngine(EngineUpdate u) async {
    final id = _entryOfTask(u.taskId);
    if (id == null) return;
    final e = _entries[id];
    if (e == null) return;
    if (u.status == null) {
      // Progress.
      final expected = u.expectedBytes ?? e.expected;
      final progress = u.progress ?? e.progress;
      _entries[id] = e.copyWith(
        state: e.state == DownloadState.paused ? null : DownloadState.running,
        progress: progress,
        expected: expected,
        bytes: expected == null ? e.bytes : (expected * progress).round(),
      );
      _notifySoon();
      return;
    }
    switch (u.status!) {
      case EngineStatus.waiting:
        _inEngine.add(id);
        if (e.state != DownloadState.queued) _entries[id] = e.copyWith(state: DownloadState.queued);
      case EngineStatus.running:
        _inEngine.add(id);
        _entries[id] = e.copyWith(state: DownloadState.running, clearError: true);
      case EngineStatus.paused:
        _entries[id] = e.copyWith(state: DownloadState.paused);
      case EngineStatus.done:
        _inEngine.remove(id);
        await _finished(e, u.mimeType);
      case EngineStatus.notFound:
        _inEngine.remove(id);
        _entries[id] = e.copyWith(state: DownloadState.failed, error: 'The server doesn\'t have it any more.');
      case EngineStatus.failed:
        _inEngine.remove(id);
        // The sign-in stopped working: ask for a new address once (it signs in again).
        if ((u.httpStatus == 401 || u.httpStatus == 403) && _retriedSignIn.add(id)) {
          _entries[id] = e.copyWith(state: DownloadState.queued);
          _pump();
        } else {
          _entries[id] = e.copyWith(state: DownloadState.failed, error: _plainError(u));
        }
      case EngineStatus.canceled:
        _inEngine.remove(id);
        // Cancelled by us (removed, or held back while in the background).
        if (_heldBack.contains(id)) _entries[id] = e.copyWith(state: DownloadState.paused);
    }
    notifyListeners();
    _saveSoon();
    if (u.status == EngineStatus.done || u.status == EngineStatus.failed || u.status == EngineStatus.notFound) _pump();
  }

  static String _plainError(EngineUpdate u) {
    final code = u.httpStatus;
    if (code != null && code >= 400) return 'The server answered $code.';
    final err = (u.error ?? '').toLowerCase();
    if (err.contains('space')) return 'There isn\'t enough free space on this device.';
    if (err.isEmpty) return 'The connection to the server was lost.';
    return 'The connection to the server was lost (${u.error}).';
  }

  Timer? _notifyTimer;
  void _notifySoon() {
    if (_notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 400), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  /// A file arrived: give it its proper name, fetch a video's subtitle files, and it's done.
  Future<void> _finished(DownloadEntry e, String? mime) async {
    final job = _jobs.remove(e.id);
    final req = _requests.remove(e.id);
    var path = job?.path ?? p.join(folder, e.kind == DownloadKind.video ? 'videos' : 'music', '${_safe(e.id)}.download');
    // A song's original file: its type comes from the server's answer.
    if (path.endsWith('.download')) {
      final renamed = '${path.substring(0, path.length - 9)}.${extensionForMime(mime)}';
      try {
        await File(path).rename(renamed);
        path = renamed;
      } catch (_) {}
    }
    final subs = <String>[];
    if (req != null && req.subtitles.isNotEmpty) {
      final c = _http();
      try {
        for (var i = 0; i < req.subtitles.length; i++) {
          final s = req.subtitles[i];
          final to = '${p.withoutExtension(path)}.$i.${s.format}';
          try {
            final r = await c.get(Uri.parse(s.url), headers: req.headers).timeout(const Duration(seconds: 30));
            if (r.statusCode == 200 && r.bodyBytes.isNotEmpty && r.bodyBytes.length < (20 << 20)) {
              await File(to).writeAsBytes(r.bodyBytes, flush: true);
              subs.add(to);
              continue;
            }
          } catch (_) {}
          subs.add('');
        }
      } finally {
        c.close();
      }
    }
    var bytes = 0;
    try {
      bytes = await File(path).length();
    } catch (_) {}
    final cur = _entries[e.id];
    if (cur == null) {
      // Removed while it finished.
      _deleteFiles(path, subs);
      return;
    }
    _entries[e.id] = cur.copyWith(
      state: DownloadState.done,
      file: path,
      subtitles: subs,
      bytes: bytes,
      expected: bytes,
      progress: 1,
      doneMs: now(),
      clearError: true,
    );
    _retriedSignIn.remove(e.id);
  }

  /// A file type for what the server sent.
  static String extensionForMime(String? mime) => switch ((mime ?? '').toLowerCase()) {
        'audio/mpeg' || 'audio/mp3' => 'mp3',
        'audio/flac' || 'audio/x-flac' => 'flac',
        'audio/mp4' || 'audio/m4a' || 'audio/x-m4a' || 'audio/aac' => 'm4a',
        'audio/ogg' || 'audio/vorbis' => 'ogg',
        'audio/opus' => 'opus',
        'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
        'audio/x-ms-wma' => 'wma',
        'video/mp4' => 'mp4',
        'video/x-matroska' => 'mkv',
        _ => 'mp3',
      };

  static void _deleteFiles(String? file, Iterable<String> subs) {
    for (final f in [?file, ...subs]) {
      if (f.isEmpty) continue;
      try {
        final x = File(f);
        if (x.existsSync()) x.deleteSync();
      } catch (_) {}
    }
  }

  // ---- controls (the Downloads page and menus) ----

  Future<void> pause(String id) async {
    final e = _entries[id];
    if (e == null || e.isDone) return;
    if (_inEngine.contains(id) && await engine.pause(taskIdFor(id))) {
      _entries[id] = e.copyWith(state: DownloadState.paused);
    } else {
      // Not started yet (or can't be paused): take it out of the queue until resumed.
      if (_inEngine.remove(id)) await engine.cancel(taskIdFor(id));
      _entries[id] = e.copyWith(state: DownloadState.paused);
    }
    notifyListeners();
    _saveSoon();
  }

  Future<void> resume(String id) async {
    final e = _entries[id];
    if (e == null || e.state != DownloadState.paused) return;
    _heldBack.remove(id);
    if (_inEngine.contains(id) && await engine.resume(taskIdFor(id))) {
      _entries[id] = e.copyWith(state: DownloadState.running);
    } else {
      _inEngine.remove(id);
      _entries[id] = e.copyWith(state: DownloadState.queued);
      _pump();
    }
    notifyListeners();
    _saveSoon();
  }

  Future<void> retry(String id) async {
    final e = _entries[id];
    if (e == null || !(e.state == DownloadState.failed || e.state == DownloadState.noRoom)) return;
    _retriedSignIn.remove(id);
    _entries[id] = e.copyWith(state: DownloadState.queued, clearError: true, progress: 0);
    notifyListeners();
    _pump();
  }

  Future<void> pauseAll() async {
    for (final e in waiting) {
      if (e.state != DownloadState.paused) await pause(e.id);
    }
  }

  Future<void> resumeAll() async {
    for (final e in waiting) {
      if (e.state == DownloadState.paused) await resume(e.id);
    }
    for (final e in [..._entries.values]) {
      if (e.state == DownloadState.failed || e.state == DownloadState.noRoom) await retry(e.id);
    }
  }

  /// Removes downloads [ids] (or stops them downloading) and deletes their files. Ones that are
  /// part of something kept offline aren't downloaded again for it.
  Future<void> remove(Iterable<String> ids) async {
    for (final id in ids.toList()) {
      final e = _entries.remove(id);
      if (e == null) continue;
      if (_inEngine.remove(id)) await engine.cancel(taskIdFor(id));
      _heldBack.remove(id);
      _jobs.remove(id);
      _requests.remove(id);
      _deleteFiles(e.file, e.subtitles);
      for (final k in _kept.values) {
        if (_itemsOf(k).any((it) => it.id == id)) (_skipped[k.id] ??= {}).add(id);
      }
    }
    // Room freed: what was waiting for it can go on.
    for (final e in [..._entries.values]) {
      if (e.state == DownloadState.noRoom) _entries[e.id] = e.copyWith(state: DownloadState.queued);
    }
    notifyListeners();
    await _save();
    _pump();
  }

  /// Removes every download.
  Future<void> removeAll() => remove([..._entries.keys]);

  // ---- keep offline ----

  /// Keeps [kind] [key] offline (everything in it is downloaded, now and as more is added), or
  /// stops (its downloads stay unless [removeDownloads]).
  Future<void> setKept(KeepKind kind, String key, String label, bool on,
      {DownloadQuality quality = const DownloadQuality.original(), bool removeDownloads = false}) async {
    final k = KeepOffline(kind, key, label, quality);
    if (on) {
      _kept[k.id] = k;
      _skipped.remove(k.id);
      _syncKept();
    } else {
      final old = _kept.remove(k.id);
      _skipped.remove(k.id);
      if (old != null) {
        final items = {for (final it in _itemsOf(old)) it.id};
        final stillKept = {for (final other in _kept.values) for (final it in _itemsOf(other)) it.id};
        if (removeDownloads) {
          await remove([for (final id in items) if (!stillKept.contains(id)) id]);
        } else {
          // What it downloaded now stays as if asked for.
          for (final id in items) {
            final e = _entries[id];
            if (e != null && e.origin == DownloadOrigin.keep && !stillKept.contains(id)) {
              _entries[id] = e.copyWith(origin: DownloadOrigin.manual);
            }
          }
        }
      }
    }
    notifyListeners();
    await _save();
  }

  /// What's in something kept offline now (server things only).
  List<DownloadItem> _itemsOf(KeepOffline k) {
    bool server(Track t) => !t.isLocal;
    switch (k.kind) {
      case KeepKind.album:
        return [for (final t in library.albumByKey(k.key)?.tracks ?? const <Track>[]) if (server(t)) DownloadItem.track(t)];
      case KeepKind.playlist:
        return [
          for (final id in playlists.byId(k.key)?.trackIds ?? const <String>[])
            if (library.byId(id) case final t? when server(t)) DownloadItem.track(t),
        ];
      case KeepKind.liked:
        return [for (final id in playlists.liked) if (library.byId(id) case final t? when server(t)) DownloadItem.track(t)];
      case KeepKind.book:
        return [for (final t in library.bookById(k.key)?.parts ?? const <Track>[]) if (server(t)) DownloadItem.track(t, book: true)];
      case KeepKind.collection:
        final c = videos.collectionNamed(k.key);
        return [for (final v in c?.videos ?? const <VideoItem>[]) if (isRemoteVideoId(v.id)) DownloadItem.video(v)];
      case KeepKind.season:
        final bar = k.key.indexOf('|');
        if (bar < 0) return const [];
        final c = videos.collectionNamed(k.key.substring(0, bar));
        final heading = k.key.substring(bar + 1);
        return [
          for (final v in c?.videos ?? const <VideoItem>[])
            if (isRemoteVideoId(v.id) && VideoCollection.groupOf(v) == heading) DownloadItem.video(v),
        ];
    }
  }

  /// The key a season is kept under.
  static String seasonKey(VideoCollection c, String heading) => '${c.key}|$heading';

  Timer? _syncTimer;

  // The library, a playlist or the videos changed: check what's kept, and tidy episodes ahead.
  void _soon() {
    if (!_started) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 2), () {
      _syncKept();
      _tidyAhead();
    });
  }

  void _syncKept() {
    for (final k in _kept.values) {
      final skip = _skipped[k.id] ?? const <String>{};
      final todo = [for (final it in _itemsOf(k)) if (!skip.contains(it.id) && !_entries.containsKey(it.id)) it];
      if (todo.isNotEmpty) download(todo, k.quality, origin: DownloadOrigin.keep);
    }
  }

  // ---- episodes ahead ----

  void _downloadAhead(VideoItem v) {
    if (ahead <= 0) return;
    final next = <DownloadItem>[];
    var at = v;
    for (var i = 0; i < ahead; i++) {
      final n = videos.after(at);
      if (n == null) break;
      at = n;
      if (isRemoteVideoId(n.id) && !_entries.containsKey(n.id) && !(videos.placeOf(n.id)?.watched ?? false)) {
        next.add(DownloadItem.video(n));
      }
    }
    if (next.isNotEmpty) download(next, aheadQuality, origin: DownloadOrigin.ahead);
  }

  /// Episodes downloaded ahead go once they're watched (unless something keeps them).
  void _tidyAhead() {
    final gone = [
      for (final e in _entries.values)
        if (e.origin == DownloadOrigin.ahead && e.isDone && (videos.placeOf(e.id)?.watched ?? false)) e.id,
    ];
    if (gone.isEmpty) return;
    for (final id in gone) {
      final e = _entries.remove(id)!;
      _deleteFiles(e.file, e.subtitles);
    }
    notifyListeners();
    _saveSoon();
  }

  // ---- in the background (phones and TVs) ----

  /// HomeTunes went into the background ([on]) or came back. With "in the background" off,
  /// Keep offline and episodes-ahead downloads wait until it's back.
  Future<void> appInBackground(bool on) async {
    if (!android || background) {
      if (!on && _heldBack.isNotEmpty) await _releaseHeld();
      return;
    }
    if (on) {
      for (final e in [..._entries.values]) {
        if (e.origin == DownloadOrigin.manual || e.isDone || e.state == DownloadState.failed) continue;
        if (e.state == DownloadState.paused && !_heldBack.contains(e.id)) continue; // paused by the user
        _heldBack.add(e.id);
        if (_inEngine.contains(e.id)) {
          if (!await engine.pause(taskIdFor(e.id))) {
            _inEngine.remove(e.id);
            await engine.cancel(taskIdFor(e.id));
          }
        }
        _entries[e.id] = _entries[e.id]!.copyWith(state: DownloadState.paused);
      }
      notifyListeners();
    } else {
      await _releaseHeld();
    }
  }

  Future<void> _releaseHeld() async {
    for (final id in [..._heldBack]) {
      await resume(id);
    }
    _heldBack.clear();
  }

  void _sayBackground() {
    if (!android || !background || _backgroundNoticeShown) return;
    _backgroundNoticeShown = true;
    onNotice?.call('Downloads for things kept offline, and episodes downloaded ahead, carry on while '
        'HomeTunes is in the background. You can turn this off in Settings › Servers › Downloads.');
  }

  // ---- Make it mine ----

  /// The folders [e] could be copied into (your music, audiobook or video folders).
  List<String> foldersFor(DownloadEntry e) => e.kind == DownloadKind.video
      ? library.videoFolders
      : (e.book ? [...library.audiobookFolders, ...library.folders] : library.folders);

  /// Copies download [id] into [root] (one of your folders), so it becomes one of your own files
  /// there (and stops being a download); the folder is rescanned. For a video, where you got to
  /// comes with it. Returns the new file's path. Throws a [FileSystemException] when it can't be
  /// copied there.
  Future<String> makeItMine(String id, String root) async {
    final e = _entries[id];
    final f = e?.file;
    if (e == null || !e.isDone || f == null || !File(f).existsSync()) {
      throw const FileSystemException('That download isn\'t on this device.');
    }
    final ext = p.extension(f);
    String to;
    final subsTo = <(String, String)>[];
    if (e.kind == DownloadKind.video) {
      final v = videos.byId(id);
      final collection = _name(v?.collection ?? e.title);
      final parts = [
        root,
        if (v?.category != null) _name(v!.category!),
        collection,
        if (v?.season != null) v!.season == 0 ? 'Specials' : 'Season ${v.seasonLabel}',
      ];
      final base = v?.episodeLabel != null && v!.season != null && v.episode != null
          ? '$collection S${v.season.toString().padLeft(2, '0')}E${v.episode.toString().padLeft(2, '0')} - ${_name(v.title)}'
          : _name(e.title);
      to = p.joinAll([...parts, '$base$ext']);
      for (var i = 0; i < e.subtitles.length; i++) {
        final s = e.subtitles[i];
        if (s.isEmpty || !File(s).existsSync()) continue;
        final info = v != null && i < v.subtitles.length ? serverSubtitle(v.subtitles[i]) : null;
        final lang = languageCodeFor(info?.language ?? info?.label ?? '') ?? '$i';
        subsTo.add((s, p.joinAll([...parts, '$base.$lang${p.extension(s)}'])));
      }
    } else {
      final t = library.byId(id);
      final artist = _name(t?.albumArtist ?? 'Unknown Artist');
      final album = _name(t?.album ?? 'Unknown Album');
      final n = t?.trackNumber;
      to = p.join(root, artist, album, '${n == null ? '' : '${n.toString().padLeft(2, '0')} '}${_name(t?.title ?? e.title)}$ext');
    }
    if (File(to).existsSync()) to = '${p.withoutExtension(to)} (from server)$ext';
    await Directory(p.dirname(to)).create(recursive: true);
    await File(f).copy(to);
    for (final (from, dest) in subsTo) {
      try {
        await File(from).copy(dest);
      } catch (_) {}
    }
    // It's yours now: the download goes, and the folder is read again.
    _entries.remove(id);
    _deleteFiles(f, e.subtitles);
    notifyListeners();
    await _save();
    if (e.kind == DownloadKind.video) {
      await videos.scanFolder(root);
      videos.adoptPlace(id, VideoItem.idFor(to));
    } else {
      await library.scanFolder(root);
    }
    return to;
  }

  /// A name that's safe as a file or folder name on every system.
  static String _name(String s) {
    final t = s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final cut = t.length > 120 ? t.substring(0, 120).trim() : t;
    final noDots = cut.replaceAll(RegExp(r'[. ]+$'), '');
    return noDots.isEmpty ? 'Untitled' : noDots;
  }

  // ---- for the Downloads page ----

  /// A line about where [e] has got to.
  String statusOf(DownloadEntry e) {
    String size(int b) => fileSizeText(b);
    switch (e.state) {
      case DownloadState.done:
        return [size(e.bytes), e.quality.label, if (e.origin == DownloadOrigin.ahead) 'Downloaded ahead',
          if (e.origin == DownloadOrigin.keep) 'Kept offline'].join(' · ');
      case DownloadState.queued:
        if (android && wifiOnly && onWifi == false) return 'Waiting for Wi-Fi';
        return _inEngine.contains(e.id) || !_started ? 'Waiting' : 'Getting ready';
      case DownloadState.running:
        final pct = (e.progress * 100).clamp(0, 100).round();
        return e.expected != null && e.expected! > 0
            ? 'Downloading $pct% · ${size(e.bytes)} of ${size(e.expected!)}'
            : 'Downloading · ${size(e.bytes)}';
      case DownloadState.paused:
        return _heldBack.contains(e.id) ? 'Paused while HomeTunes is in the background' : 'Paused';
      case DownloadState.noRoom:
        return 'Waiting for room: the space for downloads is full';
      case DownloadState.failed:
        return 'Couldn\'t download: ${e.error ?? 'something went wrong'}';
    }
  }

  bool _disposed = false;

  // A download can finish (or a timer fire) just after the model has gone: nothing to tell.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _wifiSub?.cancel();
    _saveTimer?.cancel();
    _syncTimer?.cancel();
    _notifyTimer?.cancel();
    library.removeListener(_soon);
    playlists.removeListener(_soon);
    videos.removeListener(_soon);
    if (library.downloadedFile == fileFor) library.downloadedFile = null;
    if (videos.downloadedCopy == copyOf) videos.downloadedCopy = null;
    if (videos.onServerVideoStarted == _downloadAhead) videos.onServerVideoStarted = null;
    MediaSources.downloaded = (_) => false;
    super.dispose();
  }
}

/// "1.4 GB", "120 MB", "800 KB".
String fileSizeText(int bytes) {
  if (bytes >= 1000 * 1000 * 1000) return '${(bytes / 1e9).toStringAsFixed(bytes >= 10e9 ? 0 : 1)} GB';
  if (bytes >= 1000 * 1000) return '${(bytes / 1e6).toStringAsFixed(bytes >= 100e6 ? 0 : 1)} MB';
  return '${bytes <= 0 ? 0 : math.max(1, (bytes / 1e3).round())} KB';
}

/// The app's sources: the music server (LibraryModel) for songs and audiobooks, the Jellyfin
/// servers (ServerVideosModel) for videos.
class AppDownloadSources implements DownloadSources {
  AppDownloadSources(this.library, this.videos, this.serverVideos);
  final LibraryModel library;
  final VideoLibraryModel videos;
  final ServerVideosModel? serverVideos;

  @override
  Future<DownloadRequest?> request(DownloadEntry e) async {
    if (e.kind == DownloadKind.video) {
      final v = videos.byId(e.id);
      final jf = serverVideos;
      if (v == null || jf == null) return null;
      return jf.downloadRequest(v, maxHeight: e.quality.limit);
    }
    final t = library.byId(e.id);
    if (t == null) return null;
    final url = library.serverDownloadUrl(t, kbps: e.quality.limit);
    if (url == null) return null;
    return (url: url, headers: const <String, String>{}, ext: e.quality.isOriginal ? '' : 'mp3', subtitles: const <({String url, String format})>[]);
  }

  @override
  String? problem(DownloadEntry e) {
    if (e.kind == DownloadKind.video) {
      final v = videos.byId(e.id);
      if (v == null) return 'This video isn\'t on the server any more.';
      return videos.problemWith(v);
    }
    if (library.byId(e.id) == null) return 'This song isn\'t on the server any more.';
    return 'The music server isn\'t connected (Settings › Servers).';
  }
}
