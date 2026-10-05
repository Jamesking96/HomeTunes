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
import '../../state/video_library_model.dart';
import '../nav.dart';

export '../../models/quick_link.dart';

/// The icon a link shows in the sidebar.
IconData quickLinkIcon(QuickLinkKind kind) => switch (kind) {
      QuickLinkKind.album => Icons.album,
      QuickLinkKind.artist => Icons.person,
      QuickLinkKind.book => Icons.menu_book,
      QuickLinkKind.collection => Icons.video_library_outlined,
      QuickLinkKind.video => Icons.smart_display_outlined,
    };

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
