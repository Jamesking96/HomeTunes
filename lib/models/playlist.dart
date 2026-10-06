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

  Playlist({
    required this.id,
    required this.name,
    List<String>? trackIds,
    int? createdMs,
    this.iconName,
    this.iconColour,
    this.iconImage,
  })  : trackIds = trackIds ?? [],
        createdMs = createdMs ?? DateTime.now().millisecondsSinceEpoch;

  /// Whether the user gave it an icon or picture of its own.
  bool get hasOwnIcon => iconName != null || iconImage != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdMs': createdMs,
        if (iconName != null) 'iconName': iconName,
        if (iconColour != null) 'iconColour': iconColour,
        if (iconImage != null) 'iconImage': iconImage,
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
    );
  }
}
