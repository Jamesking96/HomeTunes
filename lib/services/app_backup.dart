// Backup and restore of all HomeTunes data as a single .htbackup file.
// Used from Settings (backup page) through LibraryModel. create() gathers the JSON data files
// and cover images into one gzip'd JSON; read() opens one and checks it; restore() writes it
// back, either replacing what's here or merging the two. The models then reload their files.
// Paths inside the app's own folder are stored as "@app/..." so a backup made on Windows
// can be restored on a phone (and the other way round).
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
  // Written into every backup so we can recognise our own files and their age.
  static const format = 'hometunes-backup';
  static const version = 1;
  static const fileExtension = 'htbackup';

  /// The data files that make up HomeTunes' state.
  static const dataFiles = [
    'settings.json',
    'edits.json',
    'playlists.json',
    'library.json',
    'listening.json',
    'bookmarks.json',
    'lyrics.json',
    'equalizer.json',
  ];

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
    // 1. The data files, with app paths made portable.
    final files = <String, dynamic>{};
    for (final name in dataFiles) {
      final j = await storage.read(name);
      if (j == null) continue;
      files[name] = toPortable(j, root);
    }
    // 2. Leave the server password out unless the user ticked the box.
    final settings = files['settings.json'];
    if (!includePassword && settings is Map && settings['server'] is Map) {
      (settings['server'] as Map).remove('password');
    }

    // 3. Cover images, stored as text (base64) keyed by their path under the app folder.
    //    art/custom/ holds covers the user chose, which can't be recreated, so they always go in.
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

    // 4. Wrap it all up with a label and version, then compress.
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
    if (v is! int || v > version) {  // older versions are fine
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

    // Every file must really be saved: a restore that half-worked must say so (0.1.16; the
    // results of these writes used to be ignored).
    Future<void> put(String name, Object json) async {
      if (!await storage.write(name, json)) {
        throw FileSystemException('Couldn\'t save the ${Storage.describe(name)} from the backup', name);
      }
    }

    // Cover images first, so the data never points at a picture that isn't there.
    for (final e in backup.art.entries) {
      final dest = safeArtDestination(root, e.key);
      // Safety: anything that wouldn't land inside art/ is skipped (see safeArtDestination).
      if (dest == null) continue;
      if (await dest.exists()) continue;  // files are named by content
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(base64Decode(e.value), flush: true);
    }

    // Helpers: one data file from the backup (with paths made local again), and the
    // same file as it is on this device now. Both give an empty map if missing.
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
    final backupBookFolders = (bs['audiobookFolders'] as List? ?? const []).cast<String>();
    // Folders from another device usually don't exist here; they're dropped and reported.
    final missingFolders = [
      for (final f in [...backupFolders, ...backupBookFolders]) if (!Directory(f).existsSync()) f
    ];
    final usableFolders = [for (final f in backupFolders) if (Directory(f).existsSync()) f];
    final usableBookFolders = [for (final f in backupBookFolders) if (Directory(f).existsSync()) f];
    final Map<String, dynamic> settings;
    if (merge) {
      settings = {...bs, ...cs};  // this device's settings win
      final current = (cs['folders'] as List? ?? const []).cast<String>();
      settings['folders'] = [...current, for (final f in usableFolders) if (!current.contains(f)) f];
      final currentBooks = (cs['audiobookFolders'] as List? ?? const []).cast<String>();
      settings['audiobookFolders'] = [
        ...currentBooks,
        for (final f in usableBookFolders) if (!currentBooks.contains(f)) f,
      ];
      final overrides = {...?(bs['bookOverrides'] as Map?), ...?(cs['bookOverrides'] as Map?)};
      if (overrides.isNotEmpty) settings['bookOverrides'] = overrides;
      // Only take the backup's server if this device has none set up.
      final currentServer = cs['server'];
      if (currentServer is! Map || ((currentServer['url'] as String?) ?? '').isEmpty) {
        settings['server'] = bs['server'];
        settings['serverEnabled'] = bs['serverEnabled'];
      }
    } else {
      settings = {...bs, 'folders': usableFolders, 'audiobookFolders': usableBookFolders};
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
    // Tell the user if they'll need to type the server password in again.
    final needsPassword = s is Map &&
        ((s['url'] as String?) ?? '').isNotEmpty &&
        ((s['password'] as String?) ?? '').isEmpty;

    // ---- edits ----
    final be = backupFile('edits.json');
    final edits = merge ? {...await currentFile('edits.json'), ...be} : be;  // backup's edits win

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
      // Keep this device's scan as it is. The backup's songs go into the "missing" list, so
      // their edits and playlist places are kept and get matched up if the files turn up
      // later (see track_matching.dart). Duplicates are skipped.
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

    // Save the four main files. The optional files below are only replaced if the backup
    // has them (older backups didn't), so a replace never wipes them for no reason.
    await put('settings.json', settings);
    await put('edits.json', edits);
    await put('playlists.json', playlists);
    await put('library.json', library);

    // ---- place in audiobooks: for the same book, the most recent wins ----
    final bb = backupFile('listening.json');
    if (merge) {
      final cb = await currentFile('listening.json');
      await put('listening.json', {'books': mergeListening(cb['books'], bb['books'])});
    } else if (bb.isNotEmpty) {
      await put('listening.json', bb);
    }

    // ---- bookmarks: merging keeps both sets (same bookmark only once) ----
    final bm = backupFile('bookmarks.json');
    if (merge) {
      final cm = await currentFile('bookmarks.json');
      final seen = <Object?>{};
      await put('bookmarks.json', {
        'bookmarks': [
          for (final b in [...(cm['bookmarks'] as List? ?? const []), ...(bm['bookmarks'] as List? ?? const [])])
            if (b is Map && seen.add(b['id'])) b
        ],
      });
    } else if (bm.isNotEmpty) {
      await put('bookmarks.json', bm);
    }

    // ---- lyrics found online: merging keeps both (the backup's win) ----
    final bly = backupFile('lyrics.json');
    if (merge) {
      final cly = await currentFile('lyrics.json');
      Map<String, dynamic> part(Map<String, dynamic> m, String key) =>
          m[key] is Map ? Map<String, dynamic>.from(m[key] as Map) : <String, dynamic>{};
      await put('lyrics.json', {
        'found': {...part(cly, 'found'), ...part(bly, 'found')},
        'none': {...part(cly, 'none'), ...part(bly, 'none')},
      });
    } else if (bly.isNotEmpty) {
      await put('lyrics.json', bly);
    }

    // ---- equaliser: merging keeps this device's choices and adds the backup's own presets ----
    final beq = backupFile('equalizer.json');
    if (merge) {
      final ceq = await currentFile('equalizer.json');
      if (ceq.isEmpty) {
        if (beq.isNotEmpty) await put('equalizer.json', beq);
      } else {
        final here = (ceq['custom'] as List? ?? const []);
        final ids = {for (final c in here) if (c is Map) c['id']};
        await put('equalizer.json', {
          ...ceq,
          'custom': [
            ...here,
            for (final c in (beq['custom'] as List? ?? const [])) if (c is Map && !ids.contains(c['id'])) c
          ],
        });
      }
    } else if (beq.isNotEmpty) {
      await put('equalizer.json', beq);
    }

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
      final same = lists.where((x) => x['id'] == m['id']).firstOrNull;  // e.g. restored twice
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
    // Favourite albums and books: everything that's a favourite in either.
    List<Object?> both(String key) => {
          ...(current[key] as List? ?? const []),
          ...(incoming[key] as List? ?? const []),
        }.toList();
    return {
      'playlists': lists,
      'liked': liked,
      'favouriteAlbums': both('favouriteAlbums'),
      'favouriteBooks': both('favouriteBooks'),
    };
  }

  /// Combines two listening.json "books" maps, keeping the latest place per book.
  static Map<String, dynamic> mergeListening(Object? current, Object? incoming) {
    final out = <String, dynamic>{...?(current as Map?)?.cast<String, dynamic>()};
    for (final e in ((incoming as Map?) ?? const {}).entries) {
      final mine = out[e.key];
      final theirs = e.value;
      int updated(Object? v) => v is Map ? ((v['updated'] as int?) ?? 0) : -1;  // last-saved time
      if (mine == null || updated(theirs) > updated(mine)) out[e.key as String] = theirs;
    }
    return out;
  }

  /// Replaces paths inside [root] with "@app/..." (forward slashes).
  static Object? toPortable(Object? json, String root) => _mapStrings(json, (s) {
        if (!p.isAbsolute(s) || !p.isWithin(root, s)) return s;
        return appPrefix + p.split(p.relative(s, from: root)).join('/');
      });

  /// Turns "@app/..." back into a path inside [root]. A crafted value that would point outside
  /// the app's folder is dropped (becomes an empty string), so it can't aim a cover edit at an
  /// arbitrary file on the device.
  static Object? fromPortable(Object? json, String root) => _mapStrings(json, (s) {
        if (!s.startsWith(appPrefix)) return s;
        final rel = s.substring(appPrefix.length);
        if (!_safeRelative(rel)) return '';
        final dest = p.normalize(p.joinAll([root, ...rel.split('/')]));
        return p.isWithin(p.normalize(root), dest) ? dest : '';
      });

  /// Where a backup's cover image [key] (e.g. "art/custom/abc.png") should be written inside
  /// [root], or null if it would land anywhere but inside `art/`.
  ///
  /// HomeTunes: before 0.1.15 the check split keys on "/" only. On Windows "\" is a separator
  /// too, so a crafted key like `art/..\..\x` could write outside the app's folder. Now the key
  /// must be made of plain names (no "..", no "\", no drive letters), and the final path must
  /// be inside art/ after normalising.
  static File? safeArtDestination(String root, String key) {
    if (!_safeRelative(key)) return null;
    final parts = key.split('/');
    if (parts.length < 2 || parts.first != 'art') return null;
    final artDir = p.normalize(p.join(root, 'art'));
    final dest = p.normalize(p.joinAll([root, ...parts]));
    return p.isWithin(artDir, dest) ? File(dest) : null;
  }

  /// A relative path written with "/" whose parts are all plain names.
  static bool _safeRelative(String rel) {
    if (rel.isEmpty || rel.contains('\\') || rel.contains(':') || rel.startsWith('/')) return false;
    return rel.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');
  }

  /// Runs [f] on every string anywhere in a JSON tree (values only, not keys).
  static Object? _mapStrings(Object? json, String Function(String) f) {
    if (json is String) return f(json);
    if (json is List) return [for (final v in json) _mapStrings(v, f)];
    if (json is Map) return {for (final e in json.entries) e.key as String: _mapStrings(e.value, f)};
    return json;
  }
}

