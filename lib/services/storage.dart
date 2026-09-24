import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Tiny JSON-file store kept in the app's support directory.
///
/// Files: library.json (scanned tracks), playlists.json, settings.json.
/// Cover art pulled out of audio files is cached in the `art/` subfolder.
class Storage {
  final Directory root;

  Storage._(this.root);

  static Future<Storage> open() async {
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'hometunes'));
    await root.create(recursive: true);
    await Directory(p.join(root.path, 'art')).create(recursive: true);
    return Storage._(root);
  }

  /// For tests.
  factory Storage.at(Directory dir) => Storage._(dir);

  String get artDir => p.join(root.path, 'art');

  Future<dynamic> read(String name) async {
    final f = File(p.join(root.path, name));
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null; // corrupt file: start fresh rather than crash
    }
  }

  /// Writes via a temp file + rename so a crash never leaves half a file.
  Future<void> write(String name, Object json) async {
    final f = File(p.join(root.path, name));
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(json));
    if (await f.exists()) await f.delete();
    await tmp.rename(f.path);
  }
}
