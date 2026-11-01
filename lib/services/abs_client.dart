// Talks to an Audiobookshelf server (0.2.7): signing in, its book libraries and what's in them,
// the addresses to play, download and show covers from, and where you got to in each book.
//
// The user asked (1 Nov 2026) for HomeTunes' servers to support Audiobookshelf; they chose
// audiobooks only (no podcasts), places kept the same on both sides, and every download feature.
// state/server_books.dart turns what this returns into the Books tab's files.
//
// Signing in (Audiobookshelf 2.26 and later): the user name and password saved in Settings ›
// Servers go once to POST /login with `x-return-tokens: true`; the server answers with an access
// token (a JWT that runs out after an hour on 2.31+) and a refresh token (a week). Every request
// carries the access token in the Authorization header; when it's about to run out, POST
// /auth/refresh with the refresh token in `x-refresh-token` gives a new pair (the old refresh
// token is then spent). Older servers only give `user.token`, which doesn't run out.
//
// Playing: a file streams from /api/items/<item>/file/<ino>. The audio player can't send headers
// with every file of a book, so this one address carries the access token as `?token=` (as the
// server's own web player does; hideSecrets hides it from any error or log). Downloads and covers
// send it in the header.
//
// Checked against the user's server (2.37.2, 1 Nov 2026) with a test account.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'subsonic_client.dart' show hideSecrets;

/// Something went wrong talking to the server. [message] is a sentence for the user and never
/// holds a token.
class AbsException implements Exception {
  final String message;

  /// The server answered (as opposed to not being reachable).
  final bool fromServer;

  /// The HTTP status, when the server answered.
  final int? status;
  const AbsException(this.message, {this.fromServer = false, this.status});

  /// The sign-in is no longer accepted.
  bool get signedOut => status == 401;

  @override
  String toString() => message;
}

/// What signing in (or refreshing) gave.
class AbsSignIn {
  /// What every request carries.
  final String accessToken;

  /// What gets a new [accessToken] (null on servers before 2.26).
  final String? refreshToken;

  /// When [accessToken] runs out (ms since epoch); null when it doesn't.
  final int? expiresMs;
  final String userId;
  final String? username;
  const AbsSignIn({required this.accessToken, this.refreshToken, this.expiresMs, required this.userId, this.username});
}

/// One of the server's libraries.
class AbsLibrary {
  final String id;
  final String name;

  /// "book" or "podcast".
  final String mediaType;
  const AbsLibrary(this.id, this.name, this.mediaType);

  bool get holdsBooks => mediaType == 'book';

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'type': mediaType};

  static AbsLibrary? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return AbsLibrary(j['id'] as String, (j['name'] as String?) ?? '', (j['type'] ?? j['mediaType'] ?? 'book').toString());
  }
}

/// Where the user got to in one item, as the server keeps it.
class AbsProgress {
  final String itemId;

  /// Seconds from the start of the whole book.
  final double currentTime;
  final double duration;
  final bool isFinished;

  /// When it was last changed (ms since epoch).
  final int lastUpdate;
  const AbsProgress({
    required this.itemId,
    required this.currentTime,
    required this.duration,
    required this.isFinished,
    required this.lastUpdate,
  });

  static AbsProgress? fromJson(Object? j) {
    if (j is! Map || j['libraryItemId'] is! String) return null;
    // Podcast episodes have their own; only books are read.
    if (j['episodeId'] != null) return null;
    double num0(Object? v) => v is num ? v.toDouble() : 0;
    return AbsProgress(
      itemId: j['libraryItemId'] as String,
      currentTime: num0(j['currentTime']),
      duration: num0(j['duration']),
      isFinished: j['isFinished'] == true,
      lastUpdate: j['lastUpdate'] is int ? j['lastUpdate'] as int : 0,
    );
  }
}

/// A page of a long list, and how far through it is.
typedef AbsProgressCallback = void Function(int done, int total);

class AbsClient {
  AbsClient({
    required String baseUrl,
    this.token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  })  : baseUrl = _trim(baseUrl),
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  /// The server's address, without a trailing slash.
  final String baseUrl;

  /// The access token, once signed in.
  String? token;

  final Duration timeout;
  final http.Client _http;
  final bool _ownsHttp;

