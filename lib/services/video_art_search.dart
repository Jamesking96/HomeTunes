// Videos (0.1.32): finds pictures for a video or a collection online, for "Search online…" in
// the Change picture / Change poster options. Three free services that need no account or key:
//   - TVmaze (TV series): posters, backgrounds and banners for the show, and the still for one
//     episode. Its data and pictures are CC BY-SA: the search dialog credits TVmaze.
//   - AniList (anime): cover and banner pictures. Free for non-commercial use.
//   - Wikipedia (films and anything else): the picture in the article's infobox (for a film that
//     is usually its poster: a small, copyrighted "fair use" picture, fine for a personal
//     library), or the article's free picture.
// Each service is asked on its own; one that fails or finds nothing doesn't stop the others.
// All three ask apps to name themselves in a User-Agent.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// One picture found online.
class VideoArtCandidate {
  /// "TVmaze", "AniList" or "Wikipedia".
  final String source;

  /// What it's a picture of ("Silo (2023)").
  final String title;

  /// "Poster", "Background", "Banner", "Episode", "Cover", "Picture".
  final String kind;

  /// A small version, for the list.
  final String previewUrl;

  /// The picture to save.
  final String fullUrl;

  /// Width / height, when the service says.
  final double? aspect;

  const VideoArtCandidate({
    required this.source,
    required this.title,
    required this.kind,
    required this.previewUrl,
    required this.fullUrl,
    this.aspect,
  });

  bool get tall => aspect != null && aspect! < 1;
}

/// What a search found, and which services couldn't be asked.
class VideoArtResults {
  final List<VideoArtCandidate> found;
  final List<String> failed;
  const VideoArtResults(this.found, this.failed);
}

class VideoArtSearch {
  static const userAgent = 'HomeTunes/0.1.32 (https://github.com/Jamesking96/HomeTunes)';
  static const services = ['TVmaze', 'AniList', 'Wikipedia'];
  final http.Client _http;
  final Duration timeout;

  VideoArtSearch({http.Client? client, this.timeout = const Duration(seconds: 15)}) : _http = client ?? http.Client();

  /// Looks for pictures of [query] on every service in [order] (all three by default), in that
  /// order. With [season] and [episode], TVmaze also gives that episode's still. [wikipediaHint]
  /// ("film", "TV series") is added to the Wikipedia search, which otherwise finds swords for
  /// "Claymore".
  Future<VideoArtResults> search(String query,
      {int? season, int? episode, String? wikipediaHint, List<String> order = services}) async {
    final q = query.trim();
    if (q.isEmpty) return const VideoArtResults([], []);
    // All at once; each catches its own failure.
    Future<(String, List<VideoArtCandidate>?)> ask(String s) async {
      try {
        final list = await switch (s) {
          'TVmaze' => tvmaze(q, season: season, episode: episode),
          'AniList' => anilist(q),
          'Wikipedia' => wikipedia(wikipediaHint == null ? q : '$q $wikipediaHint'),
          _ => Future.value(const <VideoArtCandidate>[]),
        };
        return (s, list);
      } catch (_) {
        return (s, null);
      }
    }

    final results = await Future.wait([for (final s in order) ask(s)]);
    return VideoArtResults(
      [for (final (_, list) in results) ...?list],
      [for (final (s, list) in results) if (list == null) s],
    );
  }

  Future<Object?> _getJson(Uri uri) async {
    final r = await _http.get(uri, headers: {'User-Agent': userAgent, 'Accept': 'application/json'}).timeout(timeout);
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}', uri);
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  // ---- TVmaze ----

