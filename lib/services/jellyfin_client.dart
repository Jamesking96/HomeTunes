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
import 'dart:isolate';
import 'dart:typed_data';

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

/// One of the server's collections (box sets): its films' ids (9 Nov 2026).
class JellyfinCollection {
  const JellyfinCollection({required this.id, required this.name, this.overview, this.items = const []});
  final String id;
  final String name;
  final String? overview;
  final List<String> items;
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

  /// Answers this big (or bigger) are decoded in an isolate (0.2.12).
  static const bigAnswer = 64 * 1024;

  /// Static, so the isolate is handed only the bytes, never this client.
  static Future<Object?> _decodeInBackground(Uint8List bytes) => Isolate.run(() => jsonDecode(utf8.decode(bytes)));

  Future<Object?> _json(String method, Uri u, {Object? body}) async {
    final res = await _send(method, u, body: body);
    if (res.bodyBytes.isEmpty) return null;
    try {
      final bytes = res.bodyBytes;
      // A big answer (a page of 200 videos with their stream details) is read in the background
      // (0.2.12): on the test TV each one held the screen and the remote for up to a
      // second while the server was read after opening.
      if (bytes.length >= bigAnswer) return await _decodeInBackground(bytes);
      return jsonDecode(utf8.decode(bytes));
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

  /// The server's own collections of films (box sets, 9 Nov 2026): each one's name and the ids
  /// of the films in it. Offered as suggested film collections; nothing is changed on the server.
  Future<List<({String id, String name, List<String> items})>> boxSets() async => [
        for (final c in await collections())
          if (c.items.length >= 2) (id: c.id, name: c.name, items: c.items),
      ];

  // ---- collections, for sharing them (9 Nov 2026; docs/ai-context/09_COLLECTION_SHARING_PLAN.md) ----

  /// Every collection (box set) this user can see, with its films' ids.
  Future<List<JellyfinCollection>> collections() async {
    final u = _need();
    final j = await _json('GET', uri('/Items', {
      'userId': u,
      'recursive': 'true',
      'includeItemTypes': 'BoxSet',
      'fields': 'Overview',
      'sortBy': 'SortName',
      'limit': '1000',
    }));
    final sets = j is Map && j['Items'] is List ? j['Items'] as List : const [];
    final out = <JellyfinCollection>[];
    for (final s in sets) {
      if (s is! Map || s['Id'] is! String || s['Name'] is! String) continue;
      final k = await _json('GET', uri('/Items', {
        'userId': u,
        'parentId': s['Id'] as String,
        'includeItemTypes': 'Movie',
        'limit': '1000',
      }));
      final films = k is Map && k['Items'] is List ? k['Items'] as List : const [];
      out.add(JellyfinCollection(
        id: s['Id'] as String,
        name: (s['Name'] as String).trim(),
        overview: s['Overview'] is String ? s['Overview'] as String : null,
        items: [for (final f in films) if (f is Map && f['Id'] is String) f['Id'] as String],
      ));
    }
    return out;
  }

  /// What this user may do with collections: make them and change their films ([manage]: an
  /// administrator, or "Allow this user to manage collections"), and rename them or change their
  /// description ([admin] only).
  Future<({bool admin, bool manage})> collectionRights() async {
    _need();
    final j = await _json('GET', uri('/Users/Me'));
    final p = j is Map && j['Policy'] is Map ? j['Policy'] as Map : const {};
    final admin = p['IsAdministrator'] == true;
    return (admin: admin, manage: admin || p['EnableCollectionManagement'] == true);
  }

  /// Makes a collection called [name] holding [items]. Returns its id.
  Future<String> createCollection(String name, List<String> items) async {
    _need();
    final j = await _json('POST', uri('/Collections', {'name': name, if (items.isNotEmpty) 'ids': items.take(40).toList()}));
    final id = j is Map ? j['Id'] : null;
    if (id is! String || id.isEmpty) {
      throw const JellyfinException('The Jellyfin server didn\'t say which collection it made.', fromServer: true);
    }
    if (items.length > 40) await addToCollection(id, items.sublist(40));
    return id;
  }

  /// Adds / takes out films (a few at a time, so the address stays short).
  Future<void> addToCollection(String id, List<String> items) => _collectionItems('POST', id, items);
  Future<void> removeFromCollection(String id, List<String> items) => _collectionItems('DELETE', id, items);

  Future<void> _collectionItems(String method, String id, List<String> items) async {
    _need();
    for (var i = 0; i < items.length; i += 40) {
      await _send(method, uri('/Collections/$id/Items', {'ids': items.skip(i).take(40).toList()}));
    }
  }

  /// Renames a collection and sets its description (administrators only).
  Future<void> updateCollection(String id, {required String name, String? overview}) async {
    final u = _need();
    final j = await _json('GET', uri('/Items/$id', {'userId': u}));
    if (j is! Map) throw const JellyfinException('The Jellyfin server sent something HomeTunes couldn\'t read.', fromServer: true);
    final item = Map<String, dynamic>.from(j)
      ..['Name'] = name
      ..['Overview'] = overview ?? '';
    await _send('POST', uri('/Items/$id'), body: item);
  }

  /// Deletes an item (a collection: its films stay).
  Future<void> deleteItem(String id) async {
    _need();
    await _send('DELETE', uri('/Items/$id'));
  }

  /// HomeTunes' own note on the server, kept with this user's display settings (any user may
  /// keep these): [CustomPrefs] values are text. Returns the whole record, to write back.
  Future<Map<String, dynamic>> readNote(String name) async {
    final u = _need();
    final j = await _json('GET', uri('/DisplayPreferences/$name', {'userId': u, 'client': clientName}));
    return j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{'Id': name};
  }

  Future<void> writeNote(String name, Map<String, dynamic> record) async {
    final u = _need();
    await _send('POST', uri('/DisplayPreferences/$name', {'userId': u, 'client': clientName}),
        body: {...record, 'Id': name, 'Client': clientName});
  }

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

  /// A copy the server converts in segments (HLS, 0.2.7), for playing and downloading a converted
  /// copy. Unlike [convertedUri] (one file sent while it's being made, so it has no length and no
  /// index: the player only knows as much of the film as it has received, and a download has no
  /// size), the playlist lists every segment of the whole video up front: the player knows the
  /// length and can go anywhere in it (the server converts from there), and a download knows how
  /// far it has got and when it has everything. Video the device can play already (H.264 within
  /// [maxHeight]) is copied rather than converted. The sign-in goes in [mediaHeaders]; the server's
  /// playlists point at the next ones with these same settings.
  Uri hlsUri(
    String itemId, {
    String? mediaSourceId,
    int? maxHeight,
    int? videoBitRate,
    int audioBitRate = 192000,
    String? playSessionId,
    int? audioStreamIndex,
    int segmentLength = 6,
  }) =>
      uri('/Videos/$itemId/master.m3u8', {
        'MediaSourceId': mediaSourceId ?? itemId,
        'DeviceId': deviceId,
        'PlaySessionId': playSessionId,
        'VideoCodec': 'h264',
        'AudioCodec': 'aac',
        'SegmentContainer': 'ts',
        'SegmentLength': '$segmentLength',
        'MinSegments': '1',
        'BreakOnNonKeyFrames': 'false',
        'AudioBitRate': '$audioBitRate',
        'MaxAudioChannels': '6',
        'TranscodingMaxAudioChannels': '6',
        if (maxHeight != null) 'MaxHeight': '$maxHeight',
        'VideoBitRate': '${videoBitRate ?? bitRateFor(maxHeight)}',
        if (audioStreamIndex != null) 'AudioStreamIndex': '$audioStreamIndex',
        'EnableAdaptiveBitrateStreaming': 'false',
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
        // A converted copy comes in segments (0.2.7), so it can be moved through too.
        'CanSeek': true,
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
