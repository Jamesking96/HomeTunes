import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A song as MusicBrainz knows it, on one particular release (album).
class SongMatch {
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final String releaseGroupId;

  /// Official studio album (not live/compilation/bootleg): shown first.
  final bool preferred;

  const SongMatch({
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.releaseGroupId,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.preferred = false,
  });
}

/// An album (MusicBrainz "release group").
class AlbumMatch {
  final String id;
  final String title;
  final String artist;
  final int? year;
  final String? type;
  const AlbumMatch({required this.id, required this.title, required this.artist, this.year, this.type});
}

/// One track on an album's track list.
class TrackInfo {
  final int disc;
  final int number;
  final String title;
  const TrackInfo(this.disc, this.number, this.title);
}

/// Looks up song and album details on MusicBrainz (free, no account).
/// Requests are spaced ~1 s apart, as MusicBrainz asks.
class MusicInfoSearch {
  static const userAgent = 'HomeTunes/0.1 ( https://github.com/Jamesking96/HomeTunes )';
  static DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> _queue = Future.value();

  final http.Client _http;
  MusicInfoSearch({http.Client? client}) : _http = client ?? http.Client();

  void close() => _http.close();

  Future<Map<String, dynamic>> _getJson(Uri uri) {
    // One MusicBrainz request at a time, at most about one per second.
    final result = _queue.then((_) async {
      final wait = const Duration(milliseconds: 1100) - DateTime.now().difference(_lastRequest);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      const headers = {'User-Agent': userAgent, 'Accept': 'application/json'};
      var res = await _http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      if (res.statusCode == 503) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        res = await _http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      }
      _lastRequest = DateTime.now();
      if (res.statusCode != 200) throw Exception('MusicBrainz replied ${res.statusCode}');
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static String _q(String s) => '"${s.replaceAll(RegExp(r'["\\]'), ' ').trim()}"';

  static Uri songQuery({required String title, String? artist, String? album, int limit = 15}) {
    final parts = ['recording:${_q(title)}'];
    if ((artist ?? '').trim().isNotEmpty) parts.add('artist:${_q(artist!)}');
    if ((album ?? '').trim().isNotEmpty) parts.add('release:${_q(album!)}');
    return Uri.https('musicbrainz.org', '/ws/2/recording/', {
      'query': parts.join(' AND '),
      'fmt': 'json',
      'limit': '$limit',
    });
  }

  static Uri albumQuery({String? artist, String? album, int limit = 12}) {
    final parts = <String>[];
    if ((album ?? '').trim().isNotEmpty) parts.add('releasegroup:${_q(album!)}');
    if ((artist ?? '').trim().isNotEmpty) parts.add('artist:${_q(artist!)}');
    return Uri.https('musicbrainz.org', '/ws/2/release-group/', {
      'query': parts.join(' AND '),
      'fmt': 'json',
      'limit': '$limit',
    });
  }

  static String _credit(Object? credit) {
    final list = credit as List? ?? const [];
    return list.map((c) {
      final m = c as Map;
      return '${m['name'] ?? ''}${m['joinphrase'] ?? ''}';
    }).join().trim();
  }

  static int? _year(Object? date) {
    final s = (date as String?) ?? '';
    return s.length >= 4 ? int.tryParse(s.substring(0, 4)) : null;
  }

  /// Song matches from a recording search, best (official studio albums) first.
  static List<SongMatch> parseSongMatches(Map<String, dynamic> json) {
    final out = <SongMatch>[];
    final seen = <String>{};
    for (final r in (json['recordings'] as List? ?? const [])) {
      final rec = r as Map<String, dynamic>;
      final title = (rec['title'] as String?) ?? '';
      final artist = _credit(rec['artist-credit']);
      final firstYear = _year(rec['first-release-date']);
      for (final rl in (rec['releases'] as List? ?? const [])) {
        final rel = rl as Map<String, dynamic>;
        final rg = rel['release-group'] as Map<String, dynamic>? ?? const {};
        final media = (rel['media'] as List? ?? const []);
        int? track, disc;
        if (media.isNotEmpty) {
          final m = media.first as Map<String, dynamic>;
          disc = (m['position'] as num?)?.toInt();
          final tracks = m['track'] as List? ?? m['tracks'] as List? ?? const [];
          if (tracks.isNotEmpty) track = int.tryParse('${(tracks.first as Map)['number']}');
        }
        final secondary = (rg['secondary-types'] as List? ?? const []);
        final match = SongMatch(
          title: title,
          artist: artist,
          album: (rel['title'] as String?) ?? '',
          albumArtist: _credit(rel['artist-credit']).isNotEmpty ? _credit(rel['artist-credit']) : artist,
          year: _year(rel['date']) ?? firstYear,
          trackNumber: track,
          discNumber: disc,
          releaseGroupId: (rg['id'] as String?) ?? '',
          preferred: rel['status'] == 'Official' && rg['primary-type'] == 'Album' && secondary.isEmpty,
        );
        final key = '${match.album}|${match.year}|${match.trackNumber}|${match.artist}';
        if (seen.add(key)) out.add(match);
      }
    }
    // Stable: keeps MusicBrainz's relevance order within each group.
    final preferred = out.where((m) => m.preferred).toList();
    final others = out.where((m) => !m.preferred).toList();
    return [...preferred, ...others];
  }

  static List<AlbumMatch> parseAlbumMatches(Map<String, dynamic> json) => [
        for (final g in (json['release-groups'] as List? ?? const []))
          AlbumMatch(
            id: (g as Map<String, dynamic>)['id'] as String,
            title: (g['title'] as String?) ?? '',
            artist: _credit(g['artist-credit']),
            year: _year(g['first-release-date']),
            type: g['primary-type'] as String?,
          ),
      ];

  /// Genre names, most-voted first, capitalised ("alternative rock" → "Alternative Rock").
  static List<String> parseGenres(Map<String, dynamic> json, {int max = 6}) {
    final g = [for (final x in (json['genres'] as List? ?? const [])) x as Map<String, dynamic>]
      ..sort((a, b) => ((b['count'] as num?) ?? 0).compareTo((a['count'] as num?) ?? 0));
    String cap(String s) => s
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
    return [for (final x in g.take(max)) cap((x['name'] as String?) ?? '')].where((s) => s.isNotEmpty).toList();
  }

  /// Picks the release whose track count best matches ours (official first)
  /// and returns its track list.
  static List<TrackInfo> parseTracklist(Map<String, dynamic> json, {int? preferTrackCount}) {
    final releases = [for (final r in (json['releases'] as List? ?? const [])) r as Map<String, dynamic>];
    if (releases.isEmpty) return const [];
    int count(Map<String, dynamic> r) => (r['media'] as List? ?? const [])
        .fold<int>(0, (n, m) => n + (((m as Map)['tracks'] as List?)?.length ?? 0));
    int rank(Map<String, dynamic> r) =>
        (r['status'] == 'Official' ? 0 : 2) + (preferTrackCount != null && count(r) == preferTrackCount ? 0 : 1);
    releases.sort((a, b) => rank(a).compareTo(rank(b)));
    final best = releases.first;
    return [
      for (final m in (best['media'] as List? ?? const []))
        for (final t in (((m as Map)['tracks'] as List?) ?? const []))
          TrackInfo(
            (m['position'] as num?)?.toInt() ?? 1,
            int.tryParse('${(t as Map)['number']}') ?? ((t['position'] as num?)?.toInt() ?? 0),
            (t['title'] as String?) ?? '',
          ),
    ];
  }

  /// Lower-case, without bracketed extras ("(Remastered)") or punctuation.
  static String normalizeTitle(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ')
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r"[^a-z0-9]+"), ' ')
      .trim();

  /// For each of [ourTitles], the matching track (or null if none).
  static List<TrackInfo?> matchTracks(List<String> ourTitles, List<TrackInfo> tracks) {
    final byTitle = <String, TrackInfo>{};
    for (final t in tracks) {
      byTitle.putIfAbsent(normalizeTitle(t.title), () => t);
    }
    return [for (final title in ourTitles) byTitle[normalizeTitle(title)]];
  }

  // ---- network calls ----

  Future<List<SongMatch>> searchSongs({required String title, String? artist, String? album}) async {
    var results = parseSongMatches(await _getJson(songQuery(title: title, artist: artist, album: album)));
    // If the album name was too strict, try again without it.
    if (results.isEmpty && (album ?? '').trim().isNotEmpty) {
      results = parseSongMatches(await _getJson(songQuery(title: title, artist: artist)));
    }
    return results;
  }

  Future<List<AlbumMatch>> searchAlbums({String? artist, String? album}) async =>
      parseAlbumMatches(await _getJson(albumQuery(artist: artist, album: album)));

  Future<List<String>> genresFor(String releaseGroupId) async => parseGenres(await _getJson(
      Uri.https('musicbrainz.org', '/ws/2/release-group/$releaseGroupId', {'inc': 'genres', 'fmt': 'json'})));

  Future<List<TrackInfo>> tracklist(String releaseGroupId, {int? preferTrackCount}) async => parseTracklist(
        await _getJson(Uri.https('musicbrainz.org', '/ws/2/release', {
          'release-group': releaseGroupId,
          'inc': 'recordings',
          'fmt': 'json',
          'limit': '25',
        })),
        preferTrackCount: preferTrackCount,
      );
}
