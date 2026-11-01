// Audiobooks from Audiobookshelf servers (0.2.7): signs in, reads the server's book libraries into
// the Books tab, plays from it and keeps where you got to the same on both sides.
//
// The user asked (1 Nov 2026) for the servers to support Audiobookshelf, and chose: audiobooks
// only (podcasts later, if ever), places kept in step both ways, and every download feature
// (Download, Keep offline, temporary copies). Every Audiobookshelf server in Settings › Servers
// that's switched on for Audiobooks is read:
//   - Signing in uses the user name and password saved for it (ServersModel keeps the password in
//     protected storage). The server's refresh token goes there too, under its own key; the access
//     token (an hour long) is only kept in memory and renewed with it before it runs out. When the
//     refresh token is refused (a week unused, or signed out), HomeTunes signs in again once.
//   - Each book becomes Tracks, one per audio file (ids `abs:<server>:<item>:<ino>`, see
//     remote_books.dart), with the book's title, author, narrator, series, year, description and
//     chapters, given to LibraryModel, which groups each item's files into one book. Covers are
//     downloaded into <data>/art/server-book/<server>/ (so the Books tab works without the server,
//     and the media controls never get an address). What was read is kept in server_books.json,
//     so the tab isn't empty when the server is off; only books changed since are read again.
//   - Where you got to: the server's place in a book is used when it's newer than HomeTunes' own
//     (ListeningModel.applyServerPlace); while listening, HomeTunes' place is sent (every 15 s at
//     most, at once when it finishes or jumps), and so are Mark as finished / not finished.
//     Anything that couldn't be sent (the server was off) waits and is sent at the next sync,
//     unless the server's place has changed since.
// Libraries can be left out one by one (Settings › Servers › a server's ⋮ › Libraries…).
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../models/track.dart';
import '../services/abs_client.dart';
import '../services/book_sidecar.dart' show htmlToText;
import '../services/secret_store.dart';
import '../services/server_probe.dart' show candidateUrls;
import '../services/storage.dart';
import '../services/subsonic_client.dart' show isPlainHttpToInternet;
import 'library_model.dart';
import 'listening_model.dart';
import 'remote_books.dart';
import 'server_reader.dart';
import 'servers_model.dart';

/// One book as last read: when it changed on the server, its files, their file types, and its
/// cover file (once downloaded).
class _Item {
  int updatedAt;
  List<Track> tracks;
  Map<String, String> ext;
  bool hasCover;
  String? cover;
  _Item({required this.updatedAt, required this.tracks, this.ext = const {}, this.hasCover = false, this.cover});

  Map<String, dynamic> toJson() => {
        'updatedAt': updatedAt,
        'tracks': [for (final t in tracks) t.toJson()],
        if (ext.isNotEmpty) 'ext': ext,
        if (hasCover) 'hasCover': true,
        if (cover != null) 'cover': cover,
      };

  static _Item? fromJson(Object? j) {
    if (j is! Map) return null;
    final tracks = <Track>[];
    for (final t in (j['tracks'] is List ? j['tracks'] as List : const [])) {
      try {
        final track = Track.fromJson(Map<String, dynamic>.from(t as Map));
        if (isRemoteBookId(track.id)) tracks.add(track);
      } catch (_) {}
    }
    if (tracks.isEmpty) return null;
    final ext = j['ext'] is Map ? j['ext'] as Map : const {};
    return _Item(
      updatedAt: j['updatedAt'] is int ? j['updatedAt'] as int : 0,
      tracks: tracks,
      ext: {for (final e in ext.entries) if (e.key is String && e.value is String) e.key as String: e.value as String},
      hasCover: j['hasCover'] == true,
      cover: j['cover'] as String?,
    );
  }
}

/// What HomeTunes remembers about one Audiobookshelf server (never its tokens or password).
class _ServerState {
  /// The address that worked (with its scheme), and the user it signed in as.
  String? base;
  String? userId;

  /// Its book libraries, and the ones the user left out.
  List<AbsLibrary> libraries = [];
  Set<String> hidden = {};

  int? syncedMs;
  String? error;
  String? status;

  /// The books as last read, by item id.
  Map<String, _Item> items = {};

  /// Places not sent yet, by item id: {t: seconds, d: seconds, f: finished, u: when (ms)}.
  Map<String, Map<String, Object>> pending = {};

  int get count => items.length;

