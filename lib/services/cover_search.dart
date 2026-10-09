// Finds album covers online for the "find cover online" option when editing songs/albums.
// Step 1 asks MusicBrainz (a free music encyclopedia) which albums match; step 2 fetches a small
// preview of each from the Cover Art Archive, dropping albums that have no picture. When the user
// picks one, download() gets the bigger version, which the editor saves as the custom cover.
// Both services are free and ask apps to send a User-Agent that names them.
// 9 Oct 2026: when the exact search finds nothing, it's tried once more without punctuation
// (MusicBrainz spells Black Eyed Peas' "THE E.N.D." as "The E•N•D", which a quoted search for
// "E.N.D." never matches), and a "busy" answer from MusicBrainz is retried twice, not once. The
// Cover Art Archive (served by archive.org) can take over 15 s per picture, and covers that took
// longer were silently left out, so it's given 45 s for a preview and 60 s for the full picture.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// One possible cover found online.
class CoverCandidate {
  /// MusicBrainz's id for the album (all its editions together).
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

/// MusicBrainz found albums, but none of their pictures arrived from the Cover Art Archive (it
/// didn't answer in time, or not at all), as opposed to them having no cover.
class CoverSiteUnavailable implements Exception {
  const CoverSiteUnavailable();
  @override
  String toString() => 'The Cover Art Archive didn\'t answer in time';
}

/// Finds album covers on MusicBrainz (album info) + Cover Art Archive (images).
/// Both are free, open services that need no account.
class CoverSearch {
  static const _userAgent = 'HomeTunes/0.1 ( https://github.com/Jamesking96/HomeTunes )';
  final http.Client _http;

  /// The longest a cover preview may take (9 Oct 2026: 45 s, was 15 s).
  static const previewWait = Duration(seconds: 45);

  /// How long to wait before asking MusicBrainz again (it allows about one request a second), and
  /// before the first retry when it says it's busy (the second waits twice as long). Shorter in tests.
  final Duration pause, busyWait;

  CoverSearch({
    http.Client? client,
    this.pause = const Duration(milliseconds: 1100),
    this.busyWait = const Duration(milliseconds: 1500),
  }) : _http = client ?? http.Client();

  /// [s] without punctuation or symbols ("THE E.N.D." → "THE E N D", "AC/DC" → "AC DC"): letters,
  /// digits and single spaces only, in any alphabet.
  static String loosen(String s) =>
      s.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Builds the MusicBrainz search. With an album name it looks for that
  /// album (by that artist if known); with only a song title + artist it
  /// looks for albums containing that song.
  static Uri buildQuery({String? artist, String? album, String? title, int limit = 12}) {
    // Wrap each value in quotes for the search, removing quotes/backslashes that would break it.
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
    // A song search returns recordings; each lists the releases (albums) it's on.
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

  // Cover Art Archive addresses: 250 px preview and 500 px full picture of the front cover.
  static Uri thumbnailUrl(String releaseGroupId) =>
      Uri.parse('https://coverartarchive.org/release-group/$releaseGroupId/front-250');
  static Uri fullImageUrl(String releaseGroupId) =>
      Uri.parse('https://coverartarchive.org/release-group/$releaseGroupId/front-500');

  /// Asks MusicBrainz; the albums it found.
  Future<List<({String id, String title, String artist, String? year})>> _ask(Uri uri) async {
    const headers = {'User-Agent': _userAgent, 'Accept': 'application/json'};
    var res = await _http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    // MusicBrainz answers 503 when it's busy or asked too often (about 1 request/second): wait and
    // try again, twice at most, waiting longer the second time.
    for (var wait = busyWait, tries = 0; res.statusCode == 503 && tries < 2; wait *= 2, tries++) {
      await Future<void>.delayed(wait);
      res = await _http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    }
    if (res.statusCode != 200) {
      throw Exception('MusicBrainz replied ${res.statusCode}');
    }
    return parseResults(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Searches and returns only matches that actually have a cover image.
  Future<List<CoverCandidate>> search({String? artist, String? album, String? title}) async {
    var groups = await _ask(buildQuery(artist: artist, album: album, title: title));
    if (groups.isEmpty) {
      // Nothing for the exact names: try again without punctuation, which MusicBrainz may write
      // differently (only if that changes anything).
      final a = loosen(artist ?? ''), al = loosen(album ?? ''), t = loosen(title ?? '');
      if (a != (artist ?? '').trim() || al != (album ?? '').trim() || t != (title ?? '').trim()) {
        await Future<void>.delayed(pause);
        groups = await _ask(buildQuery(artist: a, album: al, title: t));
      }
    }

    // Fetch previews in parallel; albums without cover art (404) are dropped.
    var failed = 0;
    final thumbs = await Future.wait(groups.map((g) async {
      try {
        final r = await _http
            .get(thumbnailUrl(g.id), headers: {'User-Agent': _userAgent})
            .timeout(previewWait);
        if (r.statusCode != 200 && r.statusCode != 404) failed++;
        return r.statusCode == 200 && r.bodyBytes.isNotEmpty ? r.bodyBytes : null;
      } catch (_) {
        failed++; // too slow, or no connection
        return null;
      }
    }));
    // Not one picture arrived, and not because they have none: say so rather than "no covers".
    if (failed > 0 && thumbs.every((t) => t == null)) throw const CoverSiteUnavailable();
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
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) {
      // Fall back to the preview we already have.
      return c.thumbnail;
    }
    return r.bodyBytes;
  }

  /// Frees the network connection.
  void close() => _http.close();
}
