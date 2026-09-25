// The Playlist model: a named list of song ids.
// PlaylistsModel (state/playlists_model.dart) keeps all playlists, including Liked Songs,
// in playlists.json. Only ids are stored, not the songs themselves, so a playlist keeps
// working after rescans, and the library can follow a song that moved (ids get remapped).
/// A user playlist. Stores track ids so it survives rescans.
class Playlist {
  final String id;
  /// Shown to the user. Not final, so a playlist can be renamed in place.
  String name;
  /// Song ids (see Track.id) in playing order.
  final List<String> trackIds;
  /// When the playlist was made (milliseconds since 1970), used for sorting.
  final int createdMs;

  Playlist({required this.id, required this.name, List<String>? trackIds, int? createdMs})
      : trackIds = trackIds ?? [],
        createdMs = createdMs ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdMs': createdMs,
      };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String,
        trackIds: (j['trackIds'] as List).cast<String>().toList(),
        createdMs: j['createdMs'] as int?,
      );
}