  Map<String, dynamic> toJson() => {
        if (base != null) 'base': base,
        if (userId != null) 'userId': userId,
        'libraries': [for (final l in libraries) l.toJson()],
        if (hidden.isNotEmpty) 'hidden': hidden.toList()..sort(),
        if (syncedMs != null) 'syncedMs': syncedMs,
        'items': {for (final e in items.entries) e.key: e.value.toJson()},
        if (pending.isNotEmpty) 'pending': pending,
      };

  static _ServerState fromJson(Object? j) {
    final s = _ServerState();
    if (j is! Map) return s;
    s.base = j['base'] as String?;
    s.userId = j['userId'] as String?;
    s.libraries = [for (final l in (j['libraries'] is List ? j['libraries'] as List : const [])) ?AbsLibrary.fromJson(l)];
    s.hidden = {for (final h in (j['hidden'] is List ? j['hidden'] as List : const [])) if (h is String) h};
    s.syncedMs = j['syncedMs'] as int?;
    final items = j['items'];
    if (items is Map) {
      for (final e in items.entries) {
        final item = e.key is String ? _Item.fromJson(e.value) : null;
        if (item != null) s.items[e.key as String] = item;
      }
    }
    final pend = j['pending'];
    if (pend is Map) {
      for (final e in pend.entries) {
        if (e.key is String && e.value is Map) {
          s.pending[e.key as String] = {
            for (final x in (e.value as Map).entries)
              if (x.key is String && (x.value is num || x.value is bool)) x.key as String: x.value as Object,
          };
        }
      }
    }
    return s;
  }
}

class ServerBooksModel extends ChangeNotifier implements RemoteBookSource, ServerReader {
  ServerBooksModel({
    required this.storage,
    required this.servers,
    required this.library,
    this.listening,
    SecretStore? secrets,
    http.Client Function()? httpClient,
  })  : secrets = secrets ?? servers.secrets,
        _makeHttp = httpClient {
    _known = {for (final s in servers.all) s.id: s};
    servers.addListener(_onServers);
    library.remoteBooks = this;
    listening?.onPlaceSaved = _placeSaved;
  }

  final Storage storage;
  final ServersModel servers;
  final LibraryModel library;
  final ListeningModel? listening;
  final SecretStore? secrets;
  final http.Client Function()? _makeHttp;

  static const fileName = 'server_books.json';

  /// How often the servers are read again while HomeTunes is open.
  static const resyncEvery = Duration(minutes: 30);

  /// Where you've got to is sent at most this often while listening.
  static const progressEvery = Duration(seconds: 15);

  /// A sign-in with less than this left is renewed before it's used.
  static const renewBefore = Duration(minutes: 10);

  /// The cover size asked for.
  static const coverWidth = 600;

  final Map<String, _ServerState> _state = {};
  final Map<String, AbsClient> _clients = {};
  final Map<String, AbsSignIn> _signIns = {};
  final Map<String, Future<AbsClient>> _signing = {};
  final Map<String, Future<void>> _syncing = {};
  Map<String, ServerEntry> _known = {};
  Timer? _resync;
  bool _disposed = false;

  /// For tests: the clock.
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  // ---- which servers ----

  @override
  MediaKind get readsKind => MediaKind.audiobooks;

  static bool _isBookServer(ServerEntry s) => s.type == ServerType.audiobookshelf && s.uses.contains(MediaKind.audiobooks);

  @override
  bool reads(ServerEntry s) => _isBookServer(s);

  /// The Audiobookshelf servers switched on for audiobooks.
  List<ServerEntry> get bookServers => [for (final s in servers.all) if (_isBookServer(s)) s];

  _ServerState _of(String id) => _state[id] ??= _ServerState();

  /// The key the server's refresh token is kept under in protected storage.
  static String refreshKey(ServerEntry s) => 'abs-refresh:${s.username.trim()}@${s.url.trim().toLowerCase()}';

  // ---- status, for Settings › Servers ----

  @override
  bool isSyncing(ServerEntry s) => _syncing.containsKey(s.id);