  /// How many items are asked for at a time.
  static const pageSize = 100, batchSize = 50;

  static String _trim(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// Headers for downloads and covers: the sign-in, never in the address.
  Map<String, String> get mediaHeaders => {if (token != null) 'Authorization': 'Bearer $token'};

  Uri uri(String path, [Map<String, Object?> query = const {}]) {
    final q = <String, String>{
      for (final e in query.entries)
        if (e.value != null) e.key: '${e.value}',
    };
    return Uri.parse('$baseUrl$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<http.Response> _send(String method, Uri u, {Object? body, Map<String, String> headers = const {}}) async {
    final all = {
      'Accept': 'application/json',
      ...mediaHeaders,
      if (body != null) 'Content-Type': 'application/json',
      ...headers,
    };
    http.Response res;
    try {
      final req = http.Request(method, u)..headers.addAll(all);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout)).timeout(timeout);
    } on TimeoutException {
      throw AbsException('No answer from $baseUrl.');
    } catch (e) {
      throw AbsException('Couldn\'t reach $baseUrl (${hideSecrets('$e')}).');
    }
    if (res.statusCode == 401) {
      throw const AbsException('The Audiobookshelf server no longer accepts the sign-in.', fromServer: true, status: 401);
    }
    if (res.statusCode == 429) {
      throw const AbsException('The Audiobookshelf server says too many sign-ins were tried. Wait a few minutes.',
          fromServer: true, status: 429);
    }
    if (res.statusCode >= 400) {
      throw AbsException('The Audiobookshelf server replied ${res.statusCode}.', fromServer: true, status: res.statusCode);
    }
    return res;
  }

  Future<Object?> _json(String method, Uri u, {Object? body, Map<String, String> headers = const {}}) async {
    final res = await _send(method, u, body: body, headers: headers);
    if (res.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      // Some answers (PATCH progress) are just "OK".
      if (method != 'GET') return null;
      throw const AbsException('The Audiobookshelf server sent something HomeTunes couldn\'t read.', fromServer: true);
    }
  }

  // ---- signing in ----

