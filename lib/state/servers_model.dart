// Your servers (0.1.46): every server HomeTunes knows about, for music, audiobooks and videos.
// The user asked for "a server connection system for videos" and "multiple server connections
// per server setup", "as a framework" to fill in as servers get built; one server may have all
// three kinds.
//
// Each server has a type (Subsonic, Jellyfin, Plex, Emby, Audiobookshelf, or a HomeTunes server
// of our own), an address and sign-in, and the kinds it's used for (music, audiobooks, videos).
// Only Subsonic can stream so far, and only one Subsonic server at a time: that one is still
// LibraryModel's music server (its songs, sync, password and plain-http rules stay where they
// were), shown here as the "main" server. Every other server is kept in servers.json (passwords
// in the system's protected storage, never in the file), can be tested ("is it there, and what
// is it?") and is ready for when its type can stream. A second Subsonic server can be made the
// main one. Settings › Servers (ui/screens/settings/server_settings.dart) shows them.
import 'package:flutter/foundation.dart';

import '../services/secret_store.dart';
import '../services/server_probe.dart';
import '../services/storage.dart';
import '../services/subsonic_client.dart';
import 'library_model.dart';

/// What a server can be used for.
enum MediaKind {
  music('Music', 'music'),
  audiobooks('Audiobooks', 'audiobooks'),
  videos('Videos', 'videos');

  final String label;

  /// In a sentence: "Use for music".
  final String lower;
  const MediaKind(this.label, this.lower);
}

/// The kinds of server HomeTunes knows of. [streams]: HomeTunes can play from it now.
enum ServerType {
  subsonic(
    'Subsonic',
    'Navidrome, Airsonic, Gonic, Ampache and other servers that speak the Subsonic API.',
    {MediaKind.music, MediaKind.audiobooks},
    'http://192.168.1.20:4533',
    streams: true,
  ),
  jellyfin('Jellyfin', 'Jellyfin media server.', {
    MediaKind.music,
    MediaKind.audiobooks,
    MediaKind.videos,
  }, 'http://192.168.1.20:8096'),
  plex('Plex', 'Plex Media Server.', {
    MediaKind.music,
    MediaKind.audiobooks,
    MediaKind.videos,
  }, 'http://192.168.1.20:32400'),
  emby('Emby', 'Emby media server.', {
    MediaKind.music,
    MediaKind.audiobooks,
    MediaKind.videos,
  }, 'http://192.168.1.20:8096'),
  audiobookshelf('Audiobookshelf', 'Audiobookshelf, for audiobooks (and podcasts).', {
    MediaKind.audiobooks,
  }, 'http://192.168.1.20:13378'),
  hometunes('HomeTunes server', 'HomeTunes\' own server, being built: music, audiobooks and videos in one place.', {
    MediaKind.music,
    MediaKind.audiobooks,
    MediaKind.videos,
  }, 'http://192.168.1.20:4545');

  final String label;
  final String about;

  /// What this kind of server can hold.
  final Set<MediaKind> can;

  /// An example address for the address box.
  final String example;

  /// HomeTunes can stream from it now (the rest are saved, tested and used later).
  final bool streams;

  const ServerType(this.label, this.about, this.can, this.example, {this.streams = false});

  static ServerType? byName(Object? name) => name is String ? values.asNameMap()[name] : null;
}

/// One server.
class ServerEntry {
  /// 'main' for LibraryModel's music server; otherwise made when it's added.
  final String id;
  final ServerType type;
  final String name;
  final String url;
  final String username;

  /// What it's used for (a subset of [ServerType.can]).
  final Set<MediaKind> uses;

  /// What the last test found ("Found a Jellyfin server…"), when, and whether it answered.
  final String? lastCheck;
  final bool? reachable;
  final int? checkedMs;

  const ServerEntry({
    required this.id,
    required this.type,
    required this.name,
    required this.url,
    this.username = '',
    required this.uses,
    this.lastCheck,
    this.reachable,
    this.checkedMs,
  });

  bool get isMain => id == ServersModel.mainId;

  ServerEntry copyWith({
    ServerType? type,
    String? name,
    String? url,
    String? username,
    Set<MediaKind>? uses,
    String? lastCheck,
    bool? reachable,
    int? checkedMs,
  }) => ServerEntry(
    id: id,
    type: type ?? this.type,
    name: name ?? this.name,
    url: url ?? this.url,
    username: username ?? this.username,
    uses: uses ?? this.uses,
    lastCheck: lastCheck ?? this.lastCheck,
    reachable: reachable ?? this.reachable,
    checkedMs: checkedMs ?? this.checkedMs,
  );

