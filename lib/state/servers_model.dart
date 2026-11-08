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
  }, 'http://192.168.1.20:8096', plays: {MediaKind.videos}),
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
  audiobookshelf('Audiobookshelf', 'Audiobookshelf, for audiobooks (its podcasts aren\'t played).', {
    MediaKind.audiobooks,
  }, 'http://192.168.1.20:13378', plays: {MediaKind.audiobooks}),
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

  /// It can be the main music server (Subsonic: LibraryModel streams its music and audiobooks).
  final bool streams;

  /// What HomeTunes can play from it now, besides the main music server's (0.2.1: Jellyfin's
  /// videos). The rest are saved, tested and used once they're added.
  final Set<MediaKind> _plays;

  const ServerType(this.label, this.about, this.can, this.example, {this.streams = false, Set<MediaKind> plays = const {}})
      : _plays = plays;

  /// What HomeTunes can play from this kind of server now.
  Set<MediaKind> get playsNow => streams ? can : _plays;

  /// HomeTunes can play [kind] from this kind of server now.
  bool playsKind(MediaKind kind) => playsNow.contains(kind);

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

  // ---- profiles (phase 3, 8 Nov 2026) ----
  // With profiles on, the servers set up for the device (servers.json) are shared, but each
  // person signs in with their own user name (the user's answer, 8 Nov: a profile that hasn't
  // signed in shows nothing from that server), and can add servers just for themselves. Both are
  // kept in the profile's folder, in [mineFile]. The main (Subsonic) music server's sign-in stays
  // shared. With profiles off, the user names in servers.json are used, as before.

  /// The person's sign-ins and own servers, in their profile's folder.
  static const mineFile = 'my_servers.json';

  Storage? _personal;
  bool _split = false;

  /// This person's user name on each of the device's servers (by server id).
  Map<String, String> _signIns = {};

  /// Servers this person added just for themselves.
  List<ServerEntry> _mine = [];

  /// Profiles are on: the device's servers use this person's own sign-in.
  bool get split => _split;

  /// [s] was added by this person just for themselves.
  bool isMine(ServerEntry s) => _mine.any((m) => m.id == s.id);

  ServerEntry _withMySignIn(ServerEntry shared) => _split ? shared.copyWith(username: _signIns[shared.id] ?? '') : shared;

  /// Someone else is listening (or profiles were switched on or off): whose sign-ins and own
  /// servers to use. Doesn't tell the listeners (main.dart's host switches the server readers
  /// first, then calls [announce]), so a switch isn't taken for a change of user name.
  Future<void> usePersonal(Storage personal, {required bool split}) async {
    if (_split && !split) {
      // Profiles off: the kept person's sign-ins and own servers become everyone's.
      _others = [
        for (final s in _others) s.copyWith(username: _signIns[s.id] ?? ''),
        ..._mine,
      ];
      _signIns = {};
      _mine = [];
      _split = false;
      _personal = null;
      await _save();
      return;
    }
    _split = split;
    _personal = split ? personal : null;
    _signIns = {};
    _mine = [];
    if (!split) return;
    final j = await personal.read(mineFile);
    if (j is Map) {
      final si = j['signIns'];
      if (si is Map) {
        _signIns = {
          for (final e in si.entries)
            if (e.key is String && e.value is String && (e.value as String).isNotEmpty) e.key as String: e.value as String,
        };
      }
      final list = j['servers'];
      _mine = [for (final x in (list is List ? list : const [])) ?ServerEntry.fromJson(x)];
    }
  }

  /// Tells the listeners after [usePersonal].
  void announce() => notifyListeners();

  /// What a person starts with when profiles are switched on: the sign-ins in use now.
  Map<String, dynamic> currentSignIns() => {
        'signIns': {
          for (final s in all)
            if (!s.isMain && s.username.isNotEmpty) s.id: s.username,
        },
        'servers': <Object>[],
      };

  Future<void> _saveMine() async {
    final p = _personal;
    if (!_split || p == null) return;
    await p.write(mineFile, {
      'signIns': _signIns,
      'servers': [for (final s in _mine) s.toJson()],
    });
  }

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

  /// Every server: the main one first, then the rest in the order they were added (with profiles
  /// on: with this person's sign-in, then their own servers).
  List<ServerEntry> get all => [?main, for (final s in _others) _withMySignIn(s), ..._mine];

  ServerEntry? byId(String id) {
    if (id == mainId) return main;
    for (final s in _others) {
      if (s.id == id) return _withMySignIn(s);
    }
    return _mine.where((s) => s.id == id).firstOrNull;
  }

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

  /// Adds a server that isn't the main one. Its password goes to the protected storage. With
  /// profiles on, [justForMe] keeps it in this person's own list; otherwise it's the device's
  /// (everyone sees it, and signs in with their own user name: this one is this person's).
  Future<ServerEntry> add({
    required ServerType type,
    required String name,
    required String url,
    String username = '',
    String password = '',
    required Set<MediaKind> uses,
    bool justForMe = false,
  }) async {
    final entry = ServerEntry(
      id: _newId(),
      type: type,
      name: name.trim().isEmpty ? ServerEntry.nameFor(url) : name.trim(),
      url: url.trim(),
      username: username.trim(),
      uses: uses.intersection(type.can),
    );
    if (_split && justForMe) {
      _mine = [..._mine, entry];
    } else if (_split) {
      // The device's list holds the address; the sign-in is this person's.
      _others = [..._others, entry.copyWith(username: '')];
      if (entry.username.isNotEmpty) _signIns = {..._signIns, entry.id: entry.username};
    } else {
      _others = [..._others, entry];
    }
    await _storePassword(entry, password);
    notifyListeners();
    await _save();
    await _saveMine();
    return entry;
  }

  /// Changes a server that isn't the main one ([password] null: keep the saved one). With
  /// profiles on, a device server's user name is this person's sign-in; its address, name and
  /// uses are everyone's.
  Future<void> update(ServerEntry changed, {String? password}) async {
    final old = byId(changed.id);
    if (old == null || old.isMain) return;
    final entry = changed.copyWith(uses: changed.uses.intersection(changed.type.can));
    if (isMine(entry)) {
      _mine = [for (final s in _mine) s.id == entry.id ? entry : s];
    } else if (_split) {
      _others = [
        for (final s in _others) s.id == entry.id ? entry.copyWith(username: s.username) : s,
      ];
      _signIns = {..._signIns}..remove(entry.id);
      if (entry.username.isNotEmpty) _signIns[entry.id] = entry.username;
    } else {
      _others = [for (final s in _others) s.id == entry.id ? entry : s];
    }
    if (password != null || old.url != entry.url || old.username != entry.username) {
      final keep = password ?? await passwordOf(old);
      if (old.url != entry.url || old.username != entry.username) await _deletePassword(old);
      await _storePassword(entry, keep);
    }
    notifyListeners();
    await _save();
    await _saveMine();
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
    _mine = [
      for (final s in _mine)
        if (s.id != server.id) s,
    ];
    if (_signIns.containsKey(server.id)) _signIns = {..._signIns}..remove(server.id);
    await _deletePassword(server);
    notifyListeners();
    await _save();
    await _saveMine();
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
      ServerEntry checked(ServerEntry s) =>
          s.id == server.id ? s.copyWith(lastCheck: result.message, reachable: result.ok, checkedMs: now) : s;
      _others = [for (final s in _others) checked(s)];
      _mine = [for (final s in _mine) checked(s)];
      notifyListeners();
      await _save();
      await _saveMine();
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
