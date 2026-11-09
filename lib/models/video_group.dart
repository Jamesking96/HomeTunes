// Film collections (plan: docs/ai-context/07_FILM_COLLECTIONS_PLAN.md, 8 Nov 2026): the user's
// own named groups of films ("Pokémon", "James Bond", "Monty Python"). Each film stays its own
// VideoCollection (its page, poster, place and watched mark); a group only lists them. TV shows
// are never put in one (the user: "TV shows should be their own collections"). Saved in the
// shared videos.json ("groups"), the same for every profile (the user: "They should be shared").
//
// In code it's a VideoGroup, so VideoCollection (one show or film) keeps its name; on screen it's
// a "collection".

/// How a group's films are listed.
enum VideoGroupOrder {
  /// Oldest first (films with no year last), then by name.
  year('By year'),

  /// A–Z.
  name('By name'),

  /// The order the user put them in.
  own('Your own order');

  const VideoGroupOrder(this.label);
  final String label;
}

class VideoGroup {
  VideoGroup({
    required this.id,
    required this.name,
    List<String>? keys,
    this.description,
    this.order = VideoGroupOrder.year,
    this.poster,
    int? createdMs,
    int? changedMs,
    Map<String, String>? links,
  })  : keys = keys ?? [],
        createdMs = createdMs ?? DateTime.now().millisecondsSinceEpoch,
        links = links ?? {} {
    this.changedMs = changedMs ?? this.createdMs;
  }

  /// When it was last changed (made, renamed, a film added…), on whichever device: sharing
  /// (9 Nov 2026, docs/ai-context/09_COLLECTION_SHARING_PLAN.md) keeps the newest.
  late int changedMs;

  /// The Jellyfin collection it's shared as, on each server (server key → the collection's id
  /// there).
  final Map<String, String> links;

  /// Never changes ("g" + a number); the group's poster and favourite are kept under it.
  final String id;
  String name;

  /// Its films, as VideoCollection keys (lower-case names), in the user's own order. A film that
  /// can't be found right now (folder offline, server off) is kept for when it's back.
  final List<String> keys;
  String? description;
  VideoGroupOrder order;

  /// A picture the user chose for it (a file name in the chosen-pictures folder); null: its
  /// films' posters, tiled.
  String? poster;
  final int createdMs;

  /// The key its poster and favourite are kept under (beside the films' keys, which are names).
  String get key => 'group:$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'keys': keys,
        if (description != null) 'description': description,
        if (order != VideoGroupOrder.year) 'order': order.name,
        if (poster != null) 'poster': poster,
        'createdMs': createdMs,
        if (changedMs != createdMs) 'changedMs': changedMs,
        if (links.isNotEmpty) 'links': links,
      };

  /// Null when [j] isn't a usable group.
  static VideoGroup? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], keys = j['keys'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) return null;
    final d = j['description'];
    return VideoGroup(
      id: id,
      name: name.trim(),
      keys: <String>{
        if (keys is List)
          for (final k in keys)
            if (k is String && k.isNotEmpty) k,
      }.toList(),
      description: d is String && d.trim().isNotEmpty ? d.trim() : null,
      order: VideoGroupOrder.values.where((o) => o.name == j['order']).firstOrNull ?? VideoGroupOrder.year,
      // Only a plain file name: a picture can't point outside the pictures folder.
      poster: j['poster'] is String && RegExp(r'^[\w.-]+$').hasMatch(j['poster'] as String) && !(j['poster'] as String).startsWith('.')
          ? j['poster'] as String
          : null,
      createdMs: j['createdMs'] is int ? j['createdMs'] as int : null,
      changedMs: j['changedMs'] is int ? j['changedMs'] as int : null,
      links: {
        if (j['links'] is Map)
          for (final e in (j['links'] as Map).entries)
            if (e.key is String && e.value is String && (e.value as String).isNotEmpty) e.key as String: e.value as String,
      },
    );
  }
}
