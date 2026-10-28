// Talks to a Jellyfin server (0.2.1): signing in, listing its video libraries and what's in them,
// the addresses to play, download and show pictures from, and telling it where you got to.
//
// The user asked (25 Oct 2026) for HomeTunes to stream from their Jellyfin server; videos first,
// music and audiobooks later. state/server_videos.dart turns what this returns into the Videos
// tab's VideoItems.
//
// Signing in: the user name and password saved in Settings › Servers are sent once to
// /Users/AuthenticateByName; the server answers with an access token, which is what every later
// request carries. Like the music server's password (security review, 0.1.21), the token never
// goes into an address: it travels in the Authorization header ("MediaBrowser … Token=…"), so it
// can't turn up in a log, an error message or the system's media controls. The player gets the
// same header (media_kit's httpHeaders), as do downloads and pictures.
//
// Built against Jellyfin's own API description (/api-docs/openapi.json on the user's server,
// version 12.3.0): only the newer routes are used (/UserViews, /Items?userId=, /UserItems/…,
// /UserPlayedItems/…), which older 10.9+ servers have too.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'subsonic_client.dart' show hideSecrets;

/// Something went wrong talking to the server. [message] is a sentence for the user and never
/// holds the token.
class JellyfinException implements Exception {
  final String message;

  /// The server answered (as opposed to not being reachable).
  final bool fromServer;

  /// The HTTP status, when the server answered.
  final int? status;
  const JellyfinException(this.message, {this.fromServer = false, this.status});

  /// The sign-in is no longer accepted (signed out on the server, or the password changed).
  bool get signedOut => status == 401;

  @override
  String toString() => message;
}

/// What signing in gave.
class JellyfinSignIn {
  final String token;
  final String userId;
  final String serverId;
  final String? serverName;
  const JellyfinSignIn({required this.token, required this.userId, required this.serverId, this.serverName});
}

/// One of the user's libraries ("Films", "TV Shows", "Home videos").
class JellyfinView {
  final String id;
  final String name;

  /// Jellyfin's kind of library: movies, tvshows, homevideos, music, books, boxsets, playlists…
  /// (null for a plain folder library).
  final String? collectionType;
  const JellyfinView(this.id, this.name, this.collectionType);

  /// Libraries that hold videos HomeTunes shows.
  bool get holdsVideos => const {null, 'movies', 'tvshows', 'homevideos', 'mixed', 'folders'}.contains(collectionType);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, if (collectionType != null) 'type': collectionType};

  static JellyfinView? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return JellyfinView(j['id'] as String, (j['name'] as String?) ?? '', j['type'] as String?);
  }
}

/// A page of a long list, and how far through it is.
typedef JellyfinProgress = void Function(int done, int total);

/// Jellyfin counts time in ticks: 10,000,000 to a second.
int ticksOf(Duration d) => d.inMicroseconds * 10;
Duration durationOfTicks(Object? ticks) => ticks is num ? Duration(microseconds: ticks ~/ 10) : Duration.zero;

class JellyfinClient {
  JellyfinClient({
    required String baseUrl,
    required this.deviceId,
    this.deviceName = 'HomeTunes',
    this.appVersion = '0',
    this.token,
    this.userId,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  })  : baseUrl = _trim(baseUrl),
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  static const clientName = 'HomeTunes';

  /// The server's address, without a trailing slash.
  final String baseUrl;

  /// This install's own id, so the server lists it once under Devices however often it signs in.
  final String deviceId;
  final String deviceName;
  final String appVersion;

  /// The access token and user, once signed in.
  String? token;
  String? userId;

  final Duration timeout;
  final http.Client _http;
  final bool _ownsHttp;

