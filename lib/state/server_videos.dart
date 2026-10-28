// Videos from Jellyfin servers (0.2.1): signs in, reads the server's video libraries into the
// Videos tab, plays from it and keeps where you got to the same on both sides.
//
// The user asked (25 Oct 2026) for HomeTunes to "actually support Jellyfin" for streaming; they
// chose videos now (music and audiobooks later) and progress synced both ways. Every Jellyfin
// server in Settings › Servers that's switched on for Videos is read:
//   - Signing in uses the user name and password saved for it (ServersModel keeps the password in
//     protected storage). The server's access token goes there too, under its own key, never into
//     a file or a backup; when the server stops accepting it, HomeTunes signs in again once.
//   - Its libraries of films, series and home videos become VideoItems (ids `jf:<server>:<item>`,
//     see remote_videos.dart): a series is a collection with its seasons and episodes, a film is
//     its own collection, as local ones are. Their pictures are downloaded into
//     <data>/art/server-video/<server>/ (so the tab works without the server, and the media
//     controls never get an address). What was read is kept in server_videos.json, so the tab
//     isn't empty when the server is off.
//   - Where you got to: the server's (its UserData) is used when it's newer than HomeTunes' own;
//     while playing, the server is told it started, where it's got to (every 10 s or on pause)
//     and that it stopped; marking watched / not watched is sent too. Anything that couldn't be
//     sent (the server was off) waits and is sent at the next sync.
// Libraries can be left out one by one (Settings › Servers › a server's ⋮ › Libraries…).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/video_item.dart';
import '../services/jellyfin_client.dart';
import '../services/secret_store.dart';
import '../services/server_probe.dart' show candidateUrls;
import '../services/storage.dart';
import '../services/subsonic_client.dart' show isPlainHttpToInternet;
import 'remote_videos.dart';
import 'servers_model.dart';
import 'video_library_model.dart';

/// What HomeTunes remembers about one Jellyfin server (never its token or password).
class _ServerState {
  /// The address that worked (with its scheme), and the user it signed in as.
  String? base;
  String? userId;

  /// The libraries it has that hold videos, and the ones the user left out.
  List<JellyfinView> views = [];
  Set<String> hidden = {};

  /// When it last synced, and how many videos it gave.
  int? syncedMs;
  int count = 0;

  /// What went wrong last time, or null.
  String? error;

  /// What's happening now ("Reading Films 40 / 200"), or null.
  String? status;

  /// The videos as last read (also given to VideoLibraryModel).
  List<VideoItem> videos = [];

  /// Places and watched marks not sent yet, by item id: {positionMs, watched, updatedMs}.
  Map<String, Map<String, Object>> pending = {};

  Map<String, dynamic> toJson() => {
        if (base != null) 'base': base,
        if (userId != null) 'userId': userId,
        'views': [for (final v in views) v.toJson()],
        if (hidden.isNotEmpty) 'hidden': hidden.toList()..sort(),
        if (syncedMs != null) 'syncedMs': syncedMs,
        'videos': [for (final v in videos) v.toJson()],
        if (pending.isNotEmpty) 'pending': pending,
      };

  static _ServerState fromJson(Object? j) {
    final s = _ServerState();
    if (j is! Map) return s;
    s.base = j['base'] as String?;
    s.userId = j['userId'] as String?;
    s.views = [for (final v in (j['views'] is List ? j['views'] as List : const [])) ?JellyfinView.fromJson(v)];
    s.hidden = {for (final h in (j['hidden'] is List ? j['hidden'] as List : const [])) if (h is String) h};
    s.syncedMs = j['syncedMs'] as int?;
    for (final v in (j['videos'] is List ? j['videos'] as List : const [])) {
      try {
        final item = VideoItem.fromJson(Map<String, dynamic>.from(v as Map));
        if (isRemoteVideoId(item.id)) s.videos.add(item);
      } catch (_) {}
    }
    s.count = s.videos.length;
    final pend = j['pending'];
    if (pend is Map) {
      for (final e in pend.entries) {
        if (e.key is String && e.value is Map) {
          s.pending[e.key as String] = {
            for (final x in (e.value as Map).entries)
              if (x.key is String && (x.value is int || x.value is bool)) x.key as String: x.value as Object,
          };
        }
      }
    }
    return s;
  }
}

