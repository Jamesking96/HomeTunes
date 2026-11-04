// Videos (4 Nov 2026): finds a collection's genres online when neither its files, its .nfo files
// nor the server say (the user: "Where a video isn't sourced with this data, attempt to find it
// via a look up"). Three free services that need no account or key, as for pictures
// (video_art_search.dart):
//   - TVmaze (TV series): the show's genres.
//   - AniList (anime): the anime's genres.
//   - The iTunes Search API (films): the film's main genre.
// Which are asked first depends on the collection's type (Anime, TV, Films). Only a result whose
// name matches the collection's (ignoring case, punctuation and a leading "The") counts, so a
// near miss never gives a home video folder some show's genres. A year, when known, picks
// between remakes.
//
// No Flutter: VideoLibraryModel calls it (automatically for collections with no genre, and from
// the editors' "Look up online" button).
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// What a look-up found.
class GenreFind {
  /// The genres, best first (empty: nothing found).
  final List<String> genres;

  /// Which service they came from ("TVmaze", "AniList", "iTunes"), or null for none.
  final String? source;

  /// Some service couldn't be asked (no internet, it was down). An empty result then isn't
  /// "nothing to find", so it's tried again later.
  final bool incomplete;

  const GenreFind(this.genres, {this.source, this.incomplete = false});

  bool get found => genres.isNotEmpty;
}

class VideoGenreLookup {
  static const userAgent = 'HomeTunes (https://github.com/Jamesking96/HomeTunes)';

  /// At most this many genres are kept from one service.
  static const maxGenres = 4;

  final http.Client _http;
  final Duration timeout;

  VideoGenreLookup({http.Client? client, this.timeout = const Duration(seconds: 15)}) : _http = client ?? http.Client();

  /// The services to ask for a collection of [type] ("Anime", "TV", "Films" or another), in order.
  static List<String> orderFor(String? type) => switch (type) {
        'Anime' => const ['AniList', 'TVmaze'],
        'Films' => const ['iTunes', 'AniList'],
        'TV' => const ['TVmaze', 'AniList'],
        _ => const ['TVmaze', 'iTunes', 'AniList'],
      };

  /// Looks [name] up on each service in turn (see [orderFor]) and gives the first one's genres.
  Future<GenreFind> find(String name, {String? type, int? year}) async {
    final q = cleanQuery(name);
    if (q.isEmpty) return const GenreFind([]);
    var incomplete = false;
    for (final s in orderFor(type)) {
      try {
        final genres = await switch (s) {
          'TVmaze' => tvmaze(q, year: year),
          'AniList' => anilist(q, year: year),
          'iTunes' => itunes(q, year: year),
          _ => Future.value(const <String>[]),
        };
        if (genres.isNotEmpty) return GenreFind(genres.take(maxGenres).toList(), source: s);
      } catch (_) {
        incomplete = true;
      }
    }
    return GenreFind(const [], incomplete: incomplete);
  }

  /// The name to search for: "(2019)" and "[1080p]" style bits taken off.
  static String cleanQuery(String name) => name
      .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r'\((?:19|20)\d\d\)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// A name reduced to compare: lower case, letters and digits only (any script), no leading
  /// "the", "&" read as "and".
  static String comparable(String name) {
    var s = name.toLowerCase().replaceAll('&', ' and ');
    s = s.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
    if (s.startsWith('the ')) s = s.substring(4);
    return s.replaceAll(' ', '');
  }

  /// Whether a result named [found] (from [foundYear]) is the collection [wanted] (from [year]).
  static bool matches(String wanted, String? found, {int? year, int? foundYear}) {
    if (found == null) return false;
    final a = comparable(wanted), b = comparable(found);
    if (a.isEmpty || a != b) return false;
    return year == null || foundYear == null || (year - foundYear).abs() <= 1;
  }

  Future<Object?> _getJson(Uri uri) async {
    final r = await _http.get(uri, headers: {'User-Agent': userAgent, 'Accept': 'application/json'}).timeout(timeout);
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}', uri);
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  static int? _yearOf(Object? date) =>
      date is String && date.length >= 4 ? int.tryParse(date.substring(0, 4)) : (date is int ? date : null);

  static List<String> _strings(Object? list) =>
      list is List ? [for (final x in list) if (x is String && x.trim().isNotEmpty) x.trim()] : const [];

  // ---- TVmaze ----

  /// The genres of the show called [query] (the one from [year] when there are several).
  Future<List<String>> tvmaze(String query, {int? year}) async {
    final hits = await _getJson(Uri.https('api.tvmaze.com', '/search/shows', {'q': query}));
    if (hits is! List) return const [];
    final shows = [for (final h in hits) if (h is Map && h['show'] is Map) h['show'] as Map];
    // The same name and year first, then the same name in any year.
    for (final strict in [true, false]) {
      for (final show in shows) {
        final y = _yearOf(show['premiered']);
        if (!matches(query, show['name'] as String?, year: strict ? year : null, foundYear: y)) continue;
        if (strict && year != null && y == null) continue;
        final g = _strings(show['genres']);
        if (g.isNotEmpty) return g;
      }
    }
    return const [];
  }

  // ---- AniList ----

  static const _anilistQuery = r'''
query ($search: String) {
  Page(perPage: 8) {
    media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
      title { romaji english native }
      synonyms
      seasonYear
      genres
    }
  }
}''';

  /// The genres of the anime called [query] (by any of its titles).
  Future<List<String>> anilist(String query, {int? year}) async {
    final r = await _http
        .post(Uri.https('graphql.anilist.co', '/'),
            headers: {'User-Agent': userAgent, 'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'query': _anilistQuery, 'variables': {'search': query}}))
        .timeout(timeout);
    // AniList answers 404 when nothing matches.
    if (r.statusCode == 404) return const [];
    if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}', r.request?.url);
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final media = (((j is Map ? j['data'] : null) as Map?)?['Page'] as Map?)?['media'];
    if (media is! List) return const [];
    for (final strict in [true, false]) {
      for (final m in media) {
        if (m is! Map) continue;
        final t = m['title'] is Map ? m['title'] as Map : const {};
        final names = [t['english'], t['romaji'], t['native'], ..._strings(m['synonyms'])].whereType<String>();
        final y = m['seasonYear'] is int ? m['seasonYear'] as int : null;
        if (strict && year != null && y == null) continue;
        if (!names.any((n) => matches(query, n, year: strict ? year : null, foundYear: y))) continue;
        final g = _strings(m['genres']);
        if (g.isNotEmpty) return g;
      }
    }
    return const [];
  }

  // ---- iTunes (films) ----

  /// The main genre of the film called [query].
  Future<List<String>> itunes(String query, {int? year}) async {
    final j = await _getJson(Uri.https('itunes.apple.com', '/search',
        {'term': query, 'media': 'movie', 'entity': 'movie', 'limit': '10', 'country': 'GB'}));
    final results = j is Map ? j['results'] : null;
    if (results is! List) return const [];
    for (final strict in [true, false]) {
      for (final m in results) {
        if (m is! Map) continue;
        final y = _yearOf(m['releaseDate']);
        if (strict && year != null && y == null) continue;
        if (!matches(query, m['trackName'] as String?, year: strict ? year : null, foundYear: y)) continue;
        final g = m['primaryGenreName'];
        if (g is String && g.trim().isNotEmpty) return [g.trim()];
      }
    }
    return const [];
  }
}
