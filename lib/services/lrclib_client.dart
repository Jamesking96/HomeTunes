import 'dart:convert';

import 'package:http/http.dart' as http;

/// One set of lyrics found on LRCLIB.
class LrclibMatch {
  final int id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;

  const LrclibMatch({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.instrumental = false,
    this.plainLyrics,
    this.syncedLyrics,
  });

  bool get timed => (syncedLyrics ?? '').trim().isNotEmpty;
  bool get hasLyrics => timed || (plainLyrics ?? '').trim().isNotEmpty;

  /// Timed lyrics if there are any, otherwise plain.
  String? get bestLyrics => timed ? syncedLyrics : ((plainLyrics ?? '').trim().isEmpty ? null : plainLyrics);

  factory LrclibMatch.fromJson(Map<String, dynamic> j) => LrclibMatch(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['trackName'] as String?) ?? '',
        artist: (j['artistName'] as String?) ?? '',
        album: (j['albumName'] as String?) ?? '',
        duration: Duration(milliseconds: (((j['duration'] as num?) ?? 0) * 1000).round()),
        instrumental: (j['instrumental'] as bool?) ?? false,
        plainLyrics: j['plainLyrics'] as String?,
        syncedLyrics: j['syncedLyrics'] as String?,
      );
}

class LrclibException implements Exception {
  final String message;
  LrclibException(this.message);
  @override
  String toString() => message;
}

/// LRCLIB (lrclib.net): a free lyrics database with no account needed.
/// Only the song's title, artist, album and length are sent.
class LrclibClient {
  static const host = 'lrclib.net';
  static const userAgent = 'HomeTunes (https://github.com/Jamesking96/HomeTunes)';

  final http.Client _http;
  LrclibClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Future<dynamic> _get(String path, Map<String, String> params) async {
    final uri = Uri.https(host, path, params);
    final http.Response res;
    try {
      res = await _http.get(uri, headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw LrclibException('Couldn\'t reach LRCLIB. Check your internet connection. ($e)');
    }
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw LrclibException('LRCLIB replied ${res.statusCode}');
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw LrclibException('LRCLIB sent something unexpected');
    }
  }

  /// The best single match for a song, or null. Tries LRCLIB's exact lookup
  /// (title, artist, album and length), then a search checked against the length.
  Future<LrclibMatch?> find({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    if (duration != null && duration > Duration.zero) {
      final j = await _get('/api/get', {
        'track_name': title,
        'artist_name': artist,
        if (album != null && album.isNotEmpty) 'album_name': album,
        'duration': '${duration.inSeconds}',
      });
      if (j is Map<String, dynamic>) {
        final m = LrclibMatch.fromJson(j);
        if (m.hasLyrics) return m;
      }
    }
    final found = await search(title: title, artist: artist, album: album, duration: duration);
    for (final m in found) {
      if (!m.hasLyrics) continue;
      // Without a close length the lyrics are probably for another version.
      if (duration != null && duration > Duration.zero && !closeLength(m.duration, duration)) continue;
      if (!sameText(m.title, title) || !sameText(m.artist, artist)) continue;
      return m;
    }
    return null;
  }

  /// Everything LRCLIB has for a song, best first: closest in length,
  /// timed before plain.
  Future<List<LrclibMatch>> search({
    required String title,
    String? artist,
    String? album,
    Duration? duration,
  }) async {
    final j = await _get('/api/search', {
      'track_name': title,
      if (artist != null && artist.isNotEmpty) 'artist_name': artist,
    });
    final list = [
      if (j is List)
        for (final e in j)
          if (e is Map<String, dynamic>) LrclibMatch.fromJson(e),
    ];
    return rank(list, duration: duration, album: album);
  }

  /// Free text search (for when the song's details don't find anything).
  Future<List<LrclibMatch>> searchText(String q, {Duration? duration}) async {
    final j = await _get('/api/search', {'q': q});
    final list = [
      if (j is List)
        for (final e in j)
          if (e is Map<String, dynamic>) LrclibMatch.fromJson(e),
    ];
    return rank(list, duration: duration);
  }

  /// Orders matches: ones with lyrics, then closest in length (within a few
  /// seconds counts as equal), timed first, same album first.
  static List<LrclibMatch> rank(List<LrclibMatch> list, {Duration? duration, String? album}) {
    int lengthScore(LrclibMatch m) {
      if (duration == null || duration <= Duration.zero) return 0;
      final diff = (m.duration - duration).inSeconds.abs();
      return diff <= 3 ? 0 : diff;
    }

    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((a, b) {
      final x = a.$2, y = b.$2;
      int c;
      if ((c = (y.hasLyrics ? 1 : 0) - (x.hasLyrics ? 1 : 0)) != 0) return c;
      if ((c = lengthScore(x).compareTo(lengthScore(y))) != 0) return c;
      if ((c = (y.timed ? 1 : 0) - (x.timed ? 1 : 0)) != 0) return c;
      if (album != null && album.isNotEmpty) {
        c = (sameText(y.album, album) ? 1 : 0) - (sameText(x.album, album) ? 1 : 0);
        if (c != 0) return c;
      }
      return a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  /// Lengths within a few seconds of each other.
  static bool closeLength(Duration a, Duration b) => (a - b).inSeconds.abs() <= 3;

  /// Same words ignoring case, punctuation and "feat." parts.
  static bool sameText(String a, String b) {
    final x = _norm(a), y = _norm(b);
    if (x.isEmpty || y.isEmpty) return x == y;
    return x == y || x.contains(y) || y.contains(x);
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\s*[\(\[](feat|ft|with)\.?[^\)\]]*[\)\]]'), '')
      .replaceAll(RegExp(r'\s+(feat|ft)\.?\s.*$'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  void close() => _http.close();
}
