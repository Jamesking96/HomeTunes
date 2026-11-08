// Where HomeTunes keeps its own data on disk: small JSON files in <app support>/hometunes/.
// main() opens one Storage and hands it to every model (library, playlists, listening places,
// bookmarks, lyrics, equaliser), which call read()/write() with a file name like 'library.json'.
// Safety ideas:
//  - saves to the same file wait their turn (a per-file queue);
//  - each save is written to a temp file first and then renamed over the old one in a single
//    step, so a crash leaves either the old file or the new one, never half a file;
//  - a file that can't be read is never silently thrown away: it's recovered from the temp file
//    if possible, otherwise kept aside as `<name>.corrupt-<date>.json`, and the problem is
//    reported (see [problems]) so the app can tell the user.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Tiny JSON-file store kept in the app's support directory.
///
/// Files: settings.json, library.json, edits.json, playlists.json, listening.json,
/// bookmarks.json, lyrics.json and equalizer.json (see AppBackup.dataFiles).
/// Cover art pulled out of audio files is cached in the `art/` subfolder.
///
/// Reads and writes to the same file are queued one after another, so quick
/// successive saves (e.g. liking several songs fast) can't trample each other.
class Storage with ChangeNotifier {
  /// The hometunes folder that holds all the JSON files and the art cache.
  final Directory root;
  // For each file name, the last queued read/write. New work is chained after it.
  final Map<String, Future<void>> _locks = {};

  /// Messages for the user about data files that were damaged or recovered, oldest first.
  /// LibraryModel shows them in the status strip until the user dismisses them.
  final List<String> problems = [];

  /// How many damaged copies of each file are kept (older ones are deleted).
  static const keepCorruptCopies = 3;

  Storage._(this.root, [this._parent]);

  /// The storage this is a profile's view of (null: this is the data folder itself).
  final Storage? _parent;

  /// Where messages about damaged files and failed saves are kept and shown: the data folder's
  /// storage, whichever view saved.
  Storage get _owner => _parent ?? this;

  final Map<String, Storage> _views = {};

  /// Where profile [id]'s own files are kept (Profiles plan, phase 0: claude/06_PROFILES_PLAN.md):
  /// `profiles/<id>/` under this folder, with the same safe saving, sharing this folder's art
  /// folder and its messages. With profiles off ([id] null) it's this folder itself, so nothing
  /// moves and every file stays where it was.
  Storage forProfile(String? id) {
    if (id == null) return _parent == null ? this : _parent.forProfile(null);
    if (_parent != null) return _parent.forProfile(id);
    if (!RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(id)) throw ArgumentError.value(id, 'id', 'not a profile id');
    return _views[id] ??= () {
      final dir = Directory(p.join(root.path, 'profiles', id))..createSync(recursive: true);
      return Storage._(dir, this);
    }();
  }

