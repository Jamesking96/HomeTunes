// A quick link in the sidebar (0.1.64): a shortcut to an album, artist, audiobook, video
// collection or video, under Liked Songs and the favourites.
//
// The user asked to add and remove more quick links there. They're added from an item's menu
// ("Add to sidebar": right-click or press and hold an album, audiobook, collection or video; the
// button on an artist's page) and removed the same way, or with a right-click on the link in
// the sidebar. They're kept in settings.json (LibraryModel.quickLinks), in the order added.
// [label] is the name when it was added, shown if the item is no longer in the library.

enum QuickLinkKind { album, artist, book, collection, video }

class QuickLink {
  const QuickLink(this.kind, this.id, this.label);

  final QuickLinkKind kind;

  /// An album's key, an artist's or collection's name, a book's or video's id.
  final String id;
  final String label;

  bool sameAs(QuickLinkKind k, String i) => kind == k && id == i;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'id': id, 'label': label};

  /// Null for anything that isn't a usable link (a damaged or unknown entry is skipped).
  static QuickLink? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = QuickLinkKind.values.asNameMap()[j['kind']];
    final id = j['id'], label = j['label'];
    if (kind == null || id is! String || id.isEmpty) return null;
    return QuickLink(kind, id, label is String && label.isNotEmpty ? label : id);
  }

  /// "Album", "Artist"… for tooltips and notices.
  String get kindName => switch (kind) {
        QuickLinkKind.album => 'Album',
        QuickLinkKind.artist => 'Artist',
        QuickLinkKind.book => 'Audiobook',
        QuickLinkKind.collection => 'Collection',
        QuickLinkKind.video => 'Video',
      };
}
