// The connection to the music server (refactor phase 3, 8 Oct 2026; was part of LibraryModel).
// It keeps the server's password in the system's protected storage (0.1.17), makes the Subsonic
// client and its cover cache from the server settings, and tries a typed address (https first,
// then http, asking before plain http on the internet: 0.1.21, security review #4).
// LibraryModel still decides what happens to the library: saving the settings, syncing the
// server's songs, forgetting them.
import 'package:path/path.dart' as p;

import '../services/secret_store.dart';
import '../services/server_art_cache.dart';
import '../services/subsonic_client.dart';
import 'settings/settings_groups.dart' show ServerSettings;

class ServerConnection {
  ServerConnection(this.settings, {required this.secrets, required String artDir}) : artCacheDir = p.join(artDir, 'server');

  /// The server's address, login and switches (settings.json).
  final ServerSettings settings;

  /// Where the server password is kept (see secret_store.dart). Null on platforms without
  /// protected storage, where it stays in settings.json as before.
  final SecretStore? secrets;

  /// Downloaded server covers for the system media controls (0.1.21, security review #2).
  final String artCacheDir;

  /// What [connectionTo] gives when the server only answered over plain http on the internet,
  /// and the user hasn't agreed to that yet.
  static const httpConsentNeeded = 'HTTP_CONSENT_NEEDED';

  /// A URL's host, lower case ('' when it isn't a URL).
  static String hostOf(String url) => Uri.tryParse(url)?.host.toLowerCase() ?? '';

  SubsonicClient? _client;
  ServerArtCache? _art;

  /// The connection to the server, or null when there's no server or it's switched off.
  SubsonicClient? get client => _client;

  /// The server's covers as files (for the media controls), or null with no connection.
  ServerArtCache? get art => _art;

  /// Makes a fresh connection from the current settings (or none). Syncs check
  /// `identical(c, client)` to notice the connection was replaced mid-sync.
  void reconnect() {
    _client?.close();
    _art?.close();
    final s = settings;
    final c = _client = s.serverEnabled && s.server.isComplete ? SubsonicClient(s.server) : null;
    _art = c == null ? null : ServerArtCache(artCacheDir, c);
  }

  /// Fills in the server's password from the protected storage, or moves a plain-text one from
  /// settings.json into it. Returns true when settings.json should be saved again without it.
  Future<bool> loadPassword() async {
    final store = secrets;
    final server = settings.server;
    settings.passwordInSettings = store == null;
    if (store == null || server.url.trim().isEmpty) return false;
    final key = SecretStore.serverPasswordKey(server.url, server.username);
    if (server.password.isNotEmpty) {
      if (await store.write(key, server.password)) return true;
      settings.passwordInSettings = true; // couldn't move it: keep it where it is
      return false;
    }
    final saved = await store.read(key);
    if (saved != null) settings.server = ServerConfig(url: server.url, username: server.username, password: saved);
    return false;
  }

  /// Saves [config]'s password in the protected storage (and forgets [previous]'s, if that was
  /// a different server or user). Falls back to settings.json if that isn't possible.
  Future<void> storePassword(ServerConfig config, {ServerConfig? previous}) async {
    final store = secrets;
    if (store == null) {
      settings.passwordInSettings = true;
      return;
    }
    final key = SecretStore.serverPasswordKey(config.url, config.username);
    if (previous != null && previous.url.trim().isNotEmpty) {
      final oldKey = SecretStore.serverPasswordKey(previous.url, previous.username);
      if (oldKey != key) await store.delete(oldKey);
    }
    if (config.password.isEmpty) {
      await store.delete(key);
      settings.passwordInSettings = false;
    } else {
      settings.passwordInSettings = !await store.write(key, config.password);
    }
  }

  /// Removes the current server's password from the protected storage.
  Future<void> forgetPassword() async {
    final server = settings.server;
    if (server.url.trim().isNotEmpty) {
      await secrets?.delete(SecretStore.serverPasswordKey(server.url, server.username));
    }
  }

  /// Deletes the downloaded server covers.
  Future<void> clearArtCache() => ServerArtCache.clear(artCacheDir);

  /// Tries [config]'s details with a throwaway connection, so bad details never get saved.
  ///
  /// HomeTunes (0.1.17): an address typed without http:// or https:// is tried with https://
  /// first (so the login token isn't sent in the clear when the server supports it), then
  /// http://; whichever works comes back with its scheme.
  ///
  /// HomeTunes (0.1.21, security review #4): when https doesn't answer and the address is on the
  /// internet (not the home network or Tailscale), http isn't tried on its own: [httpConsentNeeded]
  /// comes back instead, unless [allowPlainHttp] (the user said yes) or the host was allowed
  /// before. An address typed with http:// is the user's choice.
  ///
  /// Gives the details that worked, or the error to show.
  Future<({ServerConfig? working, String? error})> connectionTo(ServerConfig config, {bool allowPlainHttp = false}) async {
    final typed = config.url.trim();
    final hasScheme = typed.startsWith('http://') || typed.startsWith('https://');
    final attempts = hasScheme
        ? [config]
        : [
            ServerConfig(url: 'https://$typed', username: config.username, password: config.password),
            ServerConfig(url: 'http://$typed', username: config.username, password: config.password),
          ];
    String? lastError;
    for (final attempt in attempts) {
      if (!hasScheme && attempt.url.startsWith('http://') && isPlainHttpToInternet(attempt.url)) {
        final host = hostOf(attempt.url);
        if (!allowPlainHttp && host != settings.httpAllowedHost) return (working: null, error: httpConsentNeeded);
      }
      final test = SubsonicClient(attempt);
      try {
        await test.ping();
        return (working: attempt, error: null);
      } on SubsonicException catch (e) {
        lastError = e.message;
        // A real answer from the server (e.g. wrong password): no point trying http as well.
        if (e.fromServer) break;
      } catch (e) {
        // e.g. an address that isn't a valid URL at all.
        lastError = 'That server address doesn\'t look right (${hideSecrets('$e')})';
      } finally {
        test.close();
      }
    }
    return (working: null, error: lastError);
  }

  /// Whether [working] (typed without a scheme) only works over plain http on the internet,
  /// so its host should be remembered as allowed.
  static bool needsHttpAllowance(String typedUrl, ServerConfig working) {
    final typed = typedUrl.trim();
    final hasScheme = typed.startsWith('http://') || typed.startsWith('https://');
    return !hasScheme && working.url.startsWith('http://') && isPlainHttpToInternet(working.url);
  }
}
