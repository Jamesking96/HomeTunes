// Quick actions for albums and audiobooks, shown in their right-click / press-and-hold menu
// (for one, or for everything selected) and in the selection bar: edit details, change the
// cover (choose a picture, find one online, or go back to the files' own), favourites, and
// Details (where it comes from).
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../models/track.dart';
import '../../models/track_edit.dart';
import '../../state/library_model.dart';
import '../../state/playlists_model.dart';
import '../screens/book_lookup_dialog.dart';
import '../screens/cover_search_dialog.dart';
import '../screens/details_screen.dart';
import '../screens/edit_book.dart';
import '../screens/edit_details.dart';
import 'selectable_title.dart';

/// One item in a quick-actions menu.
class QuickAction {
  final IconData icon;
  final String label;
  final Future<void> Function() run;
  const QuickAction(this.icon, this.label, this.run);
}

/// An icon and a label for a menu item. The label wraps rather than overflowing a narrow menu.
Widget menuRow(IconData icon, String label) => Row(children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Flexible(child: Text(label)),
    ]);

/// Shows [actions] as a menu at [at] (a screen position), with [header] items first.
Future<void> showQuickActions(BuildContext context, Offset at, List<QuickAction> actions,
    {List<PopupMenuEntry<Future<void> Function()>> header = const []}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final run = await showMenu<Future<void> Function()>(
    context: context,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      ...header,
      if (header.isNotEmpty && actions.isNotEmpty) const PopupMenuDivider(),
      for (final a in actions)
        PopupMenuItem(
          value: a.run,
          child: menuRow(a.icon, a.label),
        ),
    ],
  );
  await run?.call();
}

// Asks for a picture, copies it into HomeTunes and gives it to every song in [ids].
Future<void> _chooseCover(BuildContext context, List<String> ids, String what) async {
  final lib = context.read<LibraryModel>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final file = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Choose a cover for $what');
    final path = file?.path;
    if (path == null) return;
    final copy = await lib.importCover(path);
    await lib.editMany(ids, TrackEdit(art: copy));
    messenger?.showSnackBar(SnackBar(content: Text('New cover for $what')));
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t use that picture: $e')));
  }
}

bool _hasOwnCover(LibraryModel lib, Iterable<Track> tracks) =>
    tracks.any((t) => lib.originalById(t.id)?.art != t.art);

String _count(int n, String one, String many) => n == 1 ? one : '$n $many';

/// Quick actions for one or more albums.
List<QuickAction> albumActions(BuildContext context, List<Album> albums) {
  if (albums.isEmpty) return const [];
  final lib = context.read<LibraryModel>();
  final playlists = context.read<PlaylistsModel>();
  final n = albums.length;
  final tracks = [for (final a in albums) ...a.tracks];
  final ids = [for (final t in tracks) t.id];
  final what = _count(n, '"${albums.first.title}"', 'albums');
  final allFavourite = albums.every(playlists.isFavouriteAlbum);
  return [
    QuickAction(Icons.edit_outlined, n == 1 ? 'Edit details…' : 'Edit $n albums…',
        () => showEditDetails(context, tracks, album: n == 1, albumCount: n)),
    QuickAction(Icons.image_outlined, n == 1 ? 'Choose cover…' : 'Choose one cover for all $n…',
        () => _chooseCover(context, ids, what)),
    if (n == 1 && lib.onlineCovers)
      QuickAction(Icons.travel_explore, 'Find cover online…', () async {
        final path = await showCoverSearch(context, artist: albums.first.artist, album: albums.first.title);
        if (path != null) await lib.editMany(ids, TrackEdit(art: path));
      }),
    if (_hasOwnCover(lib, tracks))
      QuickAction(Icons.restore, n == 1 ? 'Use the files\' own cover' : 'Use the files\' own covers',
          () => lib.resetCovers(ids)),
    QuickAction(allFavourite ? Icons.favorite : Icons.favorite_border,
        allFavourite ? 'Remove from favourites' : 'Add to favourites',
        () async => playlists.setFavouriteAlbums(albums, !allFavourite)),
    if (n == 1) QuickAction(Icons.content_copy, 'Copy title', () => copyTitle(context, albums.first.title)),
    QuickAction(Icons.info_outline, 'Details…', () => openDetails(context,
        kind: n == 1 ? 'Album' : '$n albums',
        title: n == 1 ? albums.first.title : albums.map((a) => a.title).join(', '),
        tracks: tracks)),
  ];
}

/// Quick actions for one or more audiobooks.
List<QuickAction> bookActions(BuildContext context, List<Book> books) {
  if (books.isEmpty) return const [];
  final lib = context.read<LibraryModel>();
  final playlists = context.read<PlaylistsModel>();
  final n = books.length;
  final parts = [for (final b in books) ...b.parts];
  final ids = [for (final t in parts) t.id];
  final what = _count(n, '"${books.first.title}"', 'books');
  final allFavourite = books.every(playlists.isFavouriteBook);
  return [
    QuickAction(Icons.edit_outlined, n == 1 ? 'Edit details…' : 'Edit $n books…', () => showEditBooks(context, books)),
    QuickAction(Icons.image_outlined, n == 1 ? 'Choose cover…' : 'Choose one cover for all $n…',
        () => _chooseCover(context, ids, what)),
    if (n == 1 && lib.onlineCovers)
      QuickAction(Icons.travel_explore, 'Find cover online…', () async {
        final path = await showBookCoverSearch(context, title: books.first.title, author: books.first.author);
        if (path != null) await lib.editMany(ids, TrackEdit(art: path));
      }),
    if (_hasOwnCover(lib, parts))
      QuickAction(Icons.restore, n == 1 ? 'Use the files\' own cover' : 'Use the files\' own covers',
          () => lib.resetCovers(ids)),
    QuickAction(allFavourite ? Icons.favorite : Icons.favorite_border,
        allFavourite ? 'Remove from favourites' : 'Add to favourites',
        () async => playlists.setFavouriteBooks(books, !allFavourite)),
    if (n == 1) QuickAction(Icons.content_copy, 'Copy title', () => copyTitle(context, books.first.title)),
    QuickAction(Icons.info_outline, 'Details…', () => openDetails(context,
        kind: n == 1 ? 'Audiobook' : '$n audiobooks',
        title: n == 1 ? books.first.title : books.map((b) => b.title).join(', '),
        tracks: parts,
        book: n == 1 ? books.first : null)),
  ];
}
