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

  /// The playlist's own icon (0.1.67, the user's request): a built-in icon by name
  /// (widgets/playlist_art.dart lists them) on a colour (ARGB; null = the theme's accent), or a
  /// picture the user chose, stored by file name in the playlist pictures folder
  /// (PlaylistsModel.pictureFile). None of them: the first song's cover, as before.
  String? iconName;
  int? iconColour;
  String? iconImage;

  /// Profiles, phase 4: what the other profiles may do with it, as the owner chose
  /// ([PlaylistSharing]). Saved with the owner's playlist.
  PlaylistSharing sharing;

  /// Set on another profile's shared playlist while it's shown to someone else (never saved):
  /// whose it is. Null on your own.
  String? ownerId;
  String? ownerName;

  Playlist({
    required this.id,
    required this.name,
    List<String>? trackIds,
    int? createdMs,
    this.iconName,
    this.iconColour,
    this.iconImage,
    this.sharing = PlaylistSharing.off,
    this.ownerId,
    this.ownerName,
  })  : trackIds = trackIds ?? [],
        createdMs = createdMs ?? DateTime.now().millisecondsSinceEpoch;

  /// Whether the user gave it an icon or picture of its own.
  bool get hasOwnIcon => iconName != null || iconImage != null;

  /// Yours (not another profile's shared playlist).
  bool get isMine => ownerId == null;

  /// Songs can be added, removed and moved: yours, or shared with "play and change".
  bool get canChangeSongs => isMine || sharing == PlaylistSharing.change;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdMs': createdMs,
        if (iconName != null) 'iconName': iconName,
        if (iconColour != null) 'iconColour': iconColour,
        if (iconImage != null) 'iconImage': iconImage,
        if (sharing != PlaylistSharing.off) 'sharing': sharing.name,
      };

  factory Playlist.fromJson(Map<String, dynamic> j) {
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    // Only a plain file name: a picture can't point outside the pictures folder.
    final image = text(j['iconImage']);
    return Playlist(
      id: j['id'] as String,
      name: j['name'] as String,
      trackIds: (j['trackIds'] as List).cast<String>().toList(),
      createdMs: j['createdMs'] as int?,
      iconName: text(j['iconName']),
      iconColour: j['iconColour'] is int ? j['iconColour'] as int : null,
      iconImage: image != null && RegExp(r'^[\w.-]+$').hasMatch(image) && !image.startsWith('.') ? image : null,
      sharing: PlaylistSharing.values.where((s) => s.name == j['sharing']).firstOrNull ?? PlaylistSharing.off,
    );
  }
}

/// What the other profiles may do with a playlist (Profiles, phase 4; the owner chooses).
enum PlaylistSharing {
  /// Only its owner sees it.
  off('Not shared', 'Only you see it'),

  /// Everyone else sees it and can play it.
  play('Others can play it', 'Everyone else sees it and can play it'),

  /// Everyone else can also add, remove and move its songs.
  change('Others can play and change it', 'Everyone else can play it and add, remove or move songs');

  const PlaylistSharing(this.label, this.detail);
  final String label, detail;
}
