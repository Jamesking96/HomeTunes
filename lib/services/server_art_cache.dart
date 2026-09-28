// Keeps copies of the music server's cover pictures as files, for the system media controls
// (Android notification and lock screen, the Windows media overlay).
//
// HomeTunes (0.1.21, security review #2): the media controls used to be given the server's cover
// address, and every Subsonic address carries the login token and salt. On Android any app with
// media or notification access can read that address, and the Windows plugin logged it. The token
// can be replayed, and it lets someone guess the password offline. Now HomeTunes downloads the
// cover itself and hands over a file:// path. Covers shown inside the app still load straight
// from the server (the address never leaves the app there).
//
// Files live in <data>/art/server/<md5 of server, user, cover id and size>.img. They're left out
// of backups (they can be downloaded again) and deleted when the server is forgotten.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'subsonic_client.dart';

class ServerArtCache {
  /// The largest cover accepted. Real covers are well under 1 MB at 512 px.
  static const maxBytes = 10 << 20;

  /// How long a failed download waits before it's tried again, so a server that has no cover
  /// for an album isn't asked on every media-controls update.
  static const retryAfter = Duration(minutes: 5);

  /// The folder the files go in (normally `<data>/art/server`).
  final String dir;
  final SubsonicClient client;
  final http.Client _http;

  /// Covers known to be on disk (key → file), so the disk isn't checked every time.
  final Map<String, String> _known = {};
  final Map<String, Future<String?>> _inFlight = {};
  final Map<String, DateTime> _failedAt = {};

  ServerArtCache(this.dir, this.client, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  String _key(String coverId, int size) => md5
      .convert(utf8.encode('${client.baseUrl.toLowerCase()}|${client.config.username}|$coverId|$size'))
      .toString();

  /// Where the cover [coverId] at [size] is (or will be) kept.
  String fileFor(String coverId, {int size = 512}) => p.join(dir, '${_key(coverId, size)}.img');

  /// The cover's file if it has already been downloaded, else null. Never downloads.
  String? cachedFile(String coverId, {int size = 512}) {
    final key = _key(coverId, size);
    final known = _known[key];
    if (known != null) return known;
    final path = fileFor(coverId, size: size);
    if (File(path).existsSync()) return _known[key] = path;
    return null;
  }

  /// Downloads the cover (once, however many times this is called while it's on its way) and
  /// returns its file, or null if the server had no usable picture. Never throws, and never
  /// puts the server address (with its login token) into an error message.
  Future<String?> fetch(String coverId, {int size = 512}) {
    final have = cachedFile(coverId, size: size);
    if (have != null) return Future.value(have);
    final key = _key(coverId, size);
    final failed = _failedAt[key];
    if (failed != null && DateTime.now().difference(failed) < retryAfter) return Future.value(null);
    final running = _inFlight[key];
    if (running != null) return running;
    final job = _download(coverId, size, key);
    _inFlight[key] = job;
    // A block body: `=> _inFlight.remove(key)` would return the future itself and wait on it.
    job.whenComplete(() {
      _inFlight.remove(key);
    });
    return job;
  }

  Future<String?> _download(String coverId, int size, String key) async {
    final path = fileFor(coverId, size: size);
    final tmp = File('$path.tmp');
    try {
      final res = await _http.get(Uri.parse(client.coverArtUrl(coverId, size: size))).timeout(const Duration(seconds: 20));
      final type = (res.headers['content-type'] ?? '').toLowerCase();
      final bytes = res.bodyBytes;
      if (res.statusCode != 200 || !type.startsWith('image/') || bytes.isEmpty || bytes.length > maxBytes) {
        _failedAt[key] = DateTime.now();
        return null;
      }
      await Directory(dir).create(recursive: true);
      // Written beside the final name, then renamed, so a half-written file is never used.
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(path);
      _failedAt.remove(key);
      return _known[key] = path;
    } catch (_) {
      // No network, timeout, disk full…: try again later. (The error could quote the address.)
      _failedAt[key] = DateTime.now();
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      return null;
    }
  }

  /// Deletes every downloaded cover (used when the server is forgotten).
  static Future<void> clear(String dir) async {
    try {
      final d = Directory(dir);
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {
      // In use: the files are harmless and get replaced or cleared next time.
    }
  }

  void close() => _http.close();
}
