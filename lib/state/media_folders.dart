// Folder rules shared by the music / audiobook library (LibraryModel) and the Videos tab
// (VideoLibraryModel), refactor phase 2 (8 Oct 2026). Each model had its own copy of these, and
// the copies had started to differ (the video one compared folder paths by text length).
// - Which folder's options apply to a file: the deepest library folder holding it.
// - A folder's file types, with how many files of each (Folder options › File types).
// - Whether a folder can be reached right now, and which unreachable folders count as offline
//   (their files are kept as they were) rather than gone.
// No Flutter, so it's tested directly.
import 'dart:io';

import 'package:path/path.dart' as p;

import 'book_index.dart' show isInside, splitPath;

/// A file's type as Folder options shows it: its extension in lower case, without the dot.
String fileFormatOf(String path) => p.extension(path).replaceFirst('.', '').toLowerCase();

/// The folder in [folders] whose options apply to [path]: the innermost one holding it, by
/// how many folders deep it is (an audiobook folder inside a music folder has its own options).
String? owningFolder(String path, Iterable<String> folders) {
  String? best;
  for (final f in folders) {
    if (isInside(path, f) && (best == null || splitPath(f).length > splitPath(best).length)) best = f;
  }
  return best;
}

/// The file types among [paths] owned by [folder] (see [owningFolder]), with how many files of
/// each, A–Z.
Map<String, int> formatCounts(Iterable<String> paths, String folder, Iterable<String> folders) {
  final counts = <String, int>{};
  for (final path in paths) {
    if (owningFolder(path, folders) == folder) {
      final f = fileFormatOf(path);
      counts[f] = (counts[f] ?? 0) + 1;
    }
  }
  return {for (final k in counts.keys.toList()..sort()) k: counts[k]!};
}

/// How long to wait for a folder (e.g. a sleeping network share) before counting it offline.
const folderCheckTimeout = Duration(seconds: 10);

/// Whether [folder] exists and can be listed right now.
Future<bool> canListFolder(String folder) async {
  try {
    final dir = Directory(folder);
    if (!await dir.exists()) return false;
    await dir.list(followLinks: false).take(1).toList().timeout(folderCheckTimeout);
    return true;
  } catch (_) {
    return false;
  }
}

/// Splits [folders] into those that can be reached now and those that are offline (a drive
/// that isn't plugged in, a network share that's asleep). A missing folder inside one that can
/// be reached has really gone (its drive is there), so it counts as neither.
Future<({List<String> reachable, List<String> offline})> checkFolders(
    Iterable<String> folders, Future<bool> Function(String folder) reachableNow) async {
  final reachable = <String>[];
  final unreachable = <String>[];
  for (final f in folders) {
    (await reachableNow(f) ? reachable : unreachable).add(f);
  }
  return (
    reachable: reachable,
    offline: [for (final f in unreachable) if (!reachable.any((r) => isInside(f, r))) f],
  );
}
