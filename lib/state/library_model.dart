import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/track.dart';
import '../services/local_scanner.dart';
import '../services/storage.dart';
import '../services/subsonic_client.dart';
import 'library_index.dart' as index;

/// Holds the music library: local tracks, server tracks, settings, and the
/// derived album/artist lists.
class LibraryModel extends ChangeNotifier {
  final Storage storage;
  final LocalScanner _scanner;

  LibraryModel(this.storage) : _scanner = LocalScanner(storage.artDir);

  // ---- settings ----
  List<String> folders = [];
  ServerConfig server = const ServerConfig(url: '', username: '', password: '');
  bool serverEnabled = false;
  SubsonicClient? _client;
  SubsonicClient? get client => _client;

  // ---- data ----
  List<Track> _local = [];
  List<Track> _remote = [];
  Map<String, Track> _byId = {};
  List<Track> tracks = [];
  List<Album> albums = [];
  List<Artist> artists = [];

  // ---- status ----
  bool busy = false;
  String? status; // e.g. "Scanning 120 / 900"
  String? error;

  Track? byId(String id) => _byId[id];

  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<void> load() async {
    final s = await storage.read('settings.json') as Map<String, dynamic>?;
    if (s != null) {
      folders = (s['folders'] as List? ?? const []).cast<String>().toList();
      if (s['server'] is Map<String, dynamic>) {
        server = ServerConfig.fromJson(s['server'] as Map<String, dynamic>);
      }
      serverEnabled = (s['serverEnabled'] as bool?) ?? false;
    }
    _rebuildClient();
    final lib = await storage.read('library.json') as Map<String, dynamic>?;
    if (lib != null) {
      _local = [for (final j in (lib['local'] as List? ?? const [])) Track.fromJson(j as Map<String, dynamic>)];
      _remote = [for (final j in (lib['remote'] as List? ?? const [])) Track.fromJson(j as Map<String, dynamic>)];
    }
    _rebuild();
  }

  Future<void> _saveSettings() => storage.write('settings.json', {
        'folders': folders,
        'server': server.toJson(),
        'serverEnabled': serverEnabled,
      });

  Future<void> _saveLibrary() => storage.write('library.json', {
        'local': [for (final t in _local) t.toJson()],
        'remote': [for (final t in _remote) t.toJson()],
      });

  void _rebuildClient() {
    _client?.close();
    _client = serverEnabled && server.isComplete ? SubsonicClient(server) : null;
  }

  void _rebuild() {
    tracks = [..._local, if (serverEnabled) ..._remote];
    _byId = {for (final t in tracks) t.id: t};
    albums = index.groupAlbums(tracks);
    artists = index.groupArtists(albums);
    notifyListeners();
  }

  index.SearchResults search(String q) => index.search(q, tracks, albums, artists);

  Album? albumByKey(String key) {
    for (final a in albums) {
      if (a.key == key) return a;
    }
    return null;
  }

  Artist? artistByName(String name) {
    final l = name.toLowerCase();
    for (final a in artists) {
      if (a.name.toLowerCase() == l) return a;
    }
    return null;
  }

  // ---- folders ----

  Future<void> addFolder(String path) async {
    if (folders.contains(path)) return;
    folders = [...folders, path];
    await _saveSettings();
    notifyListeners();
    await scanLocal();
  }

  Future<void> removeFolder(String path) async {
    folders = folders.where((f) => f != path).toList();
    await _saveSettings();
    await scanLocal();
  }

  /// Scans and syncs run one after another, never at the same time.
  Future<void> _jobs = Future.value();
  int _queued = 0;

  Future<void> _enqueue(Future<void> Function() work) {
    _queued++;
    final next = _jobs.then((_) async {
      busy = true;
      notifyListeners();
      try {
        await work();
      } finally {
        _queued--;
        busy = _queued > 0;
        _rebuild();
      }
    });
    _jobs = next.catchError((_) {});
    return next;
  }

  Future<void> scanLocal() => _enqueue(() async {
        error = null;
        status = 'Looking for music…';
        notifyListeners();
        try {
          final previous = {for (final t in _local) t.id: t};
          _local = await _scanner.scan(folders, previous: previous, onProgress: (done, total) {
            status = 'Scanning $done / $total';
            notifyListeners();
          });
          await _saveLibrary();
          await _scanner.removeUnusedArt(_local);
          status = null;
        } catch (e) {
          status = null;
          error = 'Scan failed: $e';
        }
      });

  // ---- server ----

  /// Saves server details after checking they work. Returns an error message or null.
  Future<String?> connectServer(ServerConfig config) async {
    final test = SubsonicClient(config);
    try {
      await test.ping();
    } on SubsonicException catch (e) {
      return e.message;
    } catch (e) {
      // e.g. an address that isn't a valid URL at all.
      return 'That server address doesn\'t look right ($e)';
    } finally {
      test.close();
    }
    server = config;
    serverEnabled = true;
    _rebuildClient();
    await _saveSettings();
    await syncServer();
    return null;
  }

  Future<void> setServerEnabled(bool on) async {
    serverEnabled = on;
    _rebuildClient();
    await _saveSettings();
    _rebuild();
    if (on && _remote.isEmpty) await syncServer();
  }

  Future<void> forgetServer() async {
    server = const ServerConfig(url: '', username: '', password: '');
    serverEnabled = false;
    _remote = [];
    _rebuildClient();
    await _saveSettings();
    await _saveLibrary();
    _rebuild();
  }

  Future<void> syncServer() => _enqueue(() async {
        final c = _client;
        if (c == null) return;
        error = null;
        status = 'Connecting to server…';
        notifyListeners();
        try {
          final result = await c.fetchAllTracks(onProgress: (done, total) {
            status = 'Syncing server albums $done / $total';
            notifyListeners();
          });
          status = null;
          // The server may have been forgotten or switched off while we synced.
          if (!identical(c, _client)) return;
          _remote = result.tracks;
          await _saveLibrary();
          if (result.failedAlbums > 0) {
            error = 'Synced, but ${result.failedAlbums} album(s) could not be read from the server.';
          }
        } catch (e) {
          status = null;
          // Cancelled by "Forget server" / switching it off: not an error.
          if (!identical(c, _client)) return;
          error = 'Server sync failed: $e';
        }
      });

  // ---- playback helpers ----

  /// What the player should open for this track: a file path or a stream URL.
  String? playableUri(Track t) {
    if (t.isLocal) return t.path;
    final c = _client;
    if (c == null || t.remoteId == null) return null;
    return c.streamUrl(t.remoteId!);
  }

  ImageProvider? artFor(Track? t, {int size = 512}) {
    if (t == null || t.art == null) return null;
    if (t.isLocal) return FileImage(File(t.art!));
    final c = _client;
    if (c == null) return null;
    return NetworkImage(c.coverArtUrl(t.art!, size: size));
  }
}