  @override
  String statusFor(ServerEntry s) {
    final st = _state[s.id];
    if (!s.uses.contains(MediaKind.audiobooks)) return 'Switch it on to show its audiobooks in the Books tab.';
    if (st == null) return 'Not read yet.';
    if (st.status != null) return st.status!;
    if (st.error != null) return st.error!;
    if (st.syncedMs == null) return 'Not read yet.';
    final hidden = st.hidden.isEmpty ? '' : ' · ${st.hidden.length} ${st.hidden.length == 1 ? 'library' : 'libraries'} left out';
    return 'Signed in as ${s.username} · ${st.count} ${st.count == 1 ? 'book' : 'books'}$hidden · read ${_ago(st.syncedMs!)}';
  }

  @override
  bool? okFor(ServerEntry s) {
    final st = _state[s.id];
    if (st == null || st.status != null || !s.uses.contains(MediaKind.audiobooks)) return null;
    if (st.error != null) return false;
    return st.syncedMs == null ? null : true;
  }

  String _ago(int ms) {
    final d = Duration(milliseconds: max(0, now() - ms));
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'} ago';
  }

  @override
  List<ServerLibraryChoice> libraryChoicesOf(ServerEntry s) =>
      [for (final l in _state[s.id]?.libraries ?? const <AbsLibrary>[]) (id: l.id, name: l.name)];

  @override
  bool isLibraryShown(ServerEntry s, String id) => !(_state[s.id]?.hidden.contains(id) ?? false);

  @override
  Future<void> setLibraryShown(ServerEntry s, String id, bool shown) async {
    final st = _of(s.id);
    shown ? st.hidden.remove(id) : st.hidden.add(id);
    notifyListeners();
    await _save();
    await sync(s);
  }

  // ---- loading and saving ----

  Future<void> load() async {
    final j = await storage.read(fileName);
    if (j is Map && j['servers'] is Map) {
      for (final e in (j['servers'] as Map).entries) {
        if (e.key is String) _state[e.key as String] = _ServerState.fromJson(e.value);
      }
    }
    // Servers that went while HomeTunes was closed are forgotten; the rest show at once.
    _state.removeWhere((id, _) => servers.byId(id)?.type != ServerType.audiobookshelf);
    for (final s in bookServers) {
      final st = _state[s.id];
      if (st != null && st.items.isNotEmpty) _giveTracks(s);
    }
    _known = {for (final s in servers.all) s.id: s};
    notifyListeners();
  }

  Future<void> _save() async {
    if (_disposed) return;
    await storage.write(fileName, {'servers': {for (final e in _state.entries) e.key: e.value.toJson()}});
  }

  /// Reads every book server now, then again every [resyncEvery] while HomeTunes is open.
  void start() {
    unawaited(syncAll());
    _resync?.cancel();
    _resync = Timer.periodic(resyncEvery, (_) => syncAll());
  }

  Future<void> syncAll() => Future.wait([for (final s in bookServers) sync(s)]);

  /// Hands [s]'s books to the library (leaving out libraries the user left out).
  void _giveTracks(ServerEntry s) {
    final st = _of(s.id);
    library.setServerBookTracks(s.id, [for (final i in st.items.values) ...i.tracks]);
  }

  // ---- following Settings › Servers ----

  void _onServers() {
    final now = {for (final s in servers.all) s.id: s};
    for (final old in _known.values) {
      if (old.type != ServerType.audiobookshelf) continue;
      final cur = now[old.id];
      if (cur == null || cur.type != ServerType.audiobookshelf) {
        unawaited(_forget(old));
        continue;
      }
      final moved = cur.url.trim().toLowerCase() != old.url.trim().toLowerCase() || cur.username.trim() != old.username.trim();
      if (moved) {
        // Another address or user: sign in again.
        _clients.remove(cur.id)?.close();
        _signIns.remove(cur.id);
        unawaited(secrets?.delete(refreshKey(old)));
        final st = _of(cur.id);
        st.base = null;
        st.userId = null;
        if (_isBookServer(cur)) unawaited(sync(cur));
      } else if (_isBookServer(cur) && !_isBookServer(old)) {
        unawaited(sync(cur));
      } else if (!_isBookServer(cur) && _isBookServer(old)) {
        // Switched off for audiobooks: they leave the Books tab (their places stay).
        library.removeServerBookTracks(cur.id);
        notifyListeners();
      }
    }
    for (final cur in now.values) {
      if (!_known.containsKey(cur.id) && _isBookServer(cur)) unawaited(sync(cur));
    }
    _known = now;
  }

