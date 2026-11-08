// The person using HomeTunes now (Profiles plan, phase 0: claude/06_PROFILES_PLAN.md).
//
// The user (4 Nov 2026): "an optional system that can be turned on via the settings page, where
// everything we do is split between profiles". The models that hold what a person did or chose
// (playlists, places, bookmarks, the equaliser, recently played, their edits) save through
// [storage], this person's folder; the shared ones (the scanned library, the servers, downloads,
// lyrics found online) through the data folder. Phase 0 has no profiles yet: [id] is null and
// [storage] is the data folder itself, so every file stays where it was. Phase 1 adds the real
// profiles and switching between them.
import '../services/storage.dart';

class ProfileSession {
  ProfileSession._(this.id, this.storage);

  /// The session for profile [id] (null: profiles are off) in the data folder [data].
  factory ProfileSession.of(Storage data, String? id) => ProfileSession._(id, data.forProfile(id));

  /// The profile's id (null while profiles are off).
  final String? id;

  /// Where this person's own files are kept.
  final Storage storage;
}
