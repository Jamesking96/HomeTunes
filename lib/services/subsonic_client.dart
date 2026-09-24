import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/track.dart';

/// Connection details for a Subsonic-compatible server
/// (Navidrome, Airsonic-Advanced, Gonic, Ampache, Jellyfin via plugin...).
class ServerConfig {
  final String url;
  final String username;
  final String password;

  const ServerConfig({required this.url, required this.username, required this.password});

  bool get isComplete => url.trim().isNotEmpty && username.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {'url': url, 'username': username, 'password': password};

  factory ServerConfig.fromJson(Map<String, dynamic> j) => ServerConfig(
        url: (j['url'] as String?) ?? '',
        username: (j['username'] as String?) ?? '',
        password: (j['password'] as String?) ?? '',
      );
}

class SubsonicException implements Exception {
  final String message;
  SubsonicException(this.message);
  @override
  String toString() => message;
}

/// Minimal client for the Subsonic REST API (v1.16.1, JSON responses).
class SubsonicClient {
  static const apiVersion = '1.16.1';
  static const clientName = 'hometunes';

  final ServerConfig config;
  final http.Client _http;
  final Random _random;

  /// One salt per client for media URLs, so image caches see the same URL each time.
  late final String _mediaSalt = _makeSalt();

  SubsonicClient(this.config, {http.Client? httpClient, Random? random})
      : _http = httpClient ?? http.Client(),
        _random = random ?? Random.secure();

  /// Server URL without trailing slash; adds http:// if no scheme was typed.
  String get baseUrl {
    var u = config.url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// Token auth: t = md5(password + salt).
  Map<String, String> authParams({String? salt}) {
    final s = salt ?? _makeSalt();
    final token = md5.convert(utf8.encode(config.password + s)).toString();
    return {
      'u': config.username,
      't': token,
      's': s,
      'v': apiVersion,
      'c': clientName,
      'f': 'json',
    };
  }

  String _makeSalt() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(12, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  Uri buildUri(String method, [Map<String, String> params = const {}, String? salt]) {
    final base = Uri.parse('$baseUrl/rest/$method');
    return base.replace(queryParameters: {...authParams(salt: salt), ...params});
  }

  /// URL the player opens to stream a song.
  String streamUrl(String songId) => buildUri('stream', {'id': songId}, _mediaSalt).toString();

  /// URL for cover art.
  String coverArtUrl(String coverId, {int size = 512}) =>
      buildUri('getCoverArt', {'id': coverId, 'size': '$size'}, _mediaSalt).toString();

  Future<Map<String, dynamic>> _get(String method, [Map<String, String> params = const {}]) async {
    final http.Response res;
    try {
      res = await _http.get(buildUri(method, params)).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw SubsonicException('Could not reach $baseUrl ($e)');
    }
    if (res.statusCode != 200) {
      throw SubsonicException('Server replied ${res.statusCode} for $method');
    }
    final Map<String, dynamic> body;
    try {
      body = (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['subsonic-response']
          as Map<String, dynamic>;
    } catch (_) {
      throw SubsonicException('That address did not answer like a Subsonic server.');
    }
    if (body['status'] != 'ok') {
      final err = body['error'] as Map<String, dynamic>?;
      throw SubsonicException((err?['message'] as String?) ?? 'Request failed');
    }
    return body;
  }

  /// Checks URL + login. Throws [SubsonicException] with a readable message.
  Future<void> ping() => _get('ping');

  /// Downloads the whole song list: every album via getAlbumList2, then each album's songs.
  Future<List<Track>> fetchAllTracks({void Function(int albumsDone, int albumsTotal)? onProgress}) async {
    final albumIds = <String>[];
    const page = 500;
    for (var offset = 0;; offset += page) {
      final body = await _get('getAlbumList2', {
        'type': 'alphabeticalByName',
        'size': '$page',
        'offset': '$offset',
      });
      final list = (body['albumList2'] as Map<String, dynamic>?)?['album'] as List? ?? const [];
      albumIds.addAll(list.map((a) => (a as Map<String, dynamic>)['id'].toString()));
      if (list.length < page) break;
    }

    final tracks = <Track>[];
    var done = 0;
    // A few requests at a time: fast, without hammering a home server.
    const parallel = 6;
    for (var i = 0; i < albumIds.length; i += parallel) {
      final chunk = albumIds.sublist(i, min(i + parallel, albumIds.length));
      final results = await Future.wait(chunk.map(_albumSongs));
      for (final r in results) {
        tracks.addAll(r);
      }
      done += chunk.length;
      onProgress?.call(done, albumIds.length);
    }
    return tracks;
  }

  Future<List<Track>> _albumSongs(String albumId) async {
    final body = await _get('getAlbum', {'id': albumId});
    final album = body['album'] as Map<String, dynamic>? ?? const {};
    final songs = album['song'] as List? ?? const [];
    return [
      for (final s in songs)
        songToTrack(s as Map<String, dynamic>, albumArtistFallback: album['artist'] as String?),
    ];
  }

  /// Maps a Subsonic "child" (song) object to a [Track].
  static Track songToTrack(Map<String, dynamic> s, {String? albumArtistFallback}) {
    final artist = (s['artist'] as String?) ?? albumArtistFallback ?? 'Unknown Artist';
    return Track(
      id: 'server:${s['id']}',
      source: TrackSource.server,
      title: (s['title'] as String?) ?? 'Untitled',
      artist: artist,
      album: (s['album'] as String?) ?? 'Unknown Album',
      albumArtist: albumArtistFallback ?? artist,
      trackNumber: (s['track'] as num?)?.toInt(),
      discNumber: (s['discNumber'] as num?)?.toInt(),
      year: (s['year'] as num?)?.toInt(),
      genre: s['genre'] as String?,
      duration: Duration(seconds: (s['duration'] as num?)?.toInt() ?? 0),
      remoteId: s['id'].toString(),
      art: s['coverArt']?.toString(),
    );
  }

  void close() => _http.close();
}
