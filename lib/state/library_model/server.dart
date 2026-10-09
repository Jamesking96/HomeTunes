// Part of LibraryModel (refactor phase 10, 9 Oct 2026: library_model.dart was over 1,500 lines).
// The music server: connecting (with the plain-http question), switching it on and off, forgetting
// it, and syncing its songs.
part of '../library_model.dart';

extension LibraryServer on LibraryModel {
  /// Shows or leaves out the audiobooks found on the music server.
  Future<void> setServerBooks(bool on) async {
    serverBooks = on;
    // Changes which files go on the Books tab, so everything has to be rebuilt.
    _rebuild();
    _changed();
    await _saveSettings();
  }

  /// Saves server details after checking they work. Returns an error message or null.
  ///
  /// HomeTunes (0.1.17): an address typed without http:// or https:// is tried with https://
  /// first (so the login token isn't sent in the clear when the server supports it), then
  /// http://; whichever works is saved with its scheme. The password goes into the system's
  /// protected storage rather than settings.json.
  ///
  /// HomeTunes (0.1.21, security review #4): when https doesn't answer and the address is on the
  /// internet (not the home network or Tailscale), http isn't tried on its own any more: the
  /// login would travel where others could read it. [LibraryModel.httpConsentNeeded] comes back instead, and
  /// Settings asks; calling again with [allowPlainHttp] (the user said yes) tries http and
  /// remembers the answer for that server. An address typed with http:// is the user's choice.
  Future<String?> connectServer(ServerConfig config, {bool allowPlainHttp = false}) async {
    final (:working, :error) = await connection.connectionTo(config, allowPlainHttp: allowPlainHttp);
    if (working == null) return error;
    if (ServerConnection.needsHttpAllowance(config.url, working)) {
      httpAllowedHost = ServerConnection.hostOf(working.url);
    }
    final previous = server;
    server = working;
    serverEnabled = true;
    await connection.storePassword(working, previous: previous);
    _rebuildClient();
    await _saveSettings();
    await syncServer();
    return null;
  }

  /// The server on/off switch. Turning it on syncs, if we don't have its songs yet.
  Future<void> setServerEnabled(bool on) async {
    serverEnabled = on;
    _rebuildClient();
    await _saveSettings();
    _rebuild();
    if (on && _remote.isEmpty) await syncServer();
  }

  /// Removes the server's details and its songs.
  Future<void> forgetServer() async {
    // Its password is removed from the protected storage too.
    await connection.forgetPassword();
    server = const ServerConfig(url: '', username: '', password: '');
    serverEnabled = false;
    httpAllowedHost = null;
    _remote = [];
    _rebuildClient();
    await connection.clearArtCache();
    await _saveSettings();
    await _saveLibrary();
    _rebuild();
  }

  /// Fetches the server's whole song list (album by album) and replaces the server songs.
  Future<void> syncServer() => _enqueue(() async {
        final c = _client;
        if (c == null) return;
        error = null;
        status = 'Connecting to server…';
        _changed();
        try {
          final result = await c.fetchAllTracks(onProgress: (done, total) {
            status = 'Syncing server albums $done / $total';
          });
          status = null;
          // The server may have been forgotten or switched off while we synced.
          if (!identical(c, _client)) return;
          _remote = result.tracks;
          await _saveLibrary();
          if (result.failedAlbums > 0) {
            error = 'Synced, but ${result.failedAlbums} album(s) could not be read from the server.';
          }
        } catch (e) {
          status = null;
          // Cancelled by "Forget server" / switching it off: not an error.
          if (!identical(c, _client)) return;
          error = 'Server sync failed: ${hideSecrets('$e')}';
        }
      });

  /// After a scan: follows songs that moved to their new place, and keeps the
  /// details of songs that have gone (if anything refers to them) so they
  /// come back as they were if the file returns.
  Future<void> _reconcile(Map<String, Track> previous) async {
    // Everything we knew of before the scan: last scan's songs plus ones already missing.
    final known = {for (final t in _missing) t.id: t, ...previous};
    final found = {for (final t in _local) t.id};
    final gone = [for (final t in known.values) if (!found.contains(t.id)) t];
    if (gone.isEmpty) {
      _missing = [];
      return;
    }
    // Songs that vanished and songs that are new may be the same files in a new place
    // (track_matching.dart pairs them up). Their edits, playlists etc. move to the new id.
    final added = [for (final t in _local) if (!known.containsKey(t.id)) t];
    final moved = matchMovedTracks(gone, added);
    if (moved.isNotEmpty) await _remapIds(moved);
    // Of the rest, keep only the ones something still refers to; the others are simply gone.
    final referenced = referencedIds;
    _missing = [
      for (final t in gone)
        if (!moved.containsKey(t.id) && referenced.contains(t.id)) t
    ];
  }
}