  /// For servers.json: never the password.
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'url': url,
    if (username.isNotEmpty) 'username': username,
    'uses': [for (final k in uses) k.name],
    if (lastCheck != null) 'lastCheck': lastCheck,
    if (reachable != null) 'reachable': reachable,
    if (checkedMs != null) 'checkedMs': checkedMs,
  };

  static ServerEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final type = ServerType.byName(j['type']);
    final id = j['id'], url = j['url'];
    if (type == null || id is! String || url is! String || id == ServersModel.mainId) return null;
    final uses = {
      for (final k in (j['uses'] is List ? j['uses'] as List : const []))
        if (MediaKind.values.asNameMap()[k] case final kind? when type.can.contains(kind)) kind,
    };
    return ServerEntry(
      id: id,
      type: type,
      name: j['name'] is String ? j['name'] as String : nameFor(url),
      url: url,
      username: j['username'] is String ? j['username'] as String : '',
      uses: uses,
      lastCheck: j['lastCheck'] is String ? j['lastCheck'] as String : null,
      reachable: j['reachable'] is bool ? j['reachable'] as bool : null,
      checkedMs: j['checkedMs'] is int ? j['checkedMs'] as int : null,
    );
  }

  /// A name from an address when none is given: "192.168.1.20", "music.example.com".
  static String nameFor(String url) {
    final u = url.trim();
    final host = Uri.tryParse(u.contains('://') ? u : 'http://$u')?.host ?? '';
    return host.isEmpty ? (u.isEmpty ? 'Server' : u) : host;
  }
}

class ServersModel extends ChangeNotifier {
  ServersModel(this.storage, this.library, {SecretStore? secrets}) : secrets = secrets ?? library.secrets {
    library.addListener(_onLibrary);
  }

  final Storage storage;
  final LibraryModel library;
  final SecretStore? secrets;
  static const file = 'servers.json';
  static const mainId = 'main';

  /// For tests: how a server is checked, and the clock.
  Future<ProbeResult> Function(ServerType type, String url, {String username, String password}) probe = probeServer;
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  List<ServerEntry> _others = [];
  String? _mainName;

  Future<void> load() async {
    final j = await storage.read(file);
    final list = j is Map ? j['servers'] : null;
    _others = [for (final x in (list is List ? list : const [])) ?ServerEntry.fromJson(x)];
    _mainName = j is Map && j['mainName'] is String ? j['mainName'] as String : null;
    notifyListeners();
  }

  Future<void> _save() async {
    await storage.write(file, {
      'servers': [for (final s in _others) s.toJson()],
      if (_mainName != null) 'mainName': _mainName,
    });
  }

  void _onLibrary() => notifyListeners();

  /// LibraryModel's music server, as an entry (null when there isn't one).
  ServerEntry? get main {
    final s = library.server;
    if (!s.isComplete) return null;
    return ServerEntry(
      id: mainId,
      type: ServerType.subsonic,
      name: _mainName ?? ServerEntry.nameFor(s.url),
      url: s.url,
      username: s.username,
      uses: {
        if (library.serverEnabled) MediaKind.music,
        if (library.serverEnabled && library.serverBooks) MediaKind.audiobooks,
      },
    );
  }

  /// Every server: the main one first, then the rest in the order they were added.
  List<ServerEntry> get all => [?main, ..._others];

  ServerEntry? byId(String id) => id == mainId ? main : _others.where((s) => s.id == id).firstOrNull;

  /// The servers that can hold [kind] (used for it or not), main first. A server that can hold
  /// all three shows in each section.
  List<ServerEntry> serversFor(MediaKind kind) => [
    for (final s in all)
      if (s.type.can.contains(kind)) s,
  ];

  /// How many songs the main server gave (for its status line).
  int get mainSongCount => library.tracks.where((t) => !t.isLocal).length;

  // ---- adding, changing, removing ----

  String _newId() => 's${now()}';

  /// Adds a server that isn't the main one. Its password goes to the protected storage.
  Future<ServerEntry> add({
    required ServerType type,
    required String name,
    required String url,
    String username = '',
    String password = '',
    required Set<MediaKind> uses,
  }) async {
    final entry = ServerEntry(
      id: _newId(),
      type: type,
      name: name.trim().isEmpty ? ServerEntry.nameFor(url) : name.trim(),
      url: url.trim(),
      username: username.trim(),
      uses: uses.intersection(type.can),
    );
    _others = [..._others, entry];
    await _storePassword(entry, password);
    notifyListeners();
    await _save();
    return entry;
  }

