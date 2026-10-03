// "Test connection" on Settings › Servers (0.1.46): is a server there, and is it what the user
// said it is? For the types HomeTunes can't stream from yet this only asks the server's public
// "who are you" address (no sign-in is sent), so a server can be set up now and used as soon as
// its type is supported:
//   Jellyfin / Emby: /System/Info/Public (JSON: ServerName, Version, ProductName)
//   Plex:            /identity (a small XML reply with the version)
//   Audiobookshelf:  /status (JSON: serverVersion), then /ping ({"success": true})
//   HomeTunes:       /api/info (JSON: {"app": "hometunes", "version": …}); our own server, still
//                    being built, will answer this
// Subsonic servers are signed in to for real (SubsonicClient.ping). Their sign-in is never sent
// over plain http to an address on the internet here (see isPlainHttpToInternet); connecting
// that way still asks first, on the main server.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../state/servers_model.dart' show ServerType;
import 'subsonic_client.dart';

/// What a test found.
class ProbeResult {
  /// The server answered as the right kind of server (and, for Subsonic, signed in).
  final bool ok;

  /// A sentence for the user.
  final String message;

  /// The address that worked, with its scheme (when a scheme had to be guessed).
  final String? url;
  const ProbeResult(this.ok, this.message, {this.url});
}

/// The addresses to try for [typed]: as typed when it has a scheme, else https then http.
List<String> candidateUrls(String typed) {
  var u = typed.trim();
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  if (u.isEmpty) return const [];
  if (u.startsWith('http://') || u.startsWith('https://')) return [u];
  return ['https://$u', 'http://$u'];
}

/// Checks [url] is a [type] server. Never throws.
Future<ProbeResult> probeServer(
  ServerType type,
  String url, {
  String username = '',
  String password = '',
  http.Client? client,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final urls = candidateUrls(url);
  if (urls.isEmpty) return const ProbeResult(false, 'Type the server\'s address first.');
  if (type == ServerType.subsonic) return _subsonic(urls, username, password, client);
  final c = client ?? http.Client();
  try {
    String? lastProblem;
    for (final base in urls) {
      try {
        final found = await _identify(type, base, c, timeout);
        if (found != null) {
          final later = type.streams
              ? ''
              : ' HomeTunes can\'t play from ${type.label} yet; it\'s saved and will be '
                    'used once that\'s added.';
          return ProbeResult(true, 'Found $found.$later', url: base);
        }
        lastProblem = 'Something answered at $base, but it doesn\'t look like a ${type.label} server.';
      } on TimeoutException {
        lastProblem = 'No answer from $base.';
      } catch (e) {
        lastProblem = 'Couldn\'t reach $base (${hideSecrets('$e')}).';
      }
    }
    return ProbeResult(false, lastProblem ?? 'Couldn\'t reach the server.');
  } finally {
    if (client == null) c.close();
  }
}

/// What the server says it is ("a Jellyfin server called "Den", version 10.9"), or null when it
/// isn't a [type] server.
Future<String?> _identify(ServerType type, String base, http.Client c, Duration timeout) async {
  Future<http.Response> get(String path) => c.get(Uri.parse('$base$path')).timeout(timeout);
  Map<String, dynamic>? json(http.Response r) {
    if (r.statusCode != 200) return null;
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  String version(Object? v) => v is String && v.isNotEmpty ? ', version $v' : '';
  switch (type) {
    case ServerType.jellyfin || ServerType.emby:
      final j = json(await get('/System/Info/Public'));
      if (j == null || (j['Id'] == null && j['ServerName'] == null)) return null;
      final product = (j['ProductName'] as String?) ?? '';
      final isJellyfin = product.toLowerCase().contains('jellyfin');
      // Both answer the same address; say which one it really is.
      final what = isJellyfin ? 'Jellyfin' : (product.isEmpty ? type.label : 'Emby');
      if ((type == ServerType.jellyfin) != isJellyfin && product.isNotEmpty) {
        return 'a $what server (not ${type.label}: choose $what as the type)${version(j['Version'])}';
      }
      final name = j['ServerName'] is String ? ' called "${j['ServerName']}"' : '';
      return 'a $what server$name${version(j['Version'])}';
    case ServerType.plex:
      final r = await get('/identity');
      final body = utf8.decode(r.bodyBytes, allowMalformed: true);
      if (r.statusCode != 200 || !body.contains('MediaContainer')) return null;
      final v = RegExp(r'version="([^"]+)"').firstMatch(body)?.group(1);
      return 'a Plex server${version(v)}';
    case ServerType.audiobookshelf:
      final status = json(await get('/status'));
      if (status != null && (status['serverVersion'] != null || status['app'] == 'audiobookshelf')) {
        return 'an Audiobookshelf server${version(status['serverVersion'])}';
      }
      final ping = json(await get('/ping'));
      return ping != null && ping['success'] == true ? 'an Audiobookshelf server' : null;
    case ServerType.hometunes:
      final j = json(await get('/api/info'));
      if (j == null || '${j['app']}'.toLowerCase() != 'hometunes') return null;
      return 'a HomeTunes server${version(j['version'])}';
    case ServerType.subsonic:
      return null; // signed in to instead (_subsonic)
  }
}

Future<ProbeResult> _subsonic(List<String> urls, String username, String password, http.Client? client) async {
  if (username.trim().isEmpty) return const ProbeResult(false, 'Type the user name to sign in with.');
  String? lastError;
  for (final base in urls) {
    // The sign-in never goes over plain http to the internet from a test.
    if (base.startsWith('http://') && isPlainHttpToInternet(base) && urls.length > 1) {
      lastError ??=
          'It didn\'t answer over a secure (https) connection. Make it the main music server to be '
          'asked about connecting over plain http.';
      continue;
    }
    final c = SubsonicClient(
      ServerConfig(url: base, username: username, password: password),
      httpClient: client,
    );
    try {
      await c.ping();
      return ProbeResult(true, 'Signed in to the Subsonic server at $base.', url: base);
    } on SubsonicException catch (e) {
      lastError = e.message;
      if (e.fromServer) break; // a real answer (wrong password): no point trying http as well
    } catch (e) {
      lastError = 'That server address doesn\'t look right (${hideSecrets('$e')}).';
    } finally {
      if (client == null) c.close();
    }
  }
  return ProbeResult(false, lastError ?? 'Couldn\'t reach the server.');
}