  static String _trim(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// Quotes can't appear inside the header's values.
  static String _clean(String s) => s.replaceAll(RegExp(r'["\r\n,=]'), ' ').trim();

  /// The Authorization header Jellyfin expects ("MediaBrowser Client=…, Token=…").
  String get authorization {
    final parts = [
      'Client="$clientName"',
      'Device="${_clean(deviceName)}"',
      'DeviceId="${_clean(deviceId)}"',
      'Version="${_clean(appVersion)}"',
      if (token != null) 'Token="$token"',
    ];
    return 'MediaBrowser ${parts.join(', ')}';
  }

  /// Headers for the player, downloads and pictures: the sign-in, never in the address.
  Map<String, String> get mediaHeaders => {'Authorization': authorization};

  Map<String, String> get _jsonHeaders => {
        'Authorization': authorization,
        'Accept': 'application/json',
      };

  Uri uri(String path, [Map<String, Object?> query = const {}]) {
    final q = <String, String>{
      for (final e in query.entries)
        if (e.value != null) e.key: e.value is List ? (e.value as List).join(',') : '${e.value}',
    };
    return Uri.parse('$baseUrl$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  String _need() {
    final u = userId;
    if (token == null || u == null) throw const JellyfinException('Not signed in to the Jellyfin server yet.');
    return u;
  }

  Future<http.Response> _send(String method, Uri u, {Object? body}) async {
    final headers = {..._jsonHeaders, if (body != null) 'Content-Type': 'application/json'};
    http.Response res;
    try {
      final req = http.Request(method, u)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout)).timeout(timeout);
    } on TimeoutException {
      throw JellyfinException('No answer from $baseUrl.');
    } catch (e) {
      throw JellyfinException('Couldn\'t reach $baseUrl (${hideSecrets('$e')}).');
    }
    if (res.statusCode == 401) {
      throw JellyfinException('The Jellyfin server no longer accepts the sign-in.', fromServer: true, status: 401);
    }
    if (res.statusCode >= 400) {
      throw JellyfinException('The Jellyfin server replied ${res.statusCode}.', fromServer: true, status: res.statusCode);
    }
    return res;
  }

  Future<Object?> _json(String method, Uri u, {Object? body}) async {
    final res = await _send(method, u, body: body);
    if (res.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw const JellyfinException('The Jellyfin server sent something HomeTunes couldn\'t read.', fromServer: true);
    }
  }

  // ---- signing in ----

  /// Signs in with a user name and password. The token is kept on this client and returned.
  Future<JellyfinSignIn> signIn(String username, String password) async {
    token = null;
    Object? j;
    try {
      j = await _json('POST', uri('/Users/AuthenticateByName'), body: {'Username': username, 'Pw': password});
    } on JellyfinException catch (e) {
      if (e.status == 401 || e.status == 403) {
        throw JellyfinException(
          'The Jellyfin server didn\'t accept the user name or password. Check them with Edit… in Settings › Servers.',
          fromServer: true,
          status: e.status,
        );
      }
      rethrow;
    }
    if (j is! Map || j['AccessToken'] is! String || j['User'] is! Map || (j['User'] as Map)['Id'] is! String) {
      throw const JellyfinException('The server answered, but not like a Jellyfin server signing in.', fromServer: true);
    }
    token = j['AccessToken'] as String;
    userId = (j['User'] as Map)['Id'] as String;
    return JellyfinSignIn(
      token: token!,
      userId: userId!,
      serverId: (j['ServerId'] as String?) ?? '',
      serverName: null,
    );
  }

  /// Signs this device out on the server (the token stops working). Never throws.
  Future<void> signOut() async {
    if (token == null) return;
    try {
      await _send('POST', uri('/Sessions/Logout'));
    } catch (_) {}
    token = null;
  }

  // ---- what's on the server ----

  /// The user's libraries.
  Future<List<JellyfinView>> views() async {
    final u = _need();
    final j = await _json('GET', uri('/UserViews', {'userId': u}));
    final items = j is Map ? j['Items'] : null;
    return [
      for (final x in (items is List ? items : const []))
        if (x is Map && x['Id'] is String)
          JellyfinView(x['Id'] as String, (x['Name'] as String?) ?? '', x['CollectionType'] as String?),
    ];
  }

