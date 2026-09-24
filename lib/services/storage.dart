import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Tiny JSON-file store kept in the app's support directory.
///
/// Files: library.json (scanned tracks), playlists.json, settings.json.
/// Cover art pulled out of audio files is cached in the `art/` subfolder.
///
/// Reads and writes to the same file are queued one after another, so quick
/// successive saves (e.g. liking several songs fast) can't trample each other.
class Storage {
  final Directory root;
  final Map<String, Future<void>> _locks = {};

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

  /// Runs [work] after any earlier read/write of [name] has finished.
  Future<T> _serial<T>(String name, Future<T> Function() work) {
    final previous = _locks[name] ?? Future<void>.value();
    final result = previous.then((_) => work());
    // Keep the chain going even if this step fails.
    _locks[name] = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<dynamic> read(String name) => _serial(name, () async {
        final f = File(p.join(root.path, name));
        if (!await f.exists()) return null;
        try {
          return jsonDecode(await f.readAsString());
        } catch (_) {
          return null; // corrupt file: start fresh rather than crash
        }
      });

  /// Writes via a temp file + rename so a crash never leaves half a file.
  /// Returns false (and logs) instead of throwing if the disk write fails.
  Future<bool> write(String name, Object json) => _serial(name, () async {
        final f = File(p.join(root.path, name));
        final tmp = File('${f.path}.tmp');
        try {
          await tmp.writeAsString(jsonEncode(json), flush: true);
          if (await f.exists()) await f.delete();
          await tmp.rename(f.path);
          return true;
        } catch (e) {
          debugPrint('HomeTunes: could not save $name: $e');
          return false;
        }
      });
}
