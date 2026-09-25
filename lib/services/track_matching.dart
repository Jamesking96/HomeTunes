// Works out which "missing" songs are really the same files in a new place.
// LibraryModel calls matchMovedTracks after a scan with the songs that vanished and the songs
// that are new. For each match it swaps the old id for the new one everywhere (edits,
// playlists, listening places, bookmarks) through its onIdsRemapped callback, so nothing the
// user built up is lost when a folder is moved or renamed.
import '../models/track.dart';

/// Finds where songs that went missing have turned up again, e.g. after a
/// music folder was moved, a drive got a new letter, or a backup was restored
/// on another device. Returns old id → new id.
///
/// [gone] are songs HomeTunes knew about whose files aren't there any more;
/// [added] are songs found that weren't known before. A song is only matched
/// when there's exactly one good candidate, so nothing gets mixed up:
///  1. the same end of the path (at least "album folder / file name"),
///     preferring the longest match;
///  2. otherwise the same title, artist, album and track number (and a
///     length within 2 seconds when both lengths are known).
Map<String, String> matchMovedTracks(Iterable<Track> gone, Iterable<Track> added) {
  // Only local files can move; server songs keep their server id.
  final candidates = added.where((t) => t.isLocal && t.path != null).toList();
  // New songs already matched, so two old songs can't both claim the same one.
  final taken = <String>{};
  final result = <String, String>{};

  // Split every new path once up front, rather than again for each missing song.
  final addedParts = {for (final t in candidates) t.id: pathParts(t.path!)};

  for (final old in gone) {
    if (!old.isLocal || old.path == null) continue;
    final oldParts = pathParts(old.path!);

    // 1. Longest shared path ending.
    var best = 0;
    final bestIds = <String>[];
    for (final t in candidates) {
      if (taken.contains(t.id)) continue;
      final n = _sharedTail(oldParts, addedParts[t.id]!);
      if (n < 2) continue;  // just the file name matching isn't enough
      if (n > best) {
        best = n;
        bestIds
          ..clear()
          ..add(t.id);
      } else if (n == best) {
        bestIds.add(t.id);
      }
    }
    // A tie (e.g. two copies of the same album) is too risky to guess, so fall through.
    if (bestIds.length == 1) {
      result[old.id] = bestIds.single;
      taken.add(bestIds.single);
      continue;
    }

    // 2. Same details.
    final sig = signature(old);
    final same = [
      for (final t in candidates)
        if (!taken.contains(t.id) && signature(t) == sig && _closeLength(old, t)) t.id
    ];
    if (same.length == 1) {
      result[old.id] = same.single;
      taken.add(same.single);
    }
  }
  return result;
}

/// Path split into lower-case parts, whichever slashes it uses.
List<String> pathParts(String path) =>
    path.toLowerCase().split(RegExp(r'[\\/]+')).where((s) => s.isNotEmpty).toList();

/// How many path parts match, counting back from the file name.
int _sharedTail(List<String> a, List<String> b) {
  var n = 0;
  while (n < a.length && n < b.length && a[a.length - 1 - n] == b[b.length - 1 - n]) {
    n++;
  }
  return n;
}

/// Details that identify a song regardless of where its file is.
String signature(Track t) =>
    [t.title, t.artist, t.album, t.trackNumber ?? ''].map((v) => '$v'.trim().toLowerCase()).join('\u0000');

/// Lengths within 2 seconds, or at least one length unknown (then it can't rule a match out).
bool _closeLength(Track a, Track b) =>
    !a.hasDuration || !b.hasDuration || (a.duration - b.duration).abs() <= const Duration(seconds: 2);