  /// The details asked for with every video.
  static const videoFields = [
    'Overview',
    'Genres',
    'DateCreated',
    'MediaSources',
    'ProductionYear',
    'Width',
    'Height',
    'ParentId',
    'SeriesId',
    'SeasonId',
    'SeriesName',
    'SeasonName',
    'Container',
  ];

  /// Everything of [types] inside library [parentId], a page at a time ([pageSize] each), with
  /// this user's place and watched mark (UserData). Missing (not yet aired) episodes are left out.
  Future<List<Map<String, dynamic>>> items({
    required String parentId,
    required List<String> types,
    List<String> fields = videoFields,
    int pageSize = 200,
    JellyfinProgress? onProgress,
  }) async {
    final u = _need();
    final out = <Map<String, dynamic>>[];
    var start = 0;
    while (true) {
      final j = await _json(
        'GET',
        uri('/Items', {
          'userId': u,
          'parentId': parentId,
          'recursive': 'true',
          'includeItemTypes': types,
          'excludeLocationTypes': 'Virtual',
          'fields': fields,
          'enableUserData': 'true',
          'enableImageTypes': 'Primary,Thumb,Backdrop',
          'imageTypeLimit': '1',
          'sortBy': 'SortName',
          'startIndex': '$start',
          'limit': '$pageSize',
          'enableTotalRecordCount': 'true',
        }),
      );
      final page = j is Map && j['Items'] is List ? j['Items'] as List : const [];
      final total = j is Map && j['TotalRecordCount'] is int ? j['TotalRecordCount'] as int : out.length + page.length;
      for (final x in page) {
        if (x is Map) out.add(Map<String, dynamic>.from(x));
      }
      start += page.length;
      onProgress?.call(start, total);
      if (page.isEmpty || page.length < pageSize || start >= total) break;
    }
    return out;
  }

  // ---- addresses (the token goes in [mediaHeaders], never in these) ----

  /// The original file, as it is on the server ("direct play").
  Uri streamUri(String itemId, {String? mediaSourceId, String? container}) => uri(
        container == null || container.isEmpty ? '/Videos/$itemId/stream' : '/Videos/$itemId/stream.$container',
        {'static': 'true', 'mediaSourceId': mediaSourceId ?? itemId, 'deviceId': deviceId},
      );

  /// A copy the server converts as it sends it (H.264 and AAC in Matroska), for a device that
  /// can't play the original. [maxHeight] limits the picture (1080, 720, 480); [start] is where to
  /// begin (timestamps are kept, so the player's clock matches the original).
  Uri convertedUri(
    String itemId, {
    String? mediaSourceId,
    int? maxHeight,
    int? videoBitRate,
    int audioBitRate = 192000,
    Duration? start,
    String? playSessionId,
    int? audioStreamIndex,
  }) =>
      uri('/Videos/$itemId/stream.mkv', {
        'static': 'false',
        'mediaSourceId': mediaSourceId ?? itemId,
        'deviceId': deviceId,
        'playSessionId': playSessionId,
        'container': 'mkv',
        'videoCodec': 'h264',
        'audioCodec': 'aac',
        'audioBitRate': '$audioBitRate',
        'maxAudioChannels': '6',
        if (maxHeight != null) 'maxHeight': '$maxHeight',
        'videoBitRate': '${videoBitRate ?? bitRateFor(maxHeight)}',
        if (audioStreamIndex != null) 'audioStreamIndex': '$audioStreamIndex',
        if (start != null && start > Duration.zero) 'startTimeTicks': '${ticksOf(start)}',
        if (start != null && start > Duration.zero) 'copyTimestamps': 'true',
      });

