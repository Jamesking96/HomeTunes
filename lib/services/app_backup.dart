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

import 'book_sidecar.dart' show companionExtensions;
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
    'videos.json',  // 0.1.40: the Videos tab (edits and watched places)
    'history.json', // 0.1.45: recently played music (Home's "Jump back in")
    'servers.json', // 0.1.46: the other servers (never their passwords)
  ];

  /// Marks a path inside the app's folder in a backup.
  static const appPrefix = '@app/';

  /// Name of the automatic backup taken just before a restore.
  static const beforeRestoreName = 'before-restore.$fileExtension';

  /// The largest backup file HomeTunes will open, and the most it may unpack to. A real backup
  /// is a few MB (mostly covers); these limits stop a damaged or crafted file from using up all
  /// the memory (0.1.21, security review #7).
  static const maxFileBytes = 256 << 20;
  static const maxUnpackedBytes = 512 << 20;

  /// Builds a backup of [storage]. [includeCoverCache] adds the covers pulled out
  /// of music files (they can be re-read by a rescan, so they're optional);
  /// covers chosen or downloaded by the user are always included.
  ///
  /// The server password is never included (0.1.21, security review #6: it would be plain text
  /// in the file). Server covers downloaded for the media controls (art/server) are left out too;
  /// they're downloaded again when needed.
  static Future<Uint8List> create(Storage storage, {bool includeCoverCache = true}) async {
    final root = storage.root.path;
    // 1. The data files, with app paths made portable.
    final files = <String, dynamic>{};
    for (final name in dataFiles) {
      final j = await storage.read(name);
      if (j == null) continue;
      files[name] = toPortable(j, root);
    }
    // 2. Never the server password. (Since 0.1.17 it's normally in protected storage anyway, but
    //    on a device without that it's still in settings.json.)
    final settings = files['settings.json'];
    if (settings is Map && settings['server'] is Map) {
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
        final parts = p.split(rel);
        if (parts.length > 1 && parts[1] == 'server') continue;  // art/server: downloaded again
        final custom = parts.contains('custom');
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

  /// Reads a backup file's bytes. Throws [FormatException] if it isn't one, or if it's bigger
  /// than [maxFileBytes] or unpacks to more than [maxUnpacked] (tests pass a smaller limit).
  static BackupContents read(List<int> bytes, {int maxUnpacked = maxUnpackedBytes}) {
    if (bytes.length > maxFileBytes) {
      throw const FormatException('This backup is too large to be a HomeTunes backup.');
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(_gunzipCapped(bytes, maxUnpacked)));
    } on _TooLarge {
      throw const FormatException('This backup is too large or damaged.');
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

    // Helpers: one data file from the backup (with paths made local again, and paths that
    // could be misused taken out, see [sanitize]), and the same file as it is on this device
    // now. Both give an empty map if missing.
    Map<String, dynamic> backupFile(String name) {
      final j = backup.files[name];
      return j is Map ? sanitize(name, Map<String, dynamic>.from(fromPortable(j, root) as Map), root) : <String, dynamic>{};
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
    final backupVideoFolders = (bs['videoFolders'] as List? ?? const []).cast<String>();
    // Folders from another device usually don't exist here; they're dropped and reported.
    final missingFolders = [
      for (final f in [...backupFolders, ...backupBookFolders, ...backupVideoFolders]) if (!Directory(f).existsSync()) f
    ];
    final usableFolders = [for (final f in backupFolders) if (Directory(f).existsSync()) f];
    final usableBookFolders = [for (final f in backupBookFolders) if (Directory(f).existsSync()) f];
    final usableVideoFolders = [for (final f in backupVideoFolders) if (Directory(f).existsSync()) f];
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
      final currentVideos = (cs['videoFolders'] as List? ?? const []).cast<String>();
      settings['videoFolders'] = [
        ...currentVideos,
        for (final f in usableVideoFolders) if (!currentVideos.contains(f)) f,
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
      settings = {
        ...bs,
        'folders': usableFolders,
        'audiobookFolders': usableBookFolders,
        'videoFolders': usableVideoFolders,
      };
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

    // ---- videos (0.1.40): merging keeps this device's scan, adds the backup's edits (they win)
    //      and keeps the latest place for each video ----
    final bv = backupFile('videos.json');
    if (merge) {
      final cv = await currentFile('videos.json');
      Map<String, dynamic> part(Map<String, dynamic> m, String key) =>
          m[key] is Map ? Map<String, dynamic>.from(m[key] as Map) : <String, dynamic>{};
      final places = part(cv, 'places');
      for (final e in part(bv, 'places').entries) {
        int updated(Object? v) => v is Map ? ((v['updatedMs'] as int?) ?? 0) : -1;
        if (updated(e.value) > updated(places[e.key])) places[e.key] = e.value;
      }
      if (cv.isNotEmpty || bv.isNotEmpty) {
        await put('videos.json', {
          'videos': cv['videos'] ?? bv['videos'] ?? const [],
          'edits': {...part(cv, 'edits'), ...part(bv, 'edits')},
          'places': places,
          // Favourite collections from both; the backup's descriptions and track choices win.
          'favourites': {...(cv['favourites'] as List? ?? const []), ...(bv['favourites'] as List? ?? const [])}.toList(),
          'descriptions': {...part(cv, 'descriptions'), ...part(bv, 'descriptions')},
          'trackChoices': {...part(cv, 'trackChoices'), ...part(bv, 'trackChoices')},
          // Pictures the user chose for videos and collections: the backup's win.
          'pictures': {...part(cv, 'pictures'), ...part(bv, 'pictures')},
          'posters': {...part(cv, 'posters'), ...part(bv, 'posters')},
          // Picture shapes and speeds per video / collection: the backup's win.
          'shapes': {...part(cv, 'shapes'), ...part(bv, 'shapes')},
          'collectionShapes': {...part(cv, 'collectionShapes'), ...part(bv, 'collectionShapes')},
          'speeds': {...part(cv, 'speeds'), ...part(bv, 'speeds')},
          // Season titles the user gave, per collection: the backup's win.
          'seasonTitles': {...part(cv, 'seasonTitles'), ...part(bv, 'seasonTitles')},
          // Seasons marked special (0.1.66), per collection: the backup's win.
          'specialSeasons': {...part(cv, 'specialSeasons'), ...part(bv, 'specialSeasons')},
          if (cv['saveNfo'] == false) 'saveNfo': false,
        });
      }
    } else if (bv.isNotEmpty) {
      await put('videos.json', bv);
    }

    // ---- recently played music (0.1.45): merging keeps both, newest first, each place once ----
    final bh = backupFile('history.json');
    if (merge) {
      final ch = await currentFile('history.json');
      if (ch.isNotEmpty || bh.isNotEmpty) await put('history.json', {'played': mergeHistory(ch['played'], bh['played'])});
    } else if (bh.isNotEmpty) {
      await put('history.json', bh);
    }

    // ---- your other servers (0.1.46): merging adds the backup's ones that aren't here (same
    //      kind, address and user name counts as the same server). Passwords are never in a
    //      backup: they're typed again on this device. ----
    final bsv = backupFile('servers.json');
    for (final s in (bsv['servers'] as List? ?? const [])) {
      if (s is Map) s.remove('password'); // never written, but a hand-made backup could hold one
    }
    if (merge) {
      final csv = await currentFile('servers.json');
      String same(Object? s) => s is Map ? '${s['type']}|${s['url']}|${s['username'] ?? ''}' : '';
      final here = [...(csv['servers'] as List? ?? const [])];
      final seen = {for (final s in here) same(s)};
      final added = [for (final s in (bsv['servers'] as List? ?? const [])) if (s is Map && seen.add(same(s))) s];
      if (here.isNotEmpty || added.isNotEmpty) {
        await put('servers.json', {...csv, 'servers': [...here, ...added]});
      }
    } else if (bsv.isNotEmpty) {
      await put('servers.json', bsv);
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

  /// Combines two history.json "played" lists: newest first, each place (kind + key) once, at
  /// most 50 (PlayHistory.max).
  static List<Map<String, dynamic>> mergeHistory(Object? current, Object? incoming) {
    final all = [
      for (final x in [...(current as List? ?? const []), ...(incoming as List? ?? const [])])
        if (x is Map && x['at'] is int) Map<String, dynamic>.from(x),
    ]..sort((a, b) => (b['at'] as int).compareTo(a['at'] as int));
    final seen = <String>{};
    return [for (final x in all) if (seen.add('${x['kind']}|${x['key']}')) x].take(50).toList();
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

  /// Takes out paths in a restored data file that HomeTunes would act on but that a normal backup
  /// never contains (0.1.21, security review #3). A backup is just a file, and it could have been
  /// edited to point HomeTunes at anything on the computer:
  ///  * edits.json: a custom cover must be inside the app's art folder (every cover the user
  ///    chooses is copied there first), so any other path is dropped;
  ///  * library.json: a book's extra files ("companions") must be PDFs or EPUBs;
  ///  * settings.json: an artist's own picture (0.1.53) must be inside the art folder too.
  /// Everything else stays; song paths are needed to match songs up, and they're checked again
  /// before a file is played, opened or written (see path_safety.dart).
  static Map<String, dynamic> sanitize(String name, Map<String, dynamic> json, String root) {
    if (name == 'edits.json') {
      final artDir = p.normalize(p.join(root, 'art'));
      for (final e in json.values) {
        if (e is! Map) continue;
        final art = e['art'];
        if (art is String && !p.isWithin(artDir, p.normalize(art))) e.remove('art');
      }
    } else if (name == 'settings.json') {
      // Artists' own pictures (0.1.53) must be in the art folder too (or name one of their albums).
      final artDir = p.normalize(p.join(root, 'art'));
      final m = json['artistPictures'];
      if (m is Map) {
        m.removeWhere((_, v) => v is! String || (!v.startsWith('album:') && !p.isWithin(artDir, p.normalize(v))));
      }
    } else if (name == 'videos.json') {
      // A video's thumbnail must be in the app's art folder (they're made there); anything else
      // is dropped and made again.
      final artDir = p.normalize(p.join(root, 'art'));
      final list = json['videos'];
      if (list is List) {
        for (final v in list) {
          if (v is! Map) continue;
          final thumb = v['thumb'];
          if (thumb is String && !p.isWithin(artDir, p.normalize(thumb))) v.remove('thumb');
        }
      }
      // So must the pictures chosen for videos and collections (they're copied there).
      for (final key in const ['pictures', 'posters']) {
        final m = json[key];
        if (m is Map) m.removeWhere((_, v) => v is! String || !p.isWithin(artDir, p.normalize(v)));
      }
    } else if (name == 'library.json') {
      for (final key in const ['local', 'remote', 'missing']) {
        final list = json[key];
        if (list is! List) continue;
        for (final t in list) {
          if (t is! Map || t['companions'] is! List) continue;
          t['companions'] = [
            for (final c in t['companions'] as List)
              if (c is String && companionExtensions.contains(p.extension(c).toLowerCase())) c
          ];
        }
      }
    }
    return json;
  }

  /// Unpacks gzip data, stopping with [_TooLarge] as soon as the output passes [max] bytes (a
  /// tiny crafted file can otherwise unpack to gigabytes).
  static List<int> _gunzipCapped(List<int> bytes, int max) {
    final out = _CappedSink(max);
    final input = gzip.decoder.startChunkedConversion(out);
    const step = 16 << 10;
    for (var i = 0; i < bytes.length; i += step) {
      input.add(bytes.sublist(i, i + step > bytes.length ? bytes.length : i + step));
    }
    input.close();
    return out.bytes.takeBytes();
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

/// Thrown by [AppBackup._gunzipCapped] when a backup unpacks to more than the limit.
class _TooLarge implements Exception {
  const _TooLarge();
}

/// Collects unpacked bytes, and gives up once there are too many.
class _CappedSink implements Sink<List<int>> {
  final int max;
  final BytesBuilder bytes = BytesBuilder(copy: false);
  _CappedSink(this.max);

  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > max) throw const _TooLarge();
    bytes.add(chunk);
  }

  @override
  void close() {}
}
