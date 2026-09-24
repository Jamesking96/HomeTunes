import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'storage.dart';

/// Exports and imports everything HomeTunes keeps on the device, as one file:
/// settings (music folders, server, switches), song edits, playlists and
/// Liked Songs, the library cache (so songs that aren't on this device yet
/// can be matched up later), and the cover images HomeTunes stores.
///
/// The file is gzip-compressed JSON. Paths inside the app's own folder are
/// stored relative to it, so a backup works on another PC or phone.
class AppBackup {
  static const format = 'hometunes-backup';
  static const version = 1;
  static const fileExtension = 'htbackup';

  /// The data files that make up HomeTunes' state.
  static const dataFiles = ['settings.json', 'edits.json', 'playlists.json', 'library.json'];

  /// Marks a path inside the app's folder in a backup.
  static const appPrefix = '@app/';

  /// Name of the automatic backup taken just before a restore.
  static const beforeRestoreName = 'before-restore.$fileExtension';

  /// Builds a backup of [storage]. The server password is only included when
  /// [includePassword] is set. [includeCoverCache] adds the covers pulled out
  /// of music files (they can be re-read by a rescan, so they're optional);
  /// covers chosen or downloaded by the user are always included.
  static Future<Uint8List> create(
    Storage storage, {
    bool includePassword = false,
    bool includeCoverCache = true,
  }) async {
    final root = storage.root.path;
    final files = <String, dynamic>{};
    for (final name in dataFiles) {
      final j = await storage.read(name);
      if (j == null) continue;
      files[name] = toPortable(j, root);
    }
    final settings = files['settings.json'];
    if (!includePassword && settings is Map && settings['server'] is Map) {
      (settings['server'] as Map).remove('password');
    }

    final art = <String, String>{};
    final artDir = Directory(storage.artDir);
    if (await artDir.exists()) {
      await for (final e in artDir.list(recursive: true)) {
        if (e is! File) continue;
        final rel = p.relative(e.path, from: root);
        final custom = p.split(rel).contains('custom');
        if (!custom && !includeCoverCache) continue;
        art[p.split(rel).join('/')] = base64Encode(await e.readAsBytes());
      }
    }

    final json = {
      'format': format,
      'version': version,
      'created': DateTime.now().toIso8601String(),
      'from': Platform.operatingSystem,
      'files': files,
      'art': art,
    };
    return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(json))));
  }

  /// Reads a backup file's bytes. Throws [FormatException] if it isn't one.
  static BackupContents read(List<int> bytes) {
    Object? json;
    try {
      json = jsonDecode(utf8.decode(gzip.decode(bytes)));
    } catch (_) {
      throw const FormatException('This isn\'t a HomeTunes backup file.');
    }
    if (json is! Map<String, dynamic> || json['format'] != format) {
      throw const FormatException('This isn\'t a HomeTunes backup file.');
    }
    final v = json['version'];
    if (v is! int || v > version) {
      throw const FormatException('This backup was made by a newer HomeTunes. Update the app first.');
    }
    return BackupContents(
      files: Map<String, dynamic>.from(json['files'] as Map? ?? const {}),
      art: Map<String, String>.from(json['art'] as Map? ?? const {}),
      created: DateTime.tryParse(json['created'] as String? ?? ''),
      from: json['from'] as String?,
    );
  }

  /// Puts a backup's data into [storage].
  ///
  /// [merge] = false replaces what's here; true combines the two: the backup's
  /// playlists, likes and edits are added (its edits win for the same song),
  /// and this device's server details and switches are kept if it has them.
  /// Music folders that don't exist on this device are left out and listed
  /// in the result. Reload the app's data and rescan afterwards.
  static Future<RestoreResult> restore(Storage storage, BackupContents backup, {required bool merge}) async {
    final root = storage.root.path;

    // Cover images first, so the data never points at a picture that isn't there.
    for (final e in backup.art.entries) {
      final parts = e.key.split('/');
      if (parts.isEmpty || parts.first != 'art' || parts.any((s) => s == '..' || s.isEmpty)) continue;
      final dest = File(p.joinAll([root, ...parts]));
      if (await dest.exists()) continue;
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(base64Decode(e.value), flush: true);
    }

    Map<String, dynamic> backupFile(String name) {
      final j = backup.files[name];
      return j is Map ? Map<String, dynamic>.from(fromPortable(j, root) as Map) : <String, dynamic>{};
    }

    Future<Map<String, dynamic>> currentFile(String name) async {
      final j = await storage.read(name);
      return j is Map<String, dynamic> ? j : <String, dynamic>{};
    }

    // ---- settings ----
    final bs = backupFile('settings.json');
    final cs = await currentFile('settings.json');
    final backupFolders = (bs['folders'] as List? ?? const []).cast<String>();
    final missingFolders = [for (final f in backupFolders) if (!Directory(f).existsSync()) f];
    final usableFolders = [for (final f in backupFolders) if (Directory(f).existsSync()) f];
    final Map<String, dynamic> settings;
    if (merge) {
      settings = {...bs, ...cs};
      final current = (cs['folders'] as List? ?? const []).cast<String>();
      settings['folders'] = [...current, for (final f in usableFolders) if (!current.contains(f)) f];
      final currentServer = cs['server'];
      if (currentServer is! Map || ((currentServer['url'] as String?) ?? '').isEmpty) {
        settings['server'] = bs['server'];
        settings['serverEnabled'] = bs['serverEnabled'];
      }
    } else {
      settings = {...bs, 'folders': usableFolders};
    }
    // No password in the backup: keep this device's one if it's the same server.
    final server = settings['server'];
    if (server is Map && ((server['password'] as String?) ?? '').isEmpty) {
      final here = cs['server'];
      if (here is Map && here['url'] == server['url'] && here['username'] == server['username']) {
        settings['server'] = {...server, 'password': here['password']};
      }
    }
    final s = settings['server'];
    final needsPassword = s is Map &&
        ((s['url'] as String?) ?? '').isNotEmpty &&
        ((s['password'] as String?) ?? '').isEmpty;

    // ---- edits ----
    final be = backupFile('edits.json');
    final edits = merge ? {...await currentFile('edits.json'), ...be} : be;

    // ---- playlists ----
    final bp = backupFile('playlists.json');
    final Map<String, dynamic> playlists;
    if (merge) {
      final cp = await currentFile('playlists.json');
      playlists = mergePlaylists(cp, bp);
    } else {
      playlists = bp;
    }

    // ---- library cache ----
    final bl = backupFile('library.json');
    final Map<String, dynamic> library;
    if (merge) {
      final cl = await currentFile('library.json');
      final here = {for (final t in (cl['local'] as List? ?? const [])) (t as Map)['id']};
      final seen = <Object?>{...here};
      final missing = [
        for (final t in [
          ...(cl['missing'] as List? ?? const []),
          ...(bl['local'] as List? ?? const []),
          ...(bl['missing'] as List? ?? const []),
        ])
          if (seen.add((t as Map)['id'])) t
      ];
      final currentRemote = cl['remote'] as List? ?? const [];
      library = {
        'local': cl['local'] ?? const [],
        'remote': currentRemote.isNotEmpty ? currentRemote : (bl['remote'] ?? const []),
        'missing': missing,
      };
    } else {
      library = bl;
    }

    await storage.write('settings.json', settings);
    await storage.write('edits.json', edits);
    await storage.write('playlists.json', playlists);
    await storage.write('library.json', library);

    return RestoreResult(missingFolders: missingFolders, needsPassword: needsPassword);
  }

  /// Combines two playlists.json contents: playlists with the same id get the
  /// songs of both (current order first); others are added. Liked songs too.
  static Map<String, dynamic> mergePlaylists(Map<String, dynamic> current, Map<String, dynamic> incoming) {
    final lists = <Map<String, dynamic>>[
      for (final pl in (current['playlists'] as List? ?? const [])) Map<String, dynamic>.from(pl as Map),
    ];
    for (final pl in (incoming['playlists'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(pl as Map);
      final same = lists.where((x) => x['id'] == m['id']).firstOrNull;
      if (same == null) {
        lists.add(m);
      } else {
        final ids = [...(same['trackIds'] as List? ?? const [])];
        for (final id in (m['trackIds'] as List? ?? const [])) {
          if (!ids.contains(id)) ids.add(id);
        }
        same['trackIds'] = ids;
      }
    }
    final liked = [...(current['liked'] as List? ?? const [])];
    for (final id in (incoming['liked'] as List? ?? const [])) {
      if (!liked.contains(id)) liked.add(id);
    }
    return {'playlists': lists, 'liked': liked};
  }

  /// Replaces paths inside [root] with "@app/..." (forward slashes).
  static Object? toPortable(Object? json, String root) => _mapStrings(json, (s) {
        if (!p.isAbsolute(s) || !p.isWithin(root, s)) return s;
        return appPrefix + p.split(p.relative(s, from: root)).join('/');
      });

  /// Turns "@app/..." back into a path inside [root].
  static Object? fromPortable(Object? json, String root) => _mapStrings(json, (s) {
        if (!s.startsWith(appPrefix)) return s;
        return p.joinAll([root, ...s.substring(appPrefix.length).split('/')]);
      });

  static Object? _mapStrings(Object? json, String Function(String) f) {
    if (json is String) return f(json);
    if (json is List) return [for (final v in json) _mapStrings(v, f)];
    if (json is Map) return {for (final e in json.entries) e.key as String: _mapStrings(e.value, f)};
    return json;
  }
}

/// What's in a backup file.
class BackupContents {
  final Map<String, dynamic> files;
  final Map<String, String> art;
  final DateTime? created;

  /// Operating system it was made on ("windows", "android"…).
  final String? from;

  const BackupContents({required this.files, required this.art, this.created, this.from});

  Map<String, dynamic> _file(String name) =>
      files[name] is Map ? Map<String, dynamic>.from(files[name] as Map) : const {};

  int get playlistCount => (_file('playlists.json')['playlists'] as List? ?? const []).length;
  int get likedCount => (_file('playlists.json')['liked'] as List? ?? const []).length;
  int get editCount => _file('edits.json').length;
  int get songCount {
    final l = _file('library.json');
    return (l['local'] as List? ?? const []).length + (l['remote'] as List? ?? const []).length;
  }

  List<String> get folders => (_file('settings.json')['folders'] as List? ?? const []).cast<String>();

  bool get hasPassword {
    final s = _file('settings.json')['server'];
    return s is Map && ((s['password'] as String?) ?? '').isNotEmpty;
  }
}

class RestoreResult {
  /// Music folders from the backup that don't exist on this device.
  final List<String> missingFolders;

  /// The backup has a server but no password (it wasn't included).
  final bool needsPassword;

  const RestoreResult({required this.missingFolders, required this.needsPassword});
}
