// Parts of the app that store song ids and must follow the library when songs move or are
// forgotten (refactor phase 2, 8 Oct 2026). Playlists, listening places, bookmarks and lyrics
// found online each keep song ids. Before, main.dart listed them by hand three times (which
// ids are still used, follow moved files, drop forgotten songs), and a new one could be left out
// of a list: lyrics were followed when files moved but kept when songs were forgotten.
// Now each one implements [SongIdFollower] and is connected once with [connectSongIdFollowers].
import 'library_model.dart';

/// Something that stores song ids and follows the library's changes to them.
abstract interface class SongIdFollower {
  /// Song ids this still points at. Missing songs with any of these are kept (with their edits
  /// and places) instead of being dropped at the next scan. Lyrics found online return none:
  /// they don't keep a missing song.
  Set<String> get referencedIds;

  /// Files moved: old id -> new id.
  void remapIds(Map<String, String> moved);

  /// The user chose to forget these missing songs.
  void removeIds(Set<String> ids);
}

/// Wires [followers] to [library]: asked which ids are still in use during a scan, told when
/// files move and when missing songs are forgotten.
void connectSongIdFollowers(LibraryModel library, List<SongIdFollower> followers) {
  library
    ..otherReferencedIds = (() => {for (final f in followers) ...f.referencedIds})
    ..onIdsRemapped = ((moved) {
      for (final f in followers) {
        f.remapIds(moved);
      }
    })
    ..onIdsForgotten = ((ids) {
      for (final f in followers) {
        f.removeIds(ids);
      }
    });
}
