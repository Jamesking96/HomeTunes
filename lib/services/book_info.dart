import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A book found on Open Library.
class BookMatch {
  final String key;
  final String title;
  final String author;
  final int? year;

  /// Open Library cover id (null when it has no cover).
  final int? coverId;

  /// Small cover preview, downloaded when searching for covers.
  final Uint8List? thumbnail;

  const BookMatch({
    required this.key,
    required this.title,
    required this.author,
    this.year,
    this.coverId,
    this.thumbnail,
  });

  BookMatch withThumbnail(Uint8List t) =>
      BookMatch(key: key, title: title, author: author, year: year, coverId: coverId, thumbnail: t);
}

/// Looks books up on Open Library (free, no account needed): covers, authors
/// and years. Used by the book editor and its "find online" buttons.
class BookInfoSearch {
  static const _headers = {'User-Agent': 'HomeTunes/0.1 ( https://github.com/Jamesking96/HomeTunes )'};
  final http.Client _http;

  BookInfoSearch({http.Client? client}) : _http = client ?? http.Client();

  void close() => _http.close();

  static Uri buildQuery({String? title, String? author, int limit = 16}) {
    final params = <String, String>{
      'fields': 'key,title,author_name,first_publish_year,cover_i',
      'limit': '$limit',
    };
    final t = title?.trim() ?? '';
    final a = author?.trim() ?? '';
    if (t.isNotEmpty) params['title'] = t;
    if (a.isNotEmpty) params['author'] = a;
    return Uri.https('openlibrary.org', '/search.json', params);
  }

  static List<BookMatch> parse(Map<String, dynamic> json) {
    final out = <BookMatch>[];
    final seen = <String>{};
    for (final d in (json['docs'] as List? ?? const [])) {
      if (d is! Map) continue;
      final key = (d['key'] as String?) ?? '';
      if (key.isEmpty || !seen.add(key)) continue;
      final authors = (d['author_name'] as List? ?? const []).cast<String>();
      out.add(BookMatch(
        key: key,
        title: (d['title'] as String?) ?? '',
        author: authors.isEmpty ? '' : authors.first,
        year: d['first_publish_year'] as int?,
        coverId: d['cover_i'] as int?,
      ));
    }
    return out;
  }

  static Uri coverUrl(int coverId, {bool large = false}) =>
      Uri.https('covers.openlibrary.org', '/b/id/$coverId-${large ? 'L' : 'M'}.jpg', {'default': 'false'});

  Future<List<BookMatch>> search({String? title, String? author}) async {
    final r = await _http.get(buildQuery(title: title, author: author), headers: _headers).timeout(
          const Duration(seconds: 20),
        );
    if (r.statusCode != 200) throw Exception('Open Library answered ${r.statusCode}');
    return parse(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  /// Books that have a cover, with a preview of each.
  Future<List<BookMatch>> searchCovers({String? title, String? author}) async {
    final found = (await search(title: title, author: author)).where((b) => b.coverId != null).take(12).toList();
    final withThumbs = await Future.wait(found.map((b) async {
      try {
        final r = await _http.get(coverUrl(b.coverId!), headers: _headers).timeout(const Duration(seconds: 15));
        if (r.statusCode == 200 && r.bodyBytes.length > 1000) return b.withThumbnail(r.bodyBytes);
      } catch (_) {}
      return null;
    }));
    // The same cover can appear on several editions: show it once.
    final seen = <int>{};
    return [for (final b in withThumbs) if (b != null && seen.add(b.coverId!)) b];
  }

  Future<Uint8List> downloadCover(BookMatch b) async {
    final r = await _http.get(coverUrl(b.coverId!, large: true), headers: _headers).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw Exception('Open Library answered ${r.statusCode}');
    return r.bodyBytes;
  }
}
