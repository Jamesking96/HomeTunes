/// A user playlist. Stores track ids so it survives rescans.
class Playlist {
  final String id;
  String name;
  final List<String> trackIds;
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