  /// Finds (and creates if needed) the data folder. On Windows this is under AppData\Roaming,
  /// on Android inside the app's private storage.
  static Future<Storage> open() async {
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'hometunes'));
    await root.create(recursive: true);
    await Directory(p.join(root.path, 'art')).create(recursive: true);
    return Storage._(root);
  }

  /// For tests.
  factory Storage.at(Directory dir) => Storage._(dir);

  /// Folder for cached cover images (see local_scanner.dart).
  String get artDir => _parent?.artDir ?? p.join(root.path, 'art');

  /// Saves that failed, by file name, with the message to show. Cleared when that file next
  /// saves successfully (0.1.16: failed saves used to be silent).
  final Map<String, String> _saveFailures = {};

  /// Everything to tell the user about the data files: damaged or recovered files, and saves
  /// that are failing. Listeners are told whenever this changes.
  List<String> get messages => [...problems, ..._saveFailures.values];

  /// Adds a message for the user (see [problems]).
  void report(String message) {
    if (_parent != null) return _parent.report(message);
    debugPrint('HomeTunes: $message');
    if (!problems.contains(message)) {
      problems.add(message);
      notifyListeners();
    }
  }

  /// The user dismissed the messages. A save that fails again reports itself again.
  void clearMessages() {
    if (problems.isEmpty && _saveFailures.isEmpty) return;
    problems.clear();
    _saveFailures.clear();
    notifyListeners();
  }

  /// Runs [work] after any earlier read/write of [name] has finished.
  Future<T> _serial<T>(String name, Future<T> Function() work) {
    final previous = _locks[name] ?? Future<void>.value();
    final result = previous.then((_) => work());
    // Keep the chain going even if this step fails.
    _locks[name] = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Reads and decodes a JSON file. Null if it doesn't exist yet (first run) or can't be
  /// read or recovered.
  ///
  /// HomeTunes: a damaged file used to read as null, and the model's next save then replaced
  /// it with an empty one (e.g. every playlist lost). Now:
  ///  1. a readable file is returned as before;
  ///  2. a damaged file is renamed to `<name>.corrupt-<date>.json` (kept, never overwritten);
  ///  3. if the file is damaged or missing but a complete `<name>.tmp` from an interrupted
  ///     save is there, that is used and put in place;
  ///  4. otherwise null, with a message in [problems] if a damaged file was set aside.
  Future<dynamic> read(String name) => _serial(name, () async {
        final f = File(p.join(root.path, name));
        final tmp = File('${f.path}.tmp');
        String? keptAs;
        if (await f.exists()) {
          try {
            final size = await f.length();
            if (size >= bigFileBytes) {
              _big.add(name);
              return await _decodeFileInBackground(f.path);
            }
            return _decode(await f.readAsString());
          } catch (_) {
            keptAs = await _setAside(f, name);
          }
        }
        // Missing or damaged: an interrupted save may have left a complete temp file.
        if (await tmp.exists()) {
          try {
            final json = _decode(await tmp.readAsString());
            await tmp.rename(f.path);
            report('HomeTunes recovered your ${describe(name)} from an unfinished save.');
            return json;
          } catch (_) {
            // Half-written temp file: nothing to recover from it.
          }
        }
        if (keptAs != null) {
          report('Your ${describe(name)} file was damaged and couldn\'t be read. '
              'A copy was kept as $keptAs.');
        }
        return null;
      });

  /// For a file that is valid JSON but whose contents a model couldn't fully make sense of
  /// (a wrong type somewhere, e.g. after hand-editing): keeps a copy as
  /// `<name>.corrupt-<date>.json` before the model's next save replaces it, and reports it.
  /// The model carries on with whatever it could read (or its defaults).
  Future<void> keepCopy(String name) => _serial(name, () async {
        final f = File(p.join(root.path, name));
        if (!await f.exists()) return;
        final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
        final keptName = '${p.basenameWithoutExtension(name)}.corrupt-$stamp${p.extension(name)}';
        try {
          await f.copy(p.join(root.path, keptName));
          await _tidyCopies(name);
          report('Part of your ${describe(name)} couldn\'t be read. A copy of the file was kept as $keptName.');
        } catch (e) {
          report('Part of your ${describe(name)} couldn\'t be read.');
        }
      });

  /// Files this big (or bigger) are read, turned into text and written in a background isolate
  /// (0.2.12). The user (8 Nov 2026): the TVs "can stutter sometimes while streaming and … [are]
  /// rather slow to respond". server_videos.json (the Jellyfin catalogue, 7.4 MB for ~5,900
  /// videos) was encoded on the thread that draws the screen and handles the remote: ~100 ms on
  /// the PC, about a second on the test TV, at every sync and more. In an isolate the
  /// screen's thread only hands the data over (~20 ms on the PC). Small files stay as they were:
  /// for them an isolate costs more than it saves.
  static const bigFileBytes = 256 * 1024;

  /// Files known to be big (from their last read or save).
  final Set<String> _big = {};

  /// Whether [name] is saved in the background (tests).
  @visibleForTesting
  bool isBig(String name) => _big.contains(name);

  /// Reads and decodes [path] in an isolate; the result comes back without being copied.
  static Future<dynamic> _decodeFileInBackground(String path) =>
      Isolate.run(() => _decode(File(path).readAsStringSync()));

  /// Encodes [json] and writes it to [path] (flushed) in an isolate; returns the text's length.
  /// Static, so the isolate is handed only [path] and [json], never this Storage.
  static Future<int> _writeInBackground(String path, Object json) => Isolate.run(() {
        final text = jsonEncode(json);
        File(path).writeAsStringSync(text, flush: true);
        return text.length;
      });

  /// Decodes JSON text; an empty file counts as damaged (it's what an interrupted write
  /// can leave on some file systems).
  static dynamic _decode(String text) {
    if (text.trim().isEmpty) throw const FormatException('empty file');
    return jsonDecode(text);
  }

  /// Renames a damaged file out of the way and keeps only the newest few copies.
  /// Returns the new file name, or null if it couldn't be moved.
  Future<String?> _setAside(File f, String name) async {
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final base = p.basenameWithoutExtension(name);
    final keptName = '$base.corrupt-$stamp${p.extension(name)}';
    try {
      await f.rename(p.join(root.path, keptName));
    } catch (e) {
      debugPrint('HomeTunes: could not set aside damaged $name: $e');
      return null;
    }
    await _tidyCopies(name);
    return keptName;
  }

  /// Keeps only the newest [keepCorruptCopies] damaged copies of [name].
  Future<void> _tidyCopies(String name) async {
    final base = p.basenameWithoutExtension(name);
    // Newest copies first (the date in the name sorts correctly), drop the rest.
    try {
      final copies = [
        await for (final e in root.list())
          if (e is File && p.basename(e.path).startsWith('$base.corrupt-')) e,
      ]..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
      for (final old in copies.skip(keepCorruptCopies)) {
        await old.delete();
      }
    } catch (_) {
      // Tidying is best effort.
    }
  }

  /// Writes via a temp file + rename so a crash never leaves half a file.
  /// Returns false (and logs) instead of throwing if the disk write fails.
  ///
  /// HomeTunes: the old file used to be deleted before the rename ("renaming onto an existing
  /// file fails on Windows"). It doesn't: Dart's rename replaces the target on Windows too, in
  /// one step. The delete only opened a moment where a crash left no file at all.
  Future<bool> write(String name, Object json) => _serial(name, () async {
        final f = File(p.join(root.path, name));
        final tmp = File('${f.path}.tmp');
        try {
          final int length;
          if (_big.contains(name)) {
            length = await _writeInBackground(tmp.path, json);
          } else {
            final text = jsonEncode(json);
            length = text.length;
            await tmp.writeAsString(text, flush: true);
          }
          // Big enough that the next save is made in the background; small again: here.
          length >= bigFileBytes ? _big.add(name) : _big.remove(name);
          await tmp.rename(f.path);
          // A save that works again clears its failure message.
          if (_owner._saveFailures.remove(name) != null) _owner.notifyListeners();
          return true;
        } catch (e) {
          debugPrint('HomeTunes: could not save $name: $e');
          // One message per file, kept until that file saves again (not one per attempt).
          final reason = e is FileSystemException ? (e.osError?.message ?? e.message) : '$e';
          final message = 'HomeTunes couldn\'t save your ${describe(name)} ($reason). '
              'Recent changes may be lost when the app closes.';
          if (_owner._saveFailures[name] != message) {
            _owner._saveFailures[name] = message;
            _owner.notifyListeners();
          }
          return false;
        }
      });

  /// Whether data file [name] is here (after any save of it that's waiting).
  Future<bool> has(String name) => _serial(name, () => File(p.join(root.path, name)).exists());

  /// Copies data file [name] to [to] (another folder's view), as it is, if it's here. Returns
  /// whether there was one. For moving a person's files in and out of their profile (phase 1).
  Future<bool> copyTo(Storage to, String name) => _serial(name, () async {
        final f = File(p.join(root.path, name));
        if (!await f.exists()) return false;
        final bytes = await f.readAsBytes();
        await to._serial(name, () async {
          final dest = File(p.join(to.root.path, name));
          final tmp = File('${dest.path}.tmp');
          await tmp.writeAsBytes(bytes, flush: true);
          await tmp.rename(dest.path);
          to._big.remove(name);
        });
        return true;
      });

  /// Deletes data file [name] (and any unfinished save of it). For the person's files left in
  /// the data folder once they've moved into a profile (phase 1).
  Future<void> remove(String name) => _serial(name, () async {
        for (final f in [File(p.join(root.path, name)), File(p.join(root.path, '$name.tmp'))]) {
          if (await f.exists()) await f.delete();
        }
        _big.remove(name);
      });

  /// The ids of the profile folders there are (`profiles/<id>/`).
  List<String> profileFolders() {
    final dir = Directory(p.join((_parent ?? this).root.path, 'profiles'));
    if (!dir.existsSync()) return const [];
    return [
      for (final e in dir.listSync())
        if (e is Directory) p.basename(e.path),
    ]..sort();
  }

  /// Deletes profile [id]'s folder and everything in it (Settings › Profiles › Remove).
  Future<void> deleteProfile(String id) async {
    if (_parent != null) return _parent.deleteProfile(id);
    final view = forProfile(id);
    _views.remove(id);
    if (await view.root.exists()) await view.root.delete(recursive: true);
  }

  /// A data file's name in words, for messages ("playlists and Liked Songs").
  static String describe(String name) => switch (name) {
        'settings.json' => 'settings',
        'library.json' => 'library list',
        'edits.json' => 'song edits',
        'playlists.json' => 'playlists and Liked Songs',
        'listening.json' => 'audiobook places',
        'bookmarks.json' => 'bookmarks',
        'lyrics.json' => 'saved lyrics',
        'equalizer.json' => 'equaliser settings',
        'videos.json' => 'list of videos',
        'video_edits.json' => 'video edits',
        'video_places.json' => 'watched videos and places',
        'profiles.json' => 'list of profiles',
        _ => name,
      };
}