  /// When a JWT runs out (its `exp`), in ms since epoch; null when it can't be read.
  static int? expiryOf(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      return j is Map && j['exp'] is int ? (j['exp'] as int) * 1000 : null;
    } catch (_) {
      return null;
    }
  }

  AbsSignIn _signInFrom(Object? j) {
    final user = j is Map ? j['user'] : null;
    if (user is! Map || user['id'] is! String) {
      throw const AbsException('The Audiobookshelf server\'s answer to the sign-in wasn\'t understood.', fromServer: true);
    }
    // 2.26+: an access token (and a refresh token, asked for with x-return-tokens); before that,
    // the one lasting token.
    final access = user['accessToken'] is String ? user['accessToken'] as String : user['token'] as String?;
    if (access == null || access.isEmpty) {
      throw const AbsException('The Audiobookshelf server didn\'t give a sign-in token.', fromServer: true);
    }
    token = access;
    return AbsSignIn(
      accessToken: access,
      refreshToken: user['refreshToken'] is String ? user['refreshToken'] as String : null,
      expiresMs: user['accessToken'] is String ? expiryOf(access) : null,
      userId: user['id'] as String,
      username: user['username'] as String?,
    );
  }

  /// Signs in with a user name and password. The access token is kept on this client.
  Future<AbsSignIn> signIn(String username, String password) async {
    token = null;
    try {
      return _signInFrom(await _json(
        'POST',
        uri('/login'),
        body: {'username': username, 'password': password},
        headers: const {'x-return-tokens': 'true'},
      ));
    } on AbsException catch (e) {
      if (e.status == 401 || e.status == 403) {
        throw const AbsException(
          'The Audiobookshelf server didn\'t accept the user name or password. Check them with Edit… in Settings › Servers.',
          fromServer: true,
          status: 401,
        );
      }
      rethrow;
    }
  }

  /// A new access token (and refresh token) from [refreshToken].
  Future<AbsSignIn> refresh(String refreshToken) async {
    token = null;
    return _signInFrom(await _json('POST', uri('/auth/refresh'), headers: {'x-refresh-token': refreshToken}));
  }

  /// Ends this sign-in on the server (its refresh token stops working). Never throws.
  Future<void> signOut(String? refreshToken) async {
    try {
      await _send('POST', uri('/logout'), headers: {if (refreshToken != null) 'x-refresh-token': refreshToken});
    } catch (_) {}
    token = null;
  }

  // ---- reading ----

  /// The server's libraries.
  Future<List<AbsLibrary>> libraries() async {
    final j = await _json('GET', uri('/api/libraries'));
    final list = j is Map ? j['libraries'] : null;
    return [
      for (final l in (list is List ? list : const []))
        if (l is Map && l['id'] is String) AbsLibrary(l['id'] as String, (l['name'] as String?) ?? '', '${l['mediaType'] ?? 'book'}'),
    ];
  }

  /// Every item in library [id], briefly (id, when it changed), page by page.
  Future<List<Map<String, dynamic>>> items(String libraryId, {AbsProgressCallback? onProgress}) async {
    final out = <Map<String, dynamic>>[];
    for (var page = 0;; page++) {
      final j = await _json('GET', uri('/api/libraries/$libraryId/items', {'limit': pageSize, 'page': page, 'minified': 1}));
      final results = j is Map ? j['results'] : null;
      final total = j is Map && j['total'] is int ? j['total'] as int : 0;
      final got = [for (final x in (results is List ? results : const [])) if (x is Map) Map<String, dynamic>.from(x)];
      out.addAll(got);
      onProgress?.call(out.length, total);
      if (got.length < pageSize || out.length >= total) break;
    }
    return out;
  }

  /// The full details of items [ids] (their files and chapters), a batch at a time.
  Future<List<Map<String, dynamic>>> fullItems(List<String> ids, {AbsProgressCallback? onProgress}) async {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i += batchSize) {
      final chunk = ids.sublist(i, i + batchSize > ids.length ? ids.length : i + batchSize);
      List<Map<String, dynamic>> got;
      try {
        final j = await _json('POST', uri('/api/items/batch/get'), body: {'libraryItemIds': chunk});
        final list = j is Map ? j['libraryItems'] : null;
        got = [for (final x in (list is List ? list : const [])) if (x is Map) Map<String, dynamic>.from(x)];
      } on AbsException catch (e) {
        if (e.status != 404) rethrow;
        // A server without the batch route: one at a time.
        got = [];
        for (final id in chunk) {
          final j = await _json('GET', uri('/api/items/$id', {'expanded': 1}));
          if (j is Map) got.add(Map<String, dynamic>.from(j));
        }
      }
      out.addAll(got);
      onProgress?.call(out.length, ids.length);
    }
    return out;
  }

  /// Where the user got to in every book.
  Future<List<AbsProgress>> progress() async {
    final j = await _json('GET', uri('/api/me'));
    final list = j is Map ? j['mediaProgress'] : null;
    return [for (final x in (list is List ? list : const [])) ?AbsProgress.fromJson(x)];
  }

  /// Tells the server where the user got to in item [itemId].
  Future<void> setProgress(String itemId, {required double currentTime, required double duration, required bool finished}) =>
      _json('PATCH', uri('/api/me/progress/$itemId'), body: {
        'currentTime': currentTime,
        'duration': duration,
        'progress': finished ? 1 : (duration > 0 ? (currentTime / duration).clamp(0, 1) : 0),
        'isFinished': finished,
      });

  // ---- addresses ----

  /// Where to play file [ino] of item [itemId] from (the access token in the address; see above).
  Uri streamUri(String itemId, String ino) => uri('/api/items/$itemId/file/$ino', {'token': token});

  /// Where to download it from (the sign-in goes in [mediaHeaders]).
  Uri downloadUri(String itemId, String ino) => uri('/api/items/$itemId/file/$ino/download');

  /// The item's cover, [width] wide.
  Uri coverUri(String itemId, {int width = 500}) => uri('/api/items/$itemId/cover', {'width': width});

  /// A cover picture's bytes, or null if there isn't one.
  Future<List<int>?> coverBytes(String itemId, {int width = 500}) async {
    try {
      final res = await _send('GET', coverUri(itemId, width: width), headers: const {'Accept': 'image/*'});
      return res.bodyBytes.isEmpty ? null : res.bodyBytes;
    } on AbsException {
      return null;
    }
  }

  void close() {
    if (_ownsHttp) _http.close();
  }
}
