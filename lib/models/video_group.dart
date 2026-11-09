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
    int? createdMs,
  })  : keys = keys ?? [],
        createdMs = createdMs ?? DateTime.now().millisecondsSinceEpoch;

  /// Never changes ("g" + a number); the group's poster and favourite are kept under it.
  final String id;
  String name;

  /// Its films, as VideoCollection keys (lower-case names), in the user's own order. A film that
  /// can't be found right now (folder offline, server off) is kept for when it's back.
  final List<String> keys;
  String? description;
  VideoGroupOrder order;
  final int createdMs;

  /// The key its poster and favourite are kept under (beside the films' keys, which are names).
  String get key => 'group:$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'keys': keys,
        if (description != null) 'description': description,
        if (order != VideoGroupOrder.year) 'order': order.name,
        'createdMs': createdMs,
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
      createdMs: j['createdMs'] is int ? j['createdMs'] as int : null,
    );
  }
}