class ServerVideosModel extends ChangeNotifier implements RemoteVideoSource {
  ServerVideosModel({
    required this.storage,
    required this.servers,
    required this.videos,
    SecretStore? secrets,
    this.appVersion = '0',
    http.Client Function()? httpClient,
    String? deviceName,
  })  : secrets = secrets ?? servers.secrets,
        _makeHttp = httpClient,
        deviceName = deviceName ?? _thisDevice() {
    _known = {for (final s in servers.all) s.id: s};
    servers.addListener(_onServers);
    videos.remote = this;
  }

  final Storage storage;
  final ServersModel servers;
  final VideoLibraryModel videos;
  final SecretStore? secrets;
  final String appVersion;
  final String deviceName;
  final http.Client Function()? _makeHttp;

  static const fileName = 'server_videos.json';

  /// The types of item read as videos.
  static const videoTypes = ['Movie', 'Episode', 'Video'];

  /// How often the servers are read again while HomeTunes is open.
  static const resyncEvery = Duration(minutes: 30);

  /// Where it's got to is sent at most this often while playing (and on every pause).
  static const progressEvery = Duration(seconds: 10);

  /// The picture sizes asked for: a video's own (wide) and a collection's poster.
  static const thumbWidth = 640, posterWidth = 500;

  static String _thisDevice() {
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty && host.toLowerCase() != 'localhost') return host;
    } catch (_) {}
    return Platform.isAndroid ? 'Android' : Platform.operatingSystem;
  }

  /// This install's id for the servers (made once, kept in server_videos.json).
  String deviceId = '';

  final Map<String, _ServerState> _state = {};
  final Map<String, JellyfinClient> _clients = {};
  final Map<String, Future<void>> _syncing = {};
  Map<String, ServerEntry> _known = {};
  Timer? _resync;
  bool _disposed = false;

  /// For tests: the clock.
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  // ---- which servers ----

  static bool _isVideoServer(ServerEntry s) => s.type == ServerType.jellyfin && s.uses.contains(MediaKind.videos);

  /// The Jellyfin servers switched on for videos.
  List<ServerEntry> get videoServers => [for (final s in servers.all) if (_isVideoServer(s)) s];

  _ServerState _of(String id) => _state[id] ??= _ServerState();

  /// The key the server's token is kept under in protected storage.
  static String tokenKey(ServerEntry s) => 'jellyfin-token:${s.username.trim()}@${s.url.trim().toLowerCase()}';

  // ---- status, for Settings › Servers ----

  /// Whether this server is being read now.
  bool isSyncing(ServerEntry s) => _syncing.containsKey(s.id);

  /// A line about how the server is doing ("Signed in · 245 videos · read 5 min ago").
  String statusFor(ServerEntry s) {
    final st = _state[s.id];
    if (!s.uses.contains(MediaKind.videos)) return 'Switch it on to show its videos in the Videos tab.';
    if (st == null) return 'Not read yet.';
    if (st.status != null) return st.status!;
    if (st.error != null) return st.error!;
    if (st.syncedMs == null) return 'Not read yet.';
    final hidden = st.hidden.isEmpty ? '' : ' · ${st.hidden.length} ${st.hidden.length == 1 ? 'library' : 'libraries'} left out';
    return 'Signed in as ${s.username} · ${st.count} ${st.count == 1 ? 'video' : 'videos'}$hidden · read ${_ago(st.syncedMs!)}';
  }

  /// Green (fine), red (a problem) or no dot.
  bool? okFor(ServerEntry s) {
    final st = _state[s.id];
    if (st == null || st.status != null || !s.uses.contains(MediaKind.videos)) return null;
    if (st.error != null) return false;
    return st.syncedMs == null ? null : true;
  }

  String _ago(int ms) {
    final d = Duration(milliseconds: max(0, now() - ms));
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'} ago';
  }

  /// The server's video libraries (as last read).
  List<JellyfinView> librariesOf(ServerEntry s) => List.unmodifiable(_state[s.id]?.views ?? const <JellyfinView>[]);

  bool isLibraryShown(ServerEntry s, String viewId) => !(_state[s.id]?.hidden.contains(viewId) ?? false);

  /// Shows or leaves out one of the server's libraries; the server is read again.
  Future<void> setLibraryShown(ServerEntry s, String viewId, bool shown) async {
    final st = _of(s.id);
    shown ? st.hidden.remove(viewId) : st.hidden.add(viewId);
    notifyListeners();
    await _save();
    await sync(s);
  }

  // ---- loading and saving ----

  Future<void> load() async {
    final j = await storage.read(fileName);
    if (j is Map) {
      deviceId = j['deviceId'] is String ? j['deviceId'] as String : '';
      final list = j['servers'];
      if (list is Map) {
        for (final e in list.entries) {
          if (e.key is String) _state[e.key as String] = _ServerState.fromJson(e.value);
        }
      }
    }
    if (deviceId.isEmpty) {
      final r = Random.secure();
      deviceId = 'hometunes-${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      await _save();
    }
    // Servers that went while HomeTunes was closed are forgotten; the rest show at once.
    _state.removeWhere((id, _) => servers.byId(id)?.type != ServerType.jellyfin);
    for (final s in videoServers) {
      final st = _state[s.id];
      if (st != null && st.videos.isNotEmpty) videos.setServerVideos(s.id, st.videos);
    }
    _known = {for (final s in servers.all) s.id: s};
    notifyListeners();
  }

  Future<void> _save() => storage.write(fileName, {
        'deviceId': deviceId,
        'servers': {for (final e in _state.entries) e.key: e.value.toJson()},
      });

  /// Reads every video server now, then again every [resyncEvery] while HomeTunes is open.
  void start() {
    unawaited(syncAll());
    _resync?.cancel();
    _resync = Timer.periodic(resyncEvery, (_) => syncAll());
  }

  /// Reads every Jellyfin server that's switched on for videos.
  Future<void> syncAll() => Future.wait([for (final s in videoServers) sync(s)]);

  // ---- following Settings › Servers ----

  void _onServers() {
    final now = {for (final s in servers.all) s.id: s};
    for (final old in _known.values) {
      if (old.type != ServerType.jellyfin) continue;
      final cur = now[old.id];
      if (cur == null || cur.type != ServerType.jellyfin) {
        // Removed: its videos, places, pictures and sign-in go.
        unawaited(_forget(old, removed: true));
        continue;
      }
      final moved = cur.url.trim().toLowerCase() != old.url.trim().toLowerCase() || cur.username.trim() != old.username.trim();
      if (moved) {
        // Another address or user: sign in again.
        _clients.remove(cur.id)?.close();
        unawaited(secrets?.delete(tokenKey(old)));
        final st = _of(cur.id);
        st.base = null;
        st.userId = null;
        if (_isVideoServer(cur)) unawaited(sync(cur));
      } else if (_isVideoServer(cur) && !_isVideoServer(old)) {
        unawaited(sync(cur));
      } else if (!_isVideoServer(cur) && _isVideoServer(old)) {
        // Switched off for videos: they leave the Videos tab (their places stay, for switching back).
        videos.removeServerVideos(cur.id);
        notifyListeners();
      }
    }
    for (final cur in now.values) {
      if (!_known.containsKey(cur.id) && _isVideoServer(cur)) unawaited(sync(cur));
    }
    _known = now;
  }

  /// Signs out of [s] on this device: its token is forgotten (the next read signs in again with
  /// the saved password). Its videos stay.
  Future<void> signOut(ServerEntry s) async {
    final c = _clients.remove(s.id);
    await c?.signOut();
    c?.close();
    await secrets?.delete(tokenKey(s));
    final st = _of(s.id);
    st.userId = null;
    st.error = 'Signed out. Use Sync now to sign in again.';
    notifyListeners();
    await _save();
  }

  Future<void> _forget(ServerEntry s, {bool removed = false}) async {
    final c = _clients.remove(s.id);
    if (removed) await c?.signOut();
    c?.close();
    await secrets?.delete(tokenKey(s));
    _state.remove(s.id);
    videos.removeServerVideos(s.id, forget: removed);
    try {
      final dir = Directory(_pictureDir(s.id));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    notifyListeners();
    await _save();
  }

  // ---- signing in ----

  http.Client? _http() => _makeHttp?.call();

  JellyfinClient _newClient(String base, {String? token, String? userId}) => JellyfinClient(
        baseUrl: base,
        deviceId: deviceId,
        deviceName: deviceName,
        appVersion: appVersion,
        token: token,
        userId: userId,
        httpClient: _http(),
      );

  /// A client signed in to [s]: the saved token if there is one, else a new sign-in with the
  /// saved password. Throws [JellyfinException] with a sentence for the user.
  Future<JellyfinClient> _signedIn(ServerEntry s, {bool fresh = false}) async {
    final st = _of(s.id);
    if (!fresh) {
      final c = _clients[s.id];
      if (c != null && c.token != null) return c;
      final token = await secrets?.read(tokenKey(s));
      if (token != null && st.base != null && st.userId != null) {
        return _clients[s.id] = _newClient(st.base!, token: token, userId: st.userId);
      }
    }
    _clients.remove(s.id)?.close();
    if (s.username.trim().isEmpty) {
      throw const JellyfinException('Add the user name and password for this server with Edit… to sign in.');
    }
    final password = await servers.passwordOf(s);
    JellyfinException? last;
    for (final base in candidateUrls(s.url)) {
      // The password never goes over plain http to an address on the internet.
      if (base.startsWith('http://') && isPlainHttpToInternet(base)) {
        last ??= const JellyfinException(
          'HomeTunes won\'t send your password over plain http to an address on the internet. '
          'Use https, or connect over your home network or Tailscale.',
        );
        continue;
      }
      final c = _newClient(base);
      try {
        final r = await c.signIn(s.username.trim(), password);
        st.base = base;
        st.userId = r.userId;
        await secrets?.write(tokenKey(s), r.token);
        await _save();
        return _clients[s.id] = c;
      } on JellyfinException catch (e) {
        c.close();
        last = e;
        if (e.fromServer) break; // a real answer (wrong password): no point trying http as well
      }
    }
    throw last ?? const JellyfinException('Couldn\'t reach the server.');
  }

  // ---- reading the server ----

  /// Reads [s]'s video libraries into the Videos tab (once at a time; a second call waits for
  /// the first).
  Future<void> sync(ServerEntry s) {
    final running = _syncing[s.id];
    if (running != null) return running;
    final job = _sync(s);
    _syncing[s.id] = job;
    job.whenComplete(() {
      _syncing.remove(s.id);
      if (!_disposed) notifyListeners();
    });
    return job;
  }

  Future<void> _sync(ServerEntry s) async {
    final st = _of(s.id);
    st.error = null;
    st.status = 'Signing in…';
    notifyListeners();
    try {
      JellyfinClient c;
      List<JellyfinView> views;
      try {
        c = await _signedIn(s);
        views = await c.views();
      } on JellyfinException catch (e) {
        if (!e.signedOut) rethrow;
        // The token stopped working (signed out on the server): sign in again, once.
        await secrets?.delete(tokenKey(s));
        c = await _signedIn(s, fresh: true);
        views = await c.views();
      }
      await _sendPending(s, c);
      st.views = [for (final v in views) if (v.holdsVideos) v];
      final shown = [for (final v in st.views) if (!st.hidden.contains(v.id)) v];
      final found = <VideoItem>[];
      final places = <String, VideoPlace>{};
      final pictures = <ServerPicture>[];
      for (final view in shown) {
        st.status = 'Reading ${view.name}…';
        notifyListeners();
        final series = <String, Map<String, dynamic>>{};
        if (view.collectionType != 'movies' && view.collectionType != 'homevideos') {
          for (final x in await c.items(
            parentId: view.id,
            types: const ['Series'],
            fields: const ['Overview', 'Genres', 'ProductionYear'],
          )) {
            if (x['Id'] is String) series[x['Id'] as String] = x;
          }
        }
        final items = await c.items(
          parentId: view.id,
          types: videoTypes,
          onProgress: (done, total) {
            st.status = 'Reading ${view.name} $done / $total';
            notifyListeners();
          },
        );
        for (final j in items) {
          final made = videoFromJellyfin(j, serverKey: s.id, view: view, series: series, pictureDir: _pictureDir(s.id));
          if (made == null) continue;
          found.add(made.video);
          pictures.addAll(made.pictures);
          final place = placeFromJellyfin(j['UserData']);
          if (place != null) places[made.video.id] = place;
        }
      }
      // The same item can be in two libraries (a "mixed" one and a films one): once each.
      final seen = <String>{};
      final unique = [for (final v in found) if (seen.add(v.id)) v];
      st.videos = unique;
      st.count = unique.length;
      st.syncedMs = now();
      st.status = null;
      st.error = null;
      if (_isVideoServer(servers.byId(s.id) ?? s)) videos.setServerVideos(s.id, unique, places: places);
      await _save();
      notifyListeners();
      await _fetchPictures(s, c, pictures);
    } on JellyfinException catch (e) {
      st.status = null;
      st.error = 'Couldn\'t read it: ${e.message}';
    } catch (e) {
      st.status = null;
      st.error = 'Couldn\'t read it: ${hidePath('$e')}';
    }
    notifyListeners();
  }

  /// Error text without addresses' query strings.
  static String hidePath(String s) => s.replaceAll(RegExp(r'\?[^\s)]*'), '');

  // ---- pictures ----

  String _pictureDir(String serverKey) => p.join(storage.artDir, 'server-video', serverKey);

  Future<void> _fetchPictures(ServerEntry s, JellyfinClient c, List<ServerPicture> jobs) async {
    final st = _of(s.id);
    final wanted = <String>{};
    var got = 0;
    final missing = <String, ServerPicture>{};
    for (final j in jobs) {
      wanted.add(p.normalize(j.file));
      if (!File(j.file).existsSync()) missing[j.file] = j;
    }
    var tried = 0;
    for (final j in missing.values) {
      if (_disposed || _state[s.id] != st) return;
      if (tried++ % 10 == 0) {
        st.status = 'Getting pictures $tried / ${missing.length}';
        notifyListeners();
      }
      final bytes = await c.imageBytes(c.imageUri(j.itemId, j.type, tag: j.tag, maxWidth: j.width));
      if (bytes == null) continue;
      try {
        await Directory(p.dirname(j.file)).create(recursive: true);
        final tmp = File('${j.file}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(j.file);
        got++;
      } catch (_) {
        continue;
      }
      // Show pictures as they arrive, a batch at a time.
      if (got % 12 == 0) _applyPictures(s, jobs);
    }
    if (got > 0) _applyPictures(s, jobs);
    if (st.status != null) {
      st.status = null;
      notifyListeners();
    }
    // Pictures no longer used go.
    try {
      final dir = Directory(_pictureDir(s.id));
      if (await dir.exists()) {
        await for (final e in dir.list()) {
          if (e is File && !wanted.contains(p.normalize(e.path))) {
            try {
              await e.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// Puts the downloaded pictures on the videos.
  void _applyPictures(ServerEntry s, List<ServerPicture> jobs) {
    final st = _of(s.id);
    final thumbs = <String, String>{}, covers = <String, String>{};
    for (final j in jobs) {
      if (!File(j.file).existsSync()) continue;
      (j.cover ? covers : thumbs)[j.videoId] = j.file;
    }
    st.videos = [
      for (final v in st.videos)
        if (thumbs[v.id] != null || covers[v.id] != null) v.withPictures(thumb: thumbs[v.id], cover: covers[v.id]) else v,
    ];
    if (_isVideoServer(servers.byId(s.id) ?? s)) videos.setServerVideos(s.id, st.videos);
    unawaited(_save());
  }

  // ---- playing (RemoteVideoSource) ----

  final Map<String, String> _problems = {};

  @override
  String? serverNameOf(VideoItem v) {
    final key = remoteServerOf(v.id);
    return key == null ? null : servers.byId(key)?.name;
  }

  @override
  String? problemFor(VideoItem v) => _problems[v.id];

  @override
  Future<VideoAddress?> streamFor(VideoItem v, {bool converted = false, Duration? start}) async {
    final key = remoteServerOf(v.id), item = remoteItemOf(v.id);
    final s = key == null ? null : servers.byId(key);
    if (s == null || item == null) {
      _problems[v.id] = 'The server this video was on has been removed from Settings › Servers.';
      return null;
    }
    if (!s.uses.contains(MediaKind.videos)) {
      _problems[v.id] = '${s.name} is switched off for videos in Settings › Servers.';
      return null;
    }
    JellyfinClient c;
    try {
      c = await _signedIn(s);
    } on JellyfinException catch (e) {
      _problems[v.id] = 'Can\'t play this from ${s.name}: ${e.message}';
      return null;
    }
    _problems.remove(v.id);
    final ext = p.extension(v.path).replaceFirst('.', '');
    final uri = converted
        ? c.convertedUri(item, maxHeight: 1080, start: start, playSessionId: _playSession(v.id))
        : c.streamUri(item, container: ext.isEmpty ? null : ext);
    return VideoAddress(
      uri.toString(),
      headers: c.mediaHeaders,
      remote: true,
      converted: converted,
      startsAt: converted ? start : null,
      subtitles: [
        for (final sub in v.subtitles)
          if (serverSubtitle(sub) case final t?)
            (uri: c.subtitleUri(item, t.index, t.format).toString(), label: t.label, language: t.language),
      ],
    );
  }

  /// Where to download [v] from (0.2.3): the original file, or with [maxHeight] a smaller copy
  /// the server converts; the sign-in goes in the headers. Also its subtitle files. Null when the
  /// server can't be signed in to ([problemFor] says why).
  Future<({String url, Map<String, String> headers, String ext, List<({String url, String format})> subtitles})?>
      downloadRequest(VideoItem v, {int? maxHeight}) async {
    final key = remoteServerOf(v.id), item = remoteItemOf(v.id);
    final s = key == null ? null : servers.byId(key);
    if (s == null || item == null) {
      _problems[v.id] = 'The server this video was on has been removed from Settings › Servers.';
      return null;
    }
    JellyfinClient c;
    try {
      c = await _signedIn(s);
    } on JellyfinException catch (e) {
      _problems[v.id] = 'Can\'t download this from ${s.name}: ${e.message}';
      return null;
    }
    final ext = maxHeight == null ? p.extension(v.path).replaceFirst('.', '') : 'mkv';
    return (
      url: (maxHeight == null ? c.downloadUri(item) : c.convertedUri(item, maxHeight: maxHeight)).toString(),
      headers: c.mediaHeaders,
      ext: ext.isEmpty ? 'mkv' : ext,
      subtitles: [
        for (final sub in v.subtitles)
          if (serverSubtitle(sub) case final t?) (url: c.subtitleUri(item, t.index, t.format).toString(), format: t.format),
      ],
    );
  }

  // One play session per video opened, so the server can tell them apart.
  final Map<String, String> _sessions = {};
  String _playSession(String id) => _sessions[id] ??= '${deviceId.hashCode.toRadixString(16)}${now().toRadixString(16)}';

  // When each video last told the server where it was, and whether it was paused then.
  final Map<String, (int, bool)> _lastProgress = {};

  @override
  void started(VideoItem v, Duration at, {bool converted = false}) {
    _sessions.remove(v.id);
    _lastProgress[v.id] = (now(), false);
    _tell(v, (c, item) => c.reportStart(item, at, playSessionId: _playSession(v.id), converted: converted));
  }

  @override
  void progress(VideoItem v, Duration at, Duration length, {required bool paused}) {
    final last = _lastProgress[v.id];
    final t = now();
    if (last != null && last.$2 == paused && t - last.$1 < progressEvery.inMilliseconds) return;
    _lastProgress[v.id] = (t, paused);
    _tell(
      v,
      (c, item) => c.reportProgress(item, at, paused: paused, playSessionId: _playSession(v.id)),
      // If it can't be sent, the place is sent at the next sync.
      orLater: {'positionMs': at.inMilliseconds, 'watched': false, 'updatedMs': t},
    );
  }

  @override
  void stopped(VideoItem v, Duration at, Duration length) {
    _lastProgress.remove(v.id);
    final watched = videos.placeOf(v.id)?.watched ?? false;
    final t = now();
    _tell(
      v,
      (c, item) async {
        await c.reportStopped(item, at, playSessionId: _playSession(v.id));
        // HomeTunes' own idea of "near the end" decides watched, so both agree.
        if (watched) await c.setPlayed(item, true);
      },
      orLater: {'positionMs': at.inMilliseconds, 'watched': watched, 'updatedMs': t},
    );
    _sessions.remove(v.id);
  }

  @override
  void watchedChanged(Iterable<VideoItem> list, bool watched) {
    final t = now();
    for (final v in list) {
      _tell(
        v,
        (c, item) async {
          await c.setPlayed(item, watched);
          if (!watched) await c.setPlace(item, position: Duration.zero, played: false);
        },
        orLater: {'positionMs': 0, 'watched': watched, 'updatedMs': t},
      );
    }
  }

  /// Sends something to [v]'s server in the background. If it can't be sent and [orLater] is
  /// given, it's kept and sent at the next sync.
  void _tell(VideoItem v, Future<void> Function(JellyfinClient c, String item) send, {Map<String, Object>? orLater}) {
    final key = remoteServerOf(v.id), item = remoteItemOf(v.id);
    final s = key == null ? null : servers.byId(key);
    if (s == null || item == null) return;
    unawaited(() async {
      try {
        final c = await _signedIn(s);
        await send(c, item);
        if (_state[s.id]?.pending.remove(item) != null) await _save();
      } catch (_) {
        if (orLater == null) return;
        _of(s.id).pending[item] = orLater;
        await _save();
      }
    }());
  }

  /// Sends places and watched marks that couldn't be sent before (watched while the server was off).
  Future<void> _sendPending(ServerEntry s, JellyfinClient c) async {
    final st = _of(s.id);
    if (st.pending.isEmpty) return;
    for (final e in Map.of(st.pending).entries) {
      final ms = e.value['updatedMs'];
      try {
        await c.setPlace(
          e.key,
          position: Duration(milliseconds: (e.value['positionMs'] as int?) ?? 0),
          played: e.value['watched'] == true,
          when: ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
        );
        st.pending.remove(e.key);
      } on JellyfinException catch (x) {
        // Gone from the server: nothing to send it to.
        if (x.status == 404 || x.status == 400) st.pending.remove(e.key);
        if (!x.fromServer) break;
      }
    }
    await _save();
  }

  @override
  void dispose() {
    _disposed = true;
    _resync?.cancel();
    servers.removeListener(_onServers);
    if (identical(videos.remote, this)) videos.remote = null;
    for (final c in _clients.values) {
      c.close();
    }
    super.dispose();
  }
}

/// A picture to download for a server video.
class ServerPicture {
  final String videoId, itemId, type, file;
  final String? tag;
  final int width;

  /// The collection's poster, rather than the video's own picture.
  final bool cover;
  const ServerPicture(this.videoId, this.itemId, this.type, this.tag, this.file, this.width, {this.cover = false});
}

/// A subtitle file the server keeps beside a video, as kept in [VideoItem.subtitles].
({int index, String format, String label, String? language})? serverSubtitle(String s) {
  if (!s.startsWith('jfsub:')) return null;
  try {
    final j = jsonDecode(s.substring(6));
    if (j is! Map || j['i'] is! int || j['f'] is! String) return null;
    return (index: j['i'] as int, format: j['f'] as String, label: (j['t'] as String?) ?? 'Subtitles', language: j['l'] as String?);
  } catch (_) {
    return null;
  }
}

/// The file format to ask for a text subtitle in, from Jellyfin's codec name (null: a picture
/// subtitle, which can't be fetched on its own).
String? _subtitleFormat(Object? codec) => switch ('$codec'.toLowerCase()) {
      'srt' || 'subrip' => 'srt',
      'ass' => 'ass',
      'ssa' => 'ssa',
      'vtt' || 'webvtt' => 'vtt',
      _ => null,
    };

/// Where the server says you got to in an item, from its UserData; null when you haven't
/// started it there.
VideoPlace? placeFromJellyfin(Object? userData) {
  if (userData is! Map) return null;
  final position = durationOfTicks(userData['PlaybackPositionTicks']);
  final played = userData['Played'] == true;
  final last = userData['LastPlayedDate'] is String ? DateTime.tryParse(userData['LastPlayedDate'] as String) : null;
  if (!played && position <= Duration.zero) return null;
  // With no date, the server's mark counts as older than anything HomeTunes has.
  return VideoPlace(position: position, watched: played, updatedMs: last?.millisecondsSinceEpoch ?? 1);
}

/// "Season 3" and "Specials" are what the season number already says.
String? _seasonTitle(Object? name) {
  if (name is! String) return null;
  final n = name.trim();
  if (n.isEmpty || RegExp(r'^(season|series|staffel|saison|temporada)\s*\d+$', caseSensitive: false).hasMatch(n)) return null;
  if (n.toLowerCase() == 'specials') return null;
  return n;
}

/// One Jellyfin item as a video, with the pictures to download for it; null when it isn't one.
@visibleForTesting
({VideoItem video, List<ServerPicture> pictures})? videoFromJellyfin(
  Map<String, dynamic> j, {
  required String serverKey,
  required JellyfinView view,
  Map<String, Map<String, dynamic>> series = const {},
  required String pictureDir,
}) {
  final itemId = j['Id'];
  final type = j['Type'];
  if (itemId is! String || type is! String || !ServerVideosModel.videoTypes.contains(type)) return null;
  final id = 'jf:$serverKey:$itemId';
  final name = (j['Name'] as String?)?.trim();
  final sources = j['MediaSources'] is List ? j['MediaSources'] as List : const [];
  final source = sources.isNotEmpty && sources.first is Map ? sources.first as Map : const {};
  var container = (source['Container'] ?? j['Container'] ?? 'mkv').toString().split(',').first.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9]{1,8}$').hasMatch(container)) container = 'mkv';
  final episode = type == 'Episode';
  final seriesId = j['SeriesId'] as String?;
  final show = seriesId == null ? null : series[seriesId];
  final genres = j['Genres'] is List ? (j['Genres'] as List).whereType<String>().toList() : const <String>[];
  final showGenres = show?['Genres'] is List ? (show!['Genres'] as List).whereType<String>().toList() : const <String>[];
  final added = j['DateCreated'] is String ? DateTime.tryParse(j['DateCreated'] as String) : null;
  final collection = episode
      ? ((j['SeriesName'] as String?)?.trim().isNotEmpty ?? false ? (j['SeriesName'] as String).trim() : (name ?? 'Series'))
      : type == 'Movie'
          ? (name ?? 'Film')
          : (view.name.isEmpty ? 'Home videos' : view.name);
  final category = switch (view.collectionType) {
    'tvshows' => 'TV',
    'movies' => 'Films',
    _ => episode ? 'TV' : (type == 'Movie' ? 'Films' : null),
  };
  final subtitles = <String>[];
  final streams = source['MediaStreams'] is List ? source['MediaStreams'] as List : const [];
  for (final st in streams) {
    if (st is! Map || st['Type'] != 'Subtitle' || st['IsExternal'] != true || st['Index'] is! int) continue;
    final format = _subtitleFormat(st['Codec']);
    if (format == null) continue;
    final label = (st['DisplayTitle'] ?? st['Title'] ?? st['Language'] ?? 'Subtitles').toString();
    subtitles.add('jfsub:${jsonEncode({'i': st['Index'], 'f': format, 't': label, if (st['Language'] is String) 'l': st['Language']})}');
  }

  // Pictures: the video's own (an episode's still, a film's wide picture) and the collection's
  // poster (the series', or the film's own).
  final tags = j['ImageTags'] is Map ? j['ImageTags'] as Map : const {};
  final backdrops = j['BackdropImageTags'] is List ? j['BackdropImageTags'] as List : const [];
  final jobs = <ServerPicture>[];
  String file(String item, String kind, String? tag) =>
      p.join(pictureDir, '$item-$kind-${(tag ?? 'x').replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}.jpg');
  void add(String item, String kind, String? tag, int width, {bool cover = false}) =>
      jobs.add(ServerPicture(id, item, kind, tag, file(item, kind, tag), width, cover: cover));
  if (episode) {
    if (tags['Primary'] is String) add(itemId, 'Primary', tags['Primary'] as String, ServerVideosModel.thumbWidth);
    if (seriesId != null && j['SeriesPrimaryImageTag'] is String) {
      add(seriesId, 'Primary', j['SeriesPrimaryImageTag'] as String, ServerVideosModel.posterWidth, cover: true);
    }
  } else {
    if (tags['Thumb'] is String) {
      add(itemId, 'Thumb', tags['Thumb'] as String, ServerVideosModel.thumbWidth);
    } else if (backdrops.isNotEmpty && backdrops.first is String) {
      add(itemId, 'Backdrop', backdrops.first as String, ServerVideosModel.thumbWidth);
    } else if (tags['Primary'] is String) {
      add(itemId, 'Primary', tags['Primary'] as String, ServerVideosModel.thumbWidth);
    }
    if (tags['Primary'] is String) add(itemId, 'Primary', tags['Primary'] as String, ServerVideosModel.posterWidth, cover: true);
  }
  String? have(bool cover) {
    for (final x in jobs) {
      if (x.cover == cover && File(x.file).existsSync()) return x.file;
    }
    return null;
  }

  final video = VideoItem(
    id: id,
    path: 'jellyfin://$serverKey/$itemId.$container',
    title: name == null || name.isEmpty ? 'Video' : name,
    collection: collection,
    category: category,
    season: episode && j['ParentIndexNumber'] is int ? j['ParentIndexNumber'] as int : null,
    episode: episode && j['IndexNumber'] is int ? j['IndexNumber'] as int : null,
    seasonTitle: episode ? _seasonTitle(j['SeasonName']) : null,
    year: j['ProductionYear'] is int ? j['ProductionYear'] as int : (show?['ProductionYear'] as int?),
    genre: genres.isNotEmpty ? genres.first : (showGenres.isNotEmpty ? showGenres.first : null),
    description: (j['Overview'] as String?)?.trim().isEmpty ?? true ? null : (j['Overview'] as String).trim(),
    duration: durationOfTicks(j['RunTimeTicks']),
    width: j['Width'] is int && (j['Width'] as int) > 0 ? j['Width'] as int : null,
    height: j['Height'] is int && (j['Height'] as int) > 0 ? j['Height'] as int : null,
    sizeBytes: source['Size'] is int ? source['Size'] as int : null,
    addedMs: added?.millisecondsSinceEpoch,
    showPlot: (show?['Overview'] as String?)?.trim().isEmpty ?? true ? null : (show!['Overview'] as String).trim(),
    subtitles: subtitles,
    thumb: have(false),
    cover: have(true),
  );
  return (video: video, pictures: jobs);
}