  /// The best two shows' posters, backgrounds and banners, plus one episode's still.
  Future<List<VideoArtCandidate>> tvmaze(String query, {int? season, int? episode}) async {
    final hits = await _getJson(Uri.https('api.tvmaze.com', '/search/shows', {'q': query}));
    if (hits is! List) return const [];
    final shows = [
      for (final h in hits.take(2))
        if (h is Map && h['show'] is Map && ((h['score'] as num?) ?? 0) >= 0.4) h['show'] as Map
    ];
    final out = <VideoArtCandidate>[];
    for (final (i, show) in shows.indexed) {
      final id = show['id'];
      final premiered = show['premiered'] as String?;
      final name = '${show['name']}${premiered != null && premiered.length >= 4 ? ' (${premiered.substring(0, 4)})' : ''}';
      if (i == 0 && season != null && episode != null) {
        Object? ep;
        try {
          ep = await _getJson(Uri.https('api.tvmaze.com', '/shows/$id/episodebynumber',
              {'season': '$season', 'number': '$episode'}));
        } catch (_) {
          // No still for that episode: the show's pictures still come.
        }
        final image = ep is Map ? ep['image'] : null;
        if (image is Map && image['original'] is String) {
          out.add(VideoArtCandidate(
            source: 'TVmaze',
            title: '$name · S$season E$episode${ep is Map && ep['name'] is String ? ' "${ep['name']}"' : ''}',
            kind: 'Episode',
            previewUrl: (image['medium'] as String?) ?? image['original'] as String,
            fullUrl: image['original'] as String,
            aspect: 16 / 9,
          ));
        }
      }
      final images = await _getJson(Uri.https('api.tvmaze.com', '/shows/$id/images'));
      if (images is! List) continue;
      const kinds = {'poster': 'Poster', 'background': 'Background', 'banner': 'Banner'};
      final list = [
        for (final im in images)
          if (im is Map && kinds.containsKey(im['type']) && im['resolutions'] is Map) im
      ]..sort((a, b) {
          // Posters first, then backgrounds, then banners; each service's main picture first.
          final k = kinds.keys.toList();
          final t = k.indexOf(a['type'] as String).compareTo(k.indexOf(b['type'] as String));
          if (t != 0) return t;
          return (b['main'] == true ? 1 : 0).compareTo(a['main'] == true ? 1 : 0);
        });
      final perKind = <String, int>{};
      for (final im in list) {
        final type = im['type'] as String;
        if ((perKind[type] = (perKind[type] ?? 0) + 1) > 4) continue;
        final res = im['resolutions'] as Map;
        final original = res['original'] is Map ? res['original'] as Map : null;
        final medium = res['medium'] is Map ? res['medium'] as Map : null;
        final full = original?['url'] as String?;
        if (full == null) continue;
        final w = (original?['width'] as num?)?.toDouble(), h = (original?['height'] as num?)?.toDouble();
        out.add(VideoArtCandidate(
          source: 'TVmaze',
          title: name,
          kind: kinds[type]!,
          previewUrl: (medium?['url'] as String?) ?? full,
          fullUrl: full,
          aspect: (w != null && h != null && h > 0) ? w / h : null,
        ));
      }
    }
    return out;
  }

  // ---- AniList ----

  static const _anilistQuery = r'''
query ($search: String) {
  Page(perPage: 4) {
    media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
      title { romaji english }
      seasonYear
      format
      coverImage { large extraLarge }
      bannerImage
    }
  }
}''';

  /// Covers (tall) and banners (wide) of the best matching anime.
  Future<List<VideoArtCandidate>> anilist(String query) async {
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
    final out = <VideoArtCandidate>[];
    for (final m in media) {
      if (m is! Map) continue;
      final t = m['title'] is Map ? m['title'] as Map : const {};
      final name = (t['english'] as String?) ?? (t['romaji'] as String?) ?? query;
      final year = m['seasonYear'];
      final label = '$name${year != null ? ' ($year)' : ''}${m['format'] is String ? ' · ${m['format']}' : ''}';
      final cover = m['coverImage'] is Map ? m['coverImage'] as Map : const {};
      final full = (cover['extraLarge'] as String?) ?? (cover['large'] as String?);
      if (full != null) {
        out.add(VideoArtCandidate(
            source: 'AniList', title: label, kind: 'Cover', previewUrl: (cover['large'] as String?) ?? full, fullUrl: full, aspect: 0.7));
      }
      final banner = m['bannerImage'] as String?;
      if (banner != null) {
        out.add(VideoArtCandidate(source: 'AniList', title: label, kind: 'Banner', previewUrl: banner, fullUrl: banner, aspect: 4.5));
      }
    }
    return out;
  }

  // ---- Wikipedia ----

  static Uri _wiki(Map<String, String> params) =>
      Uri.https('en.wikipedia.org', '/w/api.php', {...params, 'format': 'json', 'formatversion': '2'});