  @override
  Future<void> signOut(ServerEntry s) async {
    final c = _clients.remove(s.id);
    _signIns.remove(s.id);
    final refresh = await secrets?.read(refreshKey(s));
    await c?.signOut(refresh);
    c?.close();
    await secrets?.delete(refreshKey(s));
    final st = _of(s.id);
    st.userId = null;
    st.error = 'Signed out. Use Sync now to sign in again.';
    notifyListeners();
    await _save();
  }

  Future<void> _forget(ServerEntry s) async {
    final c = _clients.remove(s.id);
    _signIns.remove(s.id);
    final refresh = await secrets?.read(refreshKey(s));
    await c?.signOut(refresh);
    c?.close();
    await secrets?.delete(refreshKey(s));
    _state.remove(s.id);
    library.removeServerBookTracks(s.id);
    try {
      final dir = Directory(_coverDir(s.id));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    if (_disposed) return;
    notifyListeners();
    await _save();
  }

  // ---- signing in ----

  AbsClient _newClient(String base) => AbsClient(baseUrl: base, httpClient: _makeHttp?.call());

  /// A client signed in to [s] whose sign-in has at least [renewBefore] left: the one in hand,
  /// else renewed with the saved refresh token, else a new sign-in with the saved password.
  /// One at a time per server (a refresh token can only be spent once). Throws [AbsException]
  /// with a sentence for the user.
  Future<AbsClient> _signedIn(ServerEntry s, {bool fresh = false}) {
    final running = _signing[s.id];
    if (running != null) return running;
    final job = _signIn(s, fresh: fresh);
    _signing[s.id] = job;
    job.whenComplete(() => _signing.remove(s.id)).ignore();
    return job;
  }

  Future<AbsClient> _signIn(ServerEntry s, {required bool fresh}) async {
    final st = _of(s.id);
    if (!fresh) {
      final c = _clients[s.id], si = _signIns[s.id];
      if (c != null && si != null && (si.expiresMs == null || si.expiresMs! - now() > renewBefore.inMilliseconds)) return c;
      final refresh = await secrets?.read(refreshKey(s));
      if (refresh != null && st.base != null) {
        final c2 = _newClient(st.base!);
        try {
          final r = await c2.refresh(refresh);
          return await _keep(s, c2, r, st.base!);
        } on AbsException catch (e) {
          c2.close();
          if (!e.fromServer) rethrow; // not reachable: no point signing in with the password
          await secrets?.delete(refreshKey(s)); // spent or run out: sign in again below
        }
      }
    }
    if (s.username.trim().isEmpty) {
      throw const AbsException('Add the user name and password for this server with Edit… to sign in.');
    }
    final password = await servers.passwordOf(s);
    AbsException? last;
    for (final base in candidateUrls(s.url)) {
      // The password never goes over plain http to an address on the internet.
      if (base.startsWith('http://') && isPlainHttpToInternet(base)) {
        last ??= const AbsException(
          'HomeTunes won\'t send your password over plain http to an address on the internet. '
          'Use https, or connect over your home network or Tailscale.',
        );
        continue;
      }
      final c = _newClient(base);
      try {
        final r = await c.signIn(s.username.trim(), password);
        return await _keep(s, c, r, base);
      } on AbsException catch (e) {
        c.close();
        last = e;
        if (e.fromServer) break; // a real answer (wrong password): no point trying http as well
      }
    }
    throw last ?? const AbsException('Couldn\'t reach the server.');
  }

  Future<AbsClient> _keep(ServerEntry s, AbsClient c, AbsSignIn r, String base) async {
    final st = _of(s.id);
    final old = _clients[s.id];
    if (!identical(old, c)) old?.close();
    _clients[s.id] = c;
    _signIns[s.id] = r;
    st.base = base;
    st.userId = r.userId;
    final refresh = r.refreshToken;
    if (refresh != null) await secrets?.write(refreshKey(s), refresh);
    return c;
  }

  // ---- reading the server ----

  @override
  Future<void> sync(ServerEntry s) {
    final running = _syncing[s.id];
    if (running != null) return running;
    final job = _sync(s);
    _syncing[s.id] = job;
    job.whenComplete(() {
      _syncing.remove(s.id);
      if (!_disposed) notifyListeners();
    });
    return job;
  }

  Future<void> _sync(ServerEntry s) async {
    final st = _of(s.id);
    st.error = null;
    st.status = 'Signing in…';
    notifyListeners();
    try {
      AbsClient c;
      List<AbsLibrary> libs;
      try {
        c = await _signedIn(s);
        libs = await c.libraries();
      } on AbsException catch (e) {
        if (!e.signedOut) rethrow;
        // The sign-in stopped working (signed out on the server): sign in again, once.
        c = await _signedIn(s, fresh: true);
        libs = await c.libraries();
      }
      st.libraries = [for (final l in libs) if (l.holdsBooks) l];
      final places = {for (final pl in await c.progress()) pl.itemId: pl};
      await _sendPending(s, c, places);
      final shown = [for (final l in st.libraries) if (!st.hidden.contains(l.id)) l];
      final brief = <String, Map<String, dynamic>>{};
      for (final lib in shown) {
        st.status = 'Reading ${lib.name}…';
        notifyListeners();
        for (final x in await c.items(lib.id, onProgress: (done, total) {
          st.status = 'Reading ${lib.name} $done / $total';
          notifyListeners();
        })) {
          if (x['id'] is String && x['isMissing'] != true && x['isInvalid'] != true) brief[x['id'] as String] = x;
        }
      }
      // Only books that are new or changed since the last read are read in full.
      int stamp(Map<String, dynamic> x) => x['updatedAt'] is int ? x['updatedAt'] as int : 0;
      final changed = [
        for (final e in brief.entries)
          if (st.items[e.key]?.updatedAt != stamp(e.value) || st.items[e.key] == null) e.key,
      ];
      final items = <String, _Item>{for (final e in st.items.entries) if (brief.containsKey(e.key)) e.key: e.value};
      if (changed.isNotEmpty) {
        for (final j in await c.fullItems(changed, onProgress: (done, total) {
          st.status = 'Reading books $done / $total';
          notifyListeners();
        })) {
          final made = bookFromAbs(j, serverKey: s.id);
          if (made == null) continue;
          final old = items[made.itemId];
          items[made.itemId] = _Item(
            updatedAt: made.updatedAt,
            tracks: made.tracks,
            ext: made.ext,
            hasCover: made.hasCover,
            // A changed book's cover is fetched again (it may be a new one).
            cover: old != null && old.updatedAt == made.updatedAt ? old.cover : null,
          );
        }
      }
      st.items = items;
      // Covers already here stay on the files.
      for (final i in items.values) {
        final cover = i.cover;
        if (cover != null && File(cover).existsSync()) i.tracks = [for (final t in i.tracks) t.copyWith(art: cover)];
      }
      st.syncedMs = now();
      st.status = null;
      st.error = null;
      if (_isBookServer(servers.byId(s.id) ?? s)) {
        _giveTracks(s);
        _applyPlaces(s, places);
      }
      await _save();
      notifyListeners();
      await _fetchCovers(s, c);
    } on AbsException catch (e) {
      st.status = null;
      st.error = 'Couldn\'t read it: ${e.message}';
    } catch (e) {
      st.status = null;
      st.error = 'Couldn\'t read it: ${hidePath('$e')}';
    }
    notifyListeners();
  }

  /// Error text without addresses' query strings.
  static String hidePath(String s) => s.replaceAll(RegExp(r'\?[^\s)]*'), '');

  // ---- covers ----

  String _coverDir(String serverKey) => p.join(storage.artDir, 'server-book', serverKey);

  Future<void> _fetchCovers(ServerEntry s, AbsClient c) async {
    final st = _of(s.id);
    final wanted = <String>{};
    final missing = <String, (String, _Item)>{};
    for (final e in st.items.entries) {
      if (!e.value.hasCover) continue;
      final file = p.join(_coverDir(s.id), '${e.key}-${e.value.updatedAt}.jpg');
      wanted.add(p.normalize(file));
      if (e.value.cover != file || !File(file).existsSync()) missing[file] = (e.key, e.value);
    }
    var tried = 0, got = 0;
    for (final e in missing.entries) {
      if (_disposed || _state[s.id] != st) return;
      if (tried++ % 10 == 0) {
        st.status = 'Getting covers $tried / ${missing.length}';
        notifyListeners();
      }
      final file = e.key;
      final (itemId, item) = e.value;
      if (!File(file).existsSync()) {
        final bytes = await c.coverBytes(itemId, width: coverWidth);
        if (bytes == null) continue;
        try {
          await Directory(p.dirname(file)).create(recursive: true);
          final tmp = File('$file.tmp');
          await tmp.writeAsBytes(bytes, flush: true);
          await tmp.rename(file);
        } catch (_) {
          continue;
        }
      }
      item.cover = file;
      item.tracks = [for (final t in item.tracks) t.copyWith(art: file)];
      // Show covers as they arrive, a batch at a time.
      if (++got % 12 == 0 && _isBookServer(servers.byId(s.id) ?? s)) _giveTracks(s);
    }
    if (got > 0 && _isBookServer(servers.byId(s.id) ?? s)) _giveTracks(s);
    if (st.status != null) {
      st.status = null;
      notifyListeners();
    }
    if (got > 0) await _save();
    // Covers no longer used go.
    try {
      final dir = Directory(_coverDir(s.id));
      if (await dir.exists()) {
        await for (final f in dir.list()) {
          if (f is File && !wanted.contains(p.normalize(f.path))) {
            try {
              await f.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  // ---- places, both ways ----

  /// The server's places, where they're newer than HomeTunes' own.
  void _applyPlaces(ServerEntry s, Map<String, AbsProgress> places) {
    final l = listening;
    if (l == null) return;
    for (final pl in places.values) {
      final b = library.bookById(remoteBookId(s.id, pl.itemId));
      if (b == null) continue;
      l.applyServerPlace(
        b,
        offset: Duration(milliseconds: (pl.currentTime * 1000).round()),
        finished: pl.isFinished,
        updatedMs: pl.lastUpdate,
      );
    }
  }

  // The latest place of each book waiting to be sent, and when each was last sent.
  final Map<String, ({ServerEntry server, String item, double time, double length, bool finished, int at})> _toSend = {};
  final Map<String, int> _lastSent = {};
  Timer? _sendTimer;

  /// HomeTunes saved a place in [b] (ListeningModel.onPlaceSaved): a server book's goes to the
  /// server, at once when it finishes, starts over or jumps, else every [progressEvery] at most.
  void _placeSaved(Book b, BookProgress? place, bool jumped) {
    if (b.parts.isEmpty) return;
    final parts = remoteBookParts(b.parts.first.id);
    final s = parts == null ? null : servers.byId(parts.server);
    if (parts == null || s == null || !_isBookServer(s)) return;
    final i = place == null ? -1 : b.indexOfPart(place.partId);
    final time = place == null || i < 0 ? Duration.zero : b.offsetOf(i, place.position);
    final finished = place?.finished ?? false;
    final previous = _toSend[b.id];
    _toSend[b.id] = (
      server: s,
      item: parts.item,
      time: time.inMilliseconds / 1000,
      length: b.duration.inMilliseconds / 1000,
      finished: finished,
      at: now(),
    );
    final last = _lastSent[b.id];
    final soon = jumped || place == null || finished || (previous != null && previous.finished != finished) ||
        last == null || now() - last >= progressEvery.inMilliseconds;
    if (soon) {
      _sendNow(b.id);
    } else {
      _sendTimer ??= Timer(progressEvery, () {
        _sendTimer = null;
        for (final id in _toSend.keys.toList()) {
          _sendNow(id);
        }
      });
    }
  }

  /// Sends the latest places now (the app is going into the background).
  void flush() {
    _sendTimer?.cancel();
    _sendTimer = null;
    for (final id in _toSend.keys.toList()) {
      _sendNow(id);
    }
  }

  void _sendNow(String bookId) {
    final x = _toSend.remove(bookId);
    if (x == null) return;
    _lastSent[bookId] = now();
    unawaited(() async {
      try {
        final c = await _signedIn(x.server);
        await c.setProgress(x.item, currentTime: x.time, duration: x.length, finished: x.finished);
        if (_state[x.server.id]?.pending.remove(x.item) != null) await _save();
      } catch (_) {
        // Sent at the next sync instead (unless the server's place is newer by then).
        _of(x.server.id).pending[x.item] = {'t': x.time, 'd': x.length, 'f': x.finished, 'u': x.at};
        await _save();
      }
    }());
  }

  /// Places that couldn't be sent before, unless the server's place changed after them.
  Future<void> _sendPending(ServerEntry s, AbsClient c, Map<String, AbsProgress> places) async {
    final st = _of(s.id);
    if (st.pending.isEmpty) return;
    for (final e in Map.of(st.pending).entries) {
      final when = e.value['u'] is int ? e.value['u'] as int : 0;
      final theirs = places[e.key];
      if (theirs != null && theirs.lastUpdate >= when) {
        st.pending.remove(e.key);
        continue;
      }
      try {
        final time = (e.value['t'] as num?)?.toDouble() ?? 0, length = (e.value['d'] as num?)?.toDouble() ?? 0;
        final finished = e.value['f'] == true;
        await c.setProgress(e.key, currentTime: time, duration: length, finished: finished);
        st.pending.remove(e.key);
        // What was just sent is the place now (so it isn't replaced by the older one read above).
        places[e.key] = AbsProgress(itemId: e.key, currentTime: time, duration: length, isFinished: finished, lastUpdate: when);
      } on AbsException catch (x) {
        if (x.status == 404 || x.status == 400) st.pending.remove(e.key); // gone from the server
        if (!x.fromServer) break;
      }
    }
    await _save();
  }

  // ---- playing and downloading (RemoteBookSource) ----

  final Map<String, String> _problems = {};

  ServerEntry? _serverOf(Track t, {required String doing}) {
    final parts = remoteBookParts(t.id);
    final s = parts == null ? null : servers.byId(parts.server);
    if (s == null) {
      _problems[t.id] = 'The server this book was on has been removed from Settings › Servers.';
      return null;
    }
    if (!s.uses.contains(MediaKind.audiobooks)) {
      _problems[t.id] = '${s.name} is switched off for audiobooks in Settings › Servers.';
      return null;
    }
    return s;
  }

  @override
  String? problemFor(Track t) => _problems[t.id];

  @override
  Future<void> prepare(Track t) async {
    final s = _serverOf(t, doing: 'play');
    if (s == null) return;
    try {
      await _signedIn(s);
      _problems.remove(t.id);
    } on AbsException catch (e) {
      _problems[t.id] = 'Can\'t play this from ${s.name}: ${e.message}';
    }
  }

  @override
  String? streamUrlFor(Track t) {
    final parts = remoteBookParts(t.id);
    final s = _serverOf(t, doing: 'play');
    if (parts == null || s == null) return null;
    final c = _clients[s.id];
    if (c == null || c.token == null) {
      _problems[t.id] ??= 'Not signed in to ${s.name} yet.';
      return null;
    }
    return c.streamUri(parts.item, parts.ino).toString();
  }

  @override
  Future<RemoteBookDownload?> downloadRequest(Track t) async {
    final parts = remoteBookParts(t.id);
    final s = _serverOf(t, doing: 'download');
    if (parts == null || s == null) return null;
    AbsClient c;
    try {
      c = await _signedIn(s);
    } on AbsException catch (e) {
      _problems[t.id] = 'Can\'t download this from ${s.name}: ${e.message}';
      return null;
    }
    final ext = _state[s.id]?.items[parts.item]?.ext[parts.ino] ?? 'm4b';
    return (url: c.downloadUri(parts.item, parts.ino).toString(), headers: c.mediaHeaders, ext: ext);
  }

  /// Reads finish in the background; one that finishes after this was closed down has no one left
  /// to tell.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _resync?.cancel();
    _sendTimer?.cancel();
    servers.removeListener(_onServers);
    if (identical(library.remoteBooks, this)) library.remoteBooks = null;
    if (listening?.onPlaceSaved == _placeSaved) listening?.onPlaceSaved = null;
    for (final c in _clients.values) {
      c.close();
    }
    super.dispose();
  }
}

/// One Audiobookshelf item (in full: with its audio files and chapters) as a book's Tracks, with
/// the file types and whether it has a cover; null when it isn't a book with playable files.
@visibleForTesting
({String itemId, int updatedAt, List<Track> tracks, Map<String, String> ext, bool hasCover})? bookFromAbs(
  Map<String, dynamic> j, {
  required String serverKey,
}) {
  final itemId = j['id'];
  final media = j['media'];
  if (itemId is! String || media is! Map || (j['mediaType'] != null && j['mediaType'] != 'book')) return null;
  final meta = media['metadata'] is Map ? media['metadata'] as Map : const {};
  final files = [
    for (final f in (media['audioFiles'] is List ? media['audioFiles'] as List : const []))
      if (f is Map && f['ino'] != null && f['exclude'] != true && f['invalid'] != true) f,
  ]..sort((a, b) => ((a['index'] as num?) ?? 0).compareTo((b['index'] as num?) ?? 0));
  if (files.isEmpty) return null;

  String? str(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
  final title = str(meta['title']) ?? 'Audiobook';
  List<String> names(Object? list) => [
        for (final x in (list is List ? list : const []))
          if (x is String && x.trim().isNotEmpty) x.trim() else if (x is Map && str(x['name']) != null) str(x['name'])!,
      ];
  final authors = names(meta['authors']);
  final author = authors.isNotEmpty ? authors.join(', ') : (str(meta['authorName']) ?? 'Unknown author');
  final narrators = names(meta['narrators']);
  final narrator = narrators.isNotEmpty ? narrators.join(', ') : str(meta['narratorName']);
  String? series;
  double? seriesIndex;
  final seriesList = meta['series'] is List ? meta['series'] as List : const [];
  if (seriesList.isNotEmpty && seriesList.first is Map) {
    series = str((seriesList.first as Map)['name']);
    seriesIndex = double.tryParse('${(seriesList.first as Map)['sequence'] ?? ''}');
  } else if (str(meta['seriesName']) case final s?) {
    // "Dungeon Crawler Carl #7"
    final m = RegExp(r'^(.*?)\s*#\s*([\d.]+)$').firstMatch(s);
    series = m == null ? s : m.group(1)!.trim();
    seriesIndex = m == null ? null : double.tryParse(m.group(2)!);
  }
  final genres = names(meta['genres']);
  final year = int.tryParse('${meta['publishedYear'] ?? ''}'.trim());
  final rawDescription = str(meta['description']);
  final description = rawDescription == null ? null : (rawDescription.contains('<') ? htmlToText(rawDescription) : rawDescription);
  final added = j['addedAt'] is int ? j['addedAt'] as int : null;
  final updatedAt = j['updatedAt'] is int ? j['updatedAt'] as int : (added ?? 0);

  // The book's chapters (seconds into the whole book) go on the file each starts in.
  final chapters = [
    for (final c in (media['chapters'] is List ? media['chapters'] as List : const []))
      if (c is Map && c['start'] is num) (start: (c['start'] as num).toDouble(), title: str(c['title']) ?? ''),
  ]..sort((a, b) => a.start.compareTo(b.start));

  final tracks = <Track>[];
  final ext = <String, String>{};
  var offset = 0.0;
  for (var i = 0; i < files.length; i++) {
    final f = files[i];
    final ino = '${f['ino']}';
    final length = f['duration'] is num ? (f['duration'] as num).toDouble() : 0.0;
    final fm = f['metadata'] is Map ? f['metadata'] as Map : const {};
    final fileName = str(fm['filename']) ?? 'Part ${i + 1}';
    final e = (str(fm['ext']) ?? p.extension(fileName)).replaceFirst('.', '').toLowerCase();
    if (RegExp(r'^[a-z0-9]{1,8}$').hasMatch(e)) ext[ino] = e;
    final tags = f['metaTags'] is Map ? f['metaTags'] as Map : const {};
    final partTitle = files.length == 1
        ? title
        : (str(tags['tagTitle']) != null && str(tags['tagTitle']) != title ? str(tags['tagTitle'])! : p.basenameWithoutExtension(fileName));
    final end = offset + length;
    final mine = [
      for (final c in chapters)
        if (c.start >= offset - 0.001 && (c.start < end - 0.001 || i == files.length - 1))
          Chapter(Duration(milliseconds: ((c.start - offset) * 1000).round().clamp(0, 1 << 40)), c.title),
    ];
    tracks.add(Track(
      id: remoteBookTrackId(serverKey, itemId, ino),
      source: TrackSource.server,
      title: partTitle,
      artist: author,
      album: title,
      albumArtist: author,
      trackNumber: i + 1,
      year: year,
      genre: genres.isEmpty ? null : genres.first,
      duration: Duration(milliseconds: (length * 1000).round()),
      modifiedMs: added,
      // One file with chapters in a multi-file book is common (a chapter per file): then the
      // file is the chapter.
      chapters: files.length > 1 && mine.length <= 1 ? const [] : mine,
      narrator: narrator,
      series: series ?? '',
      seriesIndex: seriesIndex,
      description: description,
      hasBookInfo: true,
    ));
    offset = end;
  }
  return (itemId: itemId, updatedAt: updatedAt, tracks: tracks, ext: ext, hasCover: media['coverPath'] != null);
}
