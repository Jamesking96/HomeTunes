import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// One possible cover found online.
class CoverCandidate {
  final String releaseGroupId;
  final String title;
  final String artist;
  final String? year;

  /// Small preview, already downloaded (so only covers that exist are shown).
  final Uint8List thumbnail;

  const CoverCandidate({
    required this.releaseGroupId,
    required this.title,
    required this.artist,
    required this.thumbnail,
    this.year,
  });
}

/// Finds album covers on MusicBrainz (album info) + Cover Art Archive (images).
/// Both are free, open services that need no account.
class CoverSearch {
  static const _userAgent = 'HomeTunes/0.1 ( https://github.com/Jamesking96/HomeTunes )';
  final http.Client _http;

  CoverSearch({http.Client? client}) : _http = client ?? http.Client();

  /// Builds the MusicBrainz search. With an album name it looks for that
  /// album (by that artist if known); with only a song title + artist it
  /// looks for albums containing that song.
  static Uri buildQuery({String? artist, String? album, String? title, int limit = 12}) {
    String q(String s) => '"${s.replaceAll(RegExp(r'["\\]'), ' ').trim()}"';
    final a = artist?.trim() ?? '';
    final al = album?.trim() ?? '';
    final t = title?.trim() ?? '';
    if (al.isNotEmpty) {
      final query = a.isNotEmpty ? 'releasegroup:${q(al)} AND artist:${q(a)}' : 'releasegroup:${q(al)}';
      return Uri.https('musicbrainz.org', '/ws/2/release-group/', {'query': query, 'fmt': 'json', 'limit': '$limit'});
    }
    if (t.isNotEmpty && a.isNotEmpty) {
      return Uri.https('musicbrainz.org', '/ws/2/recording/', {
        'query': 'recording:${q(t)} AND artist:${q(a)}',
        'fmt': 'json',
        'limit': '$limit',
      });
    }
    // Artist only: their albums.
    return Uri.https('musicbrainz.org', '/ws/2/release-group/', {
      'query': 'artist:${q(a)} AND primarytype:album',
      'fmt': 'json',
      'limit': '$limit',
    });
  }

  /// Release groups (albums) from a MusicBrainz search response, de-duplicated.
  static List<({String id, String title, String artist, String? year})> parseResults(Map<String, dynamic> json) {
    final out = <({String id, String title, String artist, String? year})>[];
    final seen = <String>{};

    String artistOf(Map<String, dynamic> m) {
      final credit = m['artist-credit'] as List? ?? const [];
      return credit.map((c) => ((c as Map)['name'] ?? '') as String).join(', ');
    }

    void add(Map<String, dynamic> rg, String fallbackArtist) {
      final id = rg['id'] as String?;
      if (id == null || !seen.add(id)) return;
      final date = (rg['first-release-date'] as String?) ?? '';
      final a = artistOf(rg);
      out.add((
        id: id,
        title: (rg['title'] as String?) ?? '',
        artist: a.isNotEmpty ? a : fallbackArtist,
        year: date.length >= 4 ? date.substring(0, 4) : null,
      ));
    }

    for (final rg in (json['release-groups'] as List? ?? const [])) {
      add(rg as Map<String, dynamic>, '');
    }
    for (final rec in (json['recordings'] as List? ?? const [])) {
      final r = rec as Map<String, dynamic>;
      final recArtist = artistOf(r);
      for (final rel in (r['releases'] as List? ?? const [])) {
        final rg = (rel as Map<String, dynamic>)['release-group'] as Map<String, dynamic>?;
        if (rg != null) add({...rg, 'first-release-date': rel['date']}, recArtist);
      }
    }
    return out;
  }

  static Uri thumbnailUrl(String releaseGroupId) =>
      Uri.parse('https://coverartarchive.org/release-group/$releaseGroupId/front-250');
  static Uri fullImageUrl(String releaseGroupId) =>
      Uri.parse('https://coverartarchive.org/release-group/$releaseGroupId/front-500');

  /// Searches and returns only matches that actually have a cover image.
  Future<List<CoverCandidate>> search({String? artist, String? album, String? title}) async {
    final uri = buildQuery(artist: artist, album: album, title: title);
    const headers = {'User-Agent': _userAgent, 'Accept': 'application/json'};
    var res = await _http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    if (res.statusCode == 503) {
      // MusicBrainz answers 503 when asked too often (about 1 request/second): wait and retry once.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      res = await _http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    }
    if (res.statusCode != 200) {
      throw Exception('MusicBrainz replied ${res.statusCode}');
    }
    final groups = parseResults(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);

    // Fetch previews in parallel; albums without cover art (404) are dropped.
    final thumbs = await Future.wait(groups.map((g) async {
      try {
        final r = await _http
            .get(thumbnailUrl(g.id), headers: {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 15));
        return r.statusCode == 200 && r.bodyBytes.isNotEmpty ? r.bodyBytes : null;
      } catch (_) {
        return null;
      }
    }));
    return [
      for (var i = 0; i < groups.length; i++)
        if (thumbs[i] != null)
          CoverCandidate(
            releaseGroupId: groups[i].id,
            title: groups[i].title,
            artist: groups[i].artist,
            year: groups[i].year,
            thumbnail: thumbs[i]!,
          ),
    ];
  }

  /// Downloads the larger version of a chosen cover.
  Future<Uint8List> download(CoverCandidate c) async {
    final r = await _http
        .get(fullImageUrl(c.releaseGroupId), headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      // Fall back to the preview we already have.
      return c.thumbnail;
    }
    return r.bodyBytes;
  }

  void close() => _http.close();
}