  /// For the best three articles: the infobox picture (a film's poster), or the free picture.
  Future<List<VideoArtCandidate>> wikipedia(String query) async {
    final j = await _getJson(_wiki({
      'action': 'query',
      'generator': 'search',
      'gsrsearch': query,
      'gsrlimit': '3',
      'prop': 'pageimages|description',
      'piprop': 'thumbnail|original',
      'pithumbsize': '400',
    }));
    final pages = ((j is Map ? j['query'] : null) as Map?)?['pages'];
    if (pages is! List) return const [];
    final list = [for (final pg in pages) if (pg is Map) pg]
      ..sort((a, b) => ((a['index'] as num?) ?? 99).compareTo((b['index'] as num?) ?? 99));
    // The infobox picture of each article (non-free pictures, like posters, aren't "page images").
    final infobox = <String, String>{};
    for (final pg in list) {
      final title = pg['title'] as String?;
      if (title == null) continue;
      try {
        final parsed = await _getJson(_wiki({'action': 'parse', 'page': title, 'prop': 'wikitext', 'section': '0', 'redirects': '1'}));
        final text = ((parsed is Map ? parsed['parse'] : null) as Map?)?['wikitext'];
        final file = text is String ? infoboxImage(text) : null;
        if (file != null) infobox[title] = file;
      } catch (_) {
        // Just this article's infobox: its free picture may still do.
      }
    }
    final files = <String, Map>{};
    if (infobox.isNotEmpty) {
      final info = await _getJson(_wiki({
        'action': 'query',
        'titles': infobox.values.map((f) => 'File:$f').join('|'),
        'prop': 'imageinfo',
        'iiprop': 'url|size|mime',
        'iiurlwidth': '400',
      }));
      final q = (info is Map ? info['query'] : null) as Map?;
      // The API may tidy names ("_" to " ", first letter capital): follow its "normalized" list.
      final renamed = {
        for (final n in (q?['normalized'] as List? ?? const []))
          if (n is Map) n['to'] as String: (n['from'] as String).replaceFirst('File:', '')
      };
      for (final fp in (q?['pages'] as List? ?? const [])) {
        if (fp is! Map || fp['imageinfo'] is! List || (fp['imageinfo'] as List).isEmpty) continue;
        final t = fp['title'] as String;
        files[renamed[t] ?? t.replaceFirst('File:', '')] = (fp['imageinfo'] as List).first as Map;
      }
    }
    const pictures = {'image/jpeg', 'image/png', 'image/webp'};
    final out = <VideoArtCandidate>[];
    for (final pg in list) {
      final title = pg['title'] as String? ?? query;
      final label = pg['description'] is String ? '$title · ${pg['description']}' : title;
      final file = infobox[title];
      final ii = file == null ? null : files[file];
      if (ii != null && pictures.contains(ii['mime']) && ii['url'] is String) {
        final w = (ii['width'] as num?)?.toDouble(), h = (ii['height'] as num?)?.toDouble();
        out.add(VideoArtCandidate(
          source: 'Wikipedia',
          title: label,
          kind: 'Picture',
          previewUrl: (ii['thumburl'] as String?) ?? ii['url'] as String,
          fullUrl: ii['url'] as String,
          aspect: (w != null && h != null && h > 0) ? w / h : null,
        ));
        continue;
      }
      final original = pg['original'] is Map ? pg['original'] as Map : null;
      final src = original?['source'] as String?;
      if (src == null || !RegExp(r'\.(jpe?g|png|webp)(\?|$)', caseSensitive: false).hasMatch(src)) continue;
      final w = (original?['width'] as num?)?.toDouble(), h = (original?['height'] as num?)?.toDouble();
      out.add(VideoArtCandidate(
        source: 'Wikipedia',
        title: label,
        kind: 'Picture',
        previewUrl: ((pg['thumbnail'] as Map?)?['source'] as String?) ?? src,
        fullUrl: src,
        aspect: (w != null && h != null && h > 0) ? w / h : null,
      ));
    }
    return out;
  }

  /// The file name in an infobox's `| image = …` line, or null.
  static String? infoboxImage(String wikitext) {
    final m = RegExp(r'^\s*\|\s*image\s*=\s*(.+?)\s*$', multiLine: true).firstMatch(wikitext);
    if (m == null) return null;
    var v = m[1]!;
    // [[File:Name.jpg|thumb|…]] or File:Name.jpg or plain Name.jpg; drop comments.
    v = v.replaceAll(RegExp(r'<!--.*?-->'), '').trim();
    final link = RegExp(r'\[\[(?:File|Image):([^|\]]+)', caseSensitive: false).firstMatch(v);
    if (link != null) v = link[1]!;
    v = v.replaceFirst(RegExp(r'^(File|Image):', caseSensitive: false), '').split('|').first.trim();
    return RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(v) ? v : null;
  }

  // ---- downloading ----

  /// Downloads the picture (the smaller one if the full one fails). Throws if neither is a picture.
  Future<Uint8List> download(VideoArtCandidate c) async {
    for (final url in {c.fullUrl, c.previewUrl}) {
      try {
        final r = await _http.get(Uri.parse(url), headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 30));
        if (r.statusCode == 200 && looksLikePicture(r.bodyBytes)) return r.bodyBytes;
      } catch (_) {}
    }
    throw const FormatException('The picture couldn\'t be downloaded');
  }

  /// JPEG, PNG or WebP, by the first bytes.
  static bool looksLikePicture(List<int> b) =>
      (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) ||
      (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) ||
      (b.length > 12 && String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' && String.fromCharCodes(b.sublist(8, 12)) == 'WEBP');

  void close() => _http.close();
}