  /// A sensible picture bitrate for a converted copy of [maxHeight] lines.
  static int bitRateFor(int? maxHeight) => switch (maxHeight) {
        null => 20000000,
        >= 2160 => 40000000,
        >= 1080 => 10000000,
        >= 720 => 4000000,
        _ => 1500000,
      };

  /// The original file, for saving (downloads).
  Uri downloadUri(String itemId) => uri('/Items/$itemId/Download');

  /// A subtitle file stored beside the video on the server.
  Uri subtitleUri(String itemId, int index, String format, {String? mediaSourceId}) =>
      uri('/Videos/$itemId/${mediaSourceId ?? itemId}/Subtitles/$index/Stream.$format');

  /// A picture of an item: Primary (poster / episode still), Thumb (wide), Backdrop.
  Uri imageUri(String itemId, String type, {String? tag, int maxWidth = 600}) =>
      uri('/Items/$itemId/Images/$type', {'tag': tag, 'maxWidth': '$maxWidth', 'quality': '85'});

  /// Downloads a picture; null when there isn't one. Never throws.
  Future<List<int>?> imageBytes(Uri u, {int maxBytes = 10 << 20}) async {
    try {
      final req = http.Request('GET', u)..headers.addAll(mediaHeaders);
      final res = await http.Response.fromStream(await _http.send(req).timeout(timeout)).timeout(timeout);
      final type = (res.headers['content-type'] ?? '').toLowerCase();
      if (res.statusCode != 200 || !type.startsWith('image/') || res.bodyBytes.isEmpty || res.bodyBytes.length > maxBytes) {
        return null;
      }
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  // ---- where you got to ----

  Map<String, Object?> _report(String itemId, Duration at,
          {bool paused = false, String? playSessionId, bool converted = false}) =>
      {
        'ItemId': itemId,
        'MediaSourceId': itemId,
        'PositionTicks': ticksOf(at),
        'IsPaused': paused,
        'CanSeek': !converted,
        'PlayMethod': converted ? 'Transcode' : 'DirectStream',
        'PlaySessionId': ?playSessionId,
      };

  /// Playing has started (the server shows it under its dashboard's active devices).
  Future<void> reportStart(String itemId, Duration at, {String? playSessionId, bool converted = false}) async {
    _need();
    await _send('POST', uri('/Sessions/Playing'),
        body: _report(itemId, at, playSessionId: playSessionId, converted: converted));
  }

  /// Where it's got to.
  Future<void> reportProgress(String itemId, Duration at,
      {bool paused = false, String? playSessionId, bool converted = false}) async {
    _need();
    await _send('POST', uri('/Sessions/Playing/Progress'),
        body: _report(itemId, at, paused: paused, playSessionId: playSessionId, converted: converted));
  }

  /// Playing stopped at [at]: the server saves the place, and marks it watched near the end.
  Future<void> reportStopped(String itemId, Duration at, {String? playSessionId}) async {
    _need();
    await _send('POST', uri('/Sessions/Playing/Stopped'), body: {
      'ItemId': itemId,
      'MediaSourceId': itemId,
      'PositionTicks': ticksOf(at),
      'PlaySessionId': ?playSessionId,
    });
  }

  /// Marks an item watched or not.
  Future<void> setPlayed(String itemId, bool played) async {
    final u = _need();
    await _send(played ? 'POST' : 'DELETE', uri('/UserPlayedItems/$itemId', {'userId': u}));
  }

  /// Sets the place and watched mark straight away (catching up after watching offline).
  Future<void> setPlace(String itemId, {required Duration position, required bool played, DateTime? when}) async {
    final u = _need();
    await _send('POST', uri('/UserItems/$itemId/UserData', {'userId': u}), body: {
      'PlaybackPositionTicks': played ? 0 : ticksOf(position),
      'Played': played,
      if (when != null) 'LastPlayedDate': when.toUtc().toIso8601String(),
    });
  }

  void close() {
    if (_ownsHttp) _http.close();
  }
}