/// What's in a backup file.
class BackupContents {
  /// Data file name -> its JSON content, as stored (paths still portable).
  final Map<String, dynamic> files;
  /// Cover image path ("art/...") -> the picture as base64 text.
  final Map<String, String> art;
  /// When the backup was made.
  final DateTime? created;

  /// Operating system it was made on ("windows", "android"…).
  final String? from;

  const BackupContents({required this.files, required this.art, this.created, this.from});

  Map<String, dynamic> _file(String name) =>
      files[name] is Map ? Map<String, dynamic>.from(files[name] as Map) : const {};

  // Counts shown in the restore dialog so the user can see what's inside before restoring.
  int get playlistCount => (_file('playlists.json')['playlists'] as List? ?? const []).length;
  int get likedCount => (_file('playlists.json')['liked'] as List? ?? const []).length;
  int get editCount => _file('edits.json').length;
  int get bookmarkCount => (_file('bookmarks.json')['bookmarks'] as List? ?? const []).length;
  int get bookProgressCount => (_file('listening.json')['books'] as Map? ?? const {}).length;
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

/// What the restore screen should tell the user afterwards.
class RestoreResult {
  /// Music folders from the backup that don't exist on this device.
  final List<String> missingFolders;

  /// The backup has a server but no password (it wasn't included).
  final bool needsPassword;

  const RestoreResult({required this.missingFolders, required this.needsPassword});
}