  /// Changes a server that isn't the main one ([password] null: keep the saved one).
  Future<void> update(ServerEntry changed, {String? password}) async {
    final old = byId(changed.id);
    if (old == null || old.isMain) return;
    final entry = changed.copyWith(uses: changed.uses.intersection(changed.type.can));
    _others = [for (final s in _others) s.id == entry.id ? entry : s];
    if (password != null || old.url != entry.url || old.username != entry.username) {
      final keep = password ?? await passwordOf(old);
      if (old.url != entry.url || old.username != entry.username) await _deletePassword(old);
      await _storePassword(entry, keep);
    }
    notifyListeners();
    await _save();
  }

  /// The name shown for the main server.
  Future<void> renameMain(String name) async {
    _mainName = name.trim().isEmpty ? null : name.trim();
    notifyListeners();
    await _save();
  }

  /// Uses [server] for [kind] or stops. For the main server that's LibraryModel's switches
  /// (music: "Include server music"; audiobooks: "Audiobooks from the music server").
  Future<void> setUse(ServerEntry server, MediaKind kind, bool on) async {
    if (server.isMain) {
      if (kind == MediaKind.music) await library.setServerEnabled(on);
      if (kind == MediaKind.audiobooks) {
        await library.setServerBooks(on);
        if (on && !library.serverEnabled) await library.setServerEnabled(true);
      }
      return;
    }
    if (!server.type.can.contains(kind)) return;
    await update(server.copyWith(uses: on ? {...server.uses, kind} : ({...server.uses}..remove(kind))));
  }

  /// Removes a server and its password. The main one: forgets it (its songs go too).
  Future<void> remove(ServerEntry server) async {
    if (server.isMain) {
      _mainName = null;
      await library.forgetServer();
      await _save();
      return;
    }
    _others = [
      for (final s in _others)
        if (s.id != server.id) s,
    ];
    await _deletePassword(server);
    notifyListeners();
    await _save();
  }

  /// Makes a saved Subsonic server the main one: it's connected and synced, and the old main
  /// one (if any) is kept in the list. Returns LibraryModel.connectServer's answer (an error,
  /// [LibraryModel.httpConsentNeeded], or null when it worked).
  Future<String?> makeMain(ServerEntry server, {bool allowPlainHttp = false}) async {
    if (server.isMain || server.type != ServerType.subsonic) return null;
    final old = main;
    final oldPassword = library.server.password;
    final err = await library.connectServer(
      ServerConfig(url: server.url, username: server.username, password: await passwordOf(server)),
      allowPlainHttp: allowPlainHttp,
    );
    if (err != null) return err;
    _others = [
      for (final s in _others)
        if (s.id != server.id) s,
    ];
    _mainName = server.name;
    if (old != null) {
      final entry = ServerEntry(
        id: _newId(),
        type: ServerType.subsonic,
        name: old.name,
        url: old.url,
        username: old.username,
        uses: {MediaKind.music, MediaKind.audiobooks},
      );
      _others = [..._others, entry];
      await _storePassword(entry, oldPassword);
    }
    notifyListeners();
    await _save();
    return null;
  }

  /// Checks a server: whether it answers, and what it is. The result is kept on the entry.
  Future<ProbeResult> test(ServerEntry server) async {
    final result = await probe(server.type, server.url, username: server.username, password: await passwordOf(server));
    if (!server.isMain) {
      final now = this.now();
      _others = [
        for (final s in _others)
          s.id == server.id ? s.copyWith(lastCheck: result.message, reachable: result.ok, checkedMs: now) : s,
      ];
      notifyListeners();
      await _save();
    }
    return result;
  }

  // ---- passwords: in the protected storage, by address and user name ----

  Future<String> passwordOf(ServerEntry s) async {
    if (s.isMain) return library.server.password;
    if (s.username.isEmpty) return '';
    return await secrets?.read(SecretStore.serverPasswordKey(s.url, s.username)) ?? '';
  }

  Future<void> _storePassword(ServerEntry s, String password) async {
    if (s.username.isEmpty) return;
    final key = SecretStore.serverPasswordKey(s.url, s.username);
    // Never touch the main server's own key.
    if (library.server.isComplete &&
        key == SecretStore.serverPasswordKey(library.server.url, library.server.username)) {
      return;
    }
    if (password.isEmpty) {
      await secrets?.delete(key);
    } else {
      await secrets?.write(key, password);
    }
  }

  Future<void> _deletePassword(ServerEntry s) async {
    if (s.username.isEmpty) return;
    final key = SecretStore.serverPasswordKey(s.url, s.username);
    if (library.server.isComplete &&
        key == SecretStore.serverPasswordKey(library.server.url, library.server.username)) {
      return;
    }
    await secrets?.delete(key);
  }

  @override
  void dispose() {
    library.removeListener(_onLibrary);
    super.dispose();
  }
}
