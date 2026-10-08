// Quick links in the sidebar (0.1.64): the pieces the sidebar, the pages and the menus share.
//
// * [QuickLinkButton]: the bookmark button on an album's, artist's, audiobook's or collection's
//   page ("Add to sidebar" / "In the sidebar").
// * [quickLinkMenuText] / [quickLinkMenuIcon]: the "Add to sidebar" / "Remove from sidebar" item
//   in the right-click menus (albums, audiobooks, collections, videos).
// * [openQuickLink]: what clicking a link in the sidebar does; something that's no longer in the
//   library says so, with a button to take the link off.
// The links themselves are LibraryModel.quickLinks (models/quick_link.dart).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/quick_link.dart';
import '../../state/library_model.dart';
import '../../state/playlists_model.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import 'playlist_art.dart' show playlistIconOf;

export '../../models/quick_link.dart';

/// The icon a link shows in the sidebar.
IconData quickLinkIcon(QuickLinkKind kind) => switch (kind) {
      QuickLinkKind.album => Icons.album,
      QuickLinkKind.artist => Icons.person,
      QuickLinkKind.book => Icons.menu_book,
      QuickLinkKind.collection => Icons.video_library_outlined,
      QuickLinkKind.video => Icons.smart_display_outlined,
      QuickLinkKind.playlist => Icons.queue_music,
      QuickLinkKind.series => Icons.collections_bookmark_outlined,
    };

/// The icon a link shows in the sidebar: a playlist's own icon (0.1.67), else its kind's.
IconData quickLinkIconFor(BuildContext context, QuickLink link) {
  if (link.kind == QuickLinkKind.playlist) {
    final pl = Provider.of<PlaylistsModel?>(context, listen: false)?.byId(link.id);
    if (pl != null) return playlistIconOf(pl);
  }
  return quickLinkIcon(link.kind);
}

/// The name a link shows: a playlist's current name (it can be renamed), otherwise the name it
/// had when it was added.
String quickLinkLabel(BuildContext context, QuickLink link) => link.kind == QuickLinkKind.playlist
    ? Provider.of<PlaylistsModel?>(context, listen: false)?.byId(link.id)?.name ?? link.label
    : link.label;

String quickLinkMenuText(bool inSidebar) => inSidebar ? 'Remove from sidebar' : 'Add to sidebar';
IconData quickLinkMenuIcon(bool inSidebar) => inSidebar ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined;

/// Whether the item a link points at is still in the library.
bool quickLinkAvailable(BuildContext context, QuickLink link) {
  final lib = context.read<LibraryModel>();
  final videos = Provider.of<VideoLibraryModel?>(context, listen: false);
  return switch (link.kind) {
    QuickLinkKind.album => lib.albumByKey(link.id) != null,
    QuickLinkKind.artist => lib.artistByName(link.id) != null,
    QuickLinkKind.book => lib.bookById(link.id) != null,
    QuickLinkKind.collection => videos?.collectionNamed(link.id) != null,
    QuickLinkKind.video => videos?.byId(link.id) != null,
    QuickLinkKind.playlist => Provider.of<PlaylistsModel?>(context, listen: false)?.byId(link.id) != null,
    QuickLinkKind.series => lib.books.any((b) => b.series == link.id),
  };
}

/// Opens what [link] points at (a click in the sidebar).
void openQuickLink(BuildContext context, QuickLink link) {
  final lib = context.read<LibraryModel>();
  final nav = context.read<AppNav>();
  final videos = Provider.of<VideoLibraryModel?>(context, listen: false);
  switch (link.kind) {
    case QuickLinkKind.album:
      final a = lib.albumByKey(link.id);
      if (a != null) {
        nav.selectTab(AppNav.libraryTab);
        nav.openAlbum(a);
        return;
      }
    case QuickLinkKind.artist:
      if (lib.artistByName(link.id) != null) {
        nav.selectTab(AppNav.libraryTab);
        nav.openArtist(link.id);
        return;
      }
    case QuickLinkKind.book:
      final b = lib.bookById(link.id);
      if (b != null) {
        nav.openBook(b);
        return;
      }
    case QuickLinkKind.collection:
      if (videos?.collectionNamed(link.id) != null) {
        nav.openVideoCollection(link.id);
        return;
      }
    case QuickLinkKind.video:
      final v = videos?.byId(link.id);
      if (v != null) {
        nav.openVideo(v);
        return;
      }
    case QuickLinkKind.playlist:
      final p = Provider.of<PlaylistsModel?>(context, listen: false)?.byId(link.id);
      if (p != null) {
        nav.selectTab(AppNav.libraryTab);
        nav.openPlaylist(p);
        return;
      }
    case QuickLinkKind.series:
      if (lib.books.any((b) => b.series == link.id)) {
        nav.openSeries(link.id);
        return;
      }
  }
  // Gone (deleted, renamed, or its folder isn't scanned any more).
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text('"${link.label}" isn\'t in your library any more.'),
    action: SnackBarAction(label: 'Remove link', onPressed: () => lib.removeQuickLink(link.kind, link.id)),
  ));
}

/// The bookmark button on a page: adds it to the sidebar, or takes it off again.
class QuickLinkButton extends StatelessWidget {
  final QuickLink link;
  const QuickLinkButton({super.key, required this.link});

  @override
  Widget build(BuildContext context) {
    final on = context.select<LibraryModel, bool>((l) => l.isQuickLink(link.kind, link.id));
    return IconButton(
      key: const ValueKey('quick-link-button'),
      tooltip: on ? 'In the sidebar (click to remove)' : 'Add to sidebar',
      isSelected: on,
      icon: Icon(on ? Icons.bookmark_added : Icons.bookmark_add_outlined,
          color: on ? Theme.of(context).colorScheme.primary : null),
      onPressed: () => context.read<LibraryModel>().toggleQuickLink(link),
    );
  }
}

/// Right-click (or long-press) on [child]: a small menu with "Add to sidebar" or "Remove from
/// sidebar" for [link]. Used on the sidebar's links and playlists and the Library's playlists.
class QuickLinkMenu extends StatelessWidget {
  const QuickLinkMenu({super.key, required this.link, required this.child});
  final QuickLink link;
  final Widget child;

  Future<void> _menu(BuildContext context, Offset at) async {
    final lib = context.read<LibraryModel>();
    final on = lib.isQuickLink(link.kind, link.id);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(
          key: const ValueKey('quick-link-menu-item'),
          value: true,
          child: Row(children: [
            Icon(quickLinkMenuIcon(on), size: 20),
            const SizedBox(width: 12),
            Flexible(child: Text(quickLinkMenuText(on))),
          ]),
        ),
      ],
    );
    if (choice == true) await lib.toggleQuickLink(link);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
        onLongPressStart: (d) => _menu(context, d.globalPosition),
        child: child,
      );
}
