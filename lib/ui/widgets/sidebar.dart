// The computer's left-hand sidebar (moved out of shell.dart on 1 Oct, user's request: "the left
// hand side bar can be scaled and hidden away by dragging or a click of a button").
//
// * Drag its right edge to make it wider or narrower (180–420 px; remembered in settings.json).
// * Drag it narrower than that, click the fold button at the top, or double-click the edge, and it
//   folds down to a strip of icons (with tooltips); the same button or a drag opens it again.
// * Under the tabs: Liked Songs, Favourite audiobooks and Favourite videos, then the playlists.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';
import '../../state/playlists_model.dart';
import '../nav.dart';
import '../theme.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  /// Width when folded down to its icons.
  static const foldedWidth = 64.0;

  /// A drag that ends narrower than this folds it.
  static const foldBelow = 130.0;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  /// The width while the edge is being dragged (null otherwise).
  double? _drag;
  double _pressedX = 0, _startWidth = 0;

  void _toggle(LibraryModel lib) => lib.setSidebar(folded: !lib.sidebarFolded);

  @override
  Widget build(BuildContext context) {
    final lib = context.read<LibraryModel>();
    final (saved, folded) = context.select<LibraryModel, (double, bool)>((l) => (l.sidebarWidth, l.sidebarFolded));
    final width = _drag ?? (folded ? Sidebar.foldedWidth : saved);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // Material (not a plain coloured box) so the list's hover / tap highlights can paint on it.
      Material(
        color: AppColors.bg,
        child: AnimatedContainer(
          key: const ValueKey('sidebar'),
          duration: _drag == null ? const Duration(milliseconds: 160) : Duration.zero,
          curve: Curves.easeOut,
          width: width,
          child: ClipRect(
            child: LayoutBuilder(
              // Icons only below the smallest open width (also while it animates between the two).
              builder: (context, box) => _SidebarContent(
                iconsOnly: box.maxWidth < LibraryModel.sidebarMinWidth - 10,
                onToggle: () => _toggle(lib),
              ),
            ),
          ),
        ),
      ),
      // The edge: drag to resize, double-click to fold or open.
      MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          key: const ValueKey('sidebar-edge'),
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () => _toggle(lib),
          // Measured from where the mouse was pressed, so the edge stays under it.
          onHorizontalDragDown: (d) {
            _pressedX = d.globalPosition.dx;
            _startWidth = width;
          },
          onHorizontalDragStart: (_) => setState(() => _drag = _startWidth),
          onHorizontalDragUpdate: (d) => setState(
            () => _drag = (_startWidth + d.globalPosition.dx - _pressedX)
                .clamp(Sidebar.foldedWidth, LibraryModel.sidebarMaxWidth),
          ),
          onHorizontalDragEnd: (_) {
            final w = _drag ?? width;
            setState(() => _drag = null);
            if (w < Sidebar.foldBelow) {
              lib.setSidebar(folded: true);
            } else {
              lib.setSidebar(width: w, folded: false);
            }
          },
          child: SizedBox(
            width: 7,
            child: Center(child: VerticalDivider(width: 1, color: AppColors.divider)),
          ),
        ),
      ),
    ]);
  }
}

class _SidebarContent extends StatelessWidget {
  const _SidebarContent({required this.iconsOnly, required this.onToggle});
  final bool iconsOnly;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<AppNav>();
    final pl = context.watch<PlaylistsModel>();
    final accent = Theme.of(context).colorScheme.primary;

    // One entry: a list row when open, an icon with a tooltip when folded.
    Widget entry({
      required String key,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool selected = false,
      Color? iconColour,
      bool dense = false,
    }) {
      final colour = iconColour ?? (selected ? AppColors.text : AppColors.textDim);
      if (iconsOnly) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Center(
            child: IconButton(
              key: ValueKey(key),
              tooltip: label,
              isSelected: selected,
              style: IconButton.styleFrom(backgroundColor: selected ? AppColors.faded(0.10) : null),
              icon: Icon(icon, color: colour),
              onPressed: onTap,
            ),
          ),
        );
      }
      return ListTile(
        key: ValueKey(key),
        dense: dense,
        leading: Icon(icon, color: colour),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dense
              ? null
              : TextStyle(fontWeight: FontWeight.w600, color: selected ? AppColors.text : AppColors.textDim),
        ),
        onTap: onTap,
      );
    }

    Widget tab(int i, IconData icon, String label) =>
        entry(key: 'sidebar-tab:$i', icon: icon, label: label, selected: nav.tab == i, onTap: () => nav.selectTab(i));

    final foldButton = IconButton(
      key: const ValueKey('sidebar-fold'),
      tooltip: iconsOnly ? 'Open the sidebar' : 'Fold the sidebar',
      icon: Icon(iconsOnly ? Icons.menu : Icons.menu_open, color: AppColors.textDim),
      onPressed: onToggle,
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (iconsOnly)
        Padding(padding: const EdgeInsets.fromLTRB(0, 14, 0, 6), child: Center(child: foldButton))
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 6),
          child: Row(children: [
            Icon(Icons.graphic_eq, color: accent),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'HomeTunes',
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            foldButton,
          ]),
        ),
      tab(0, Icons.home, 'Home'),
      tab(1, Icons.search, 'Search'),
      tab(AppNav.libraryTab, Icons.library_music, 'Your Library'),
      tab(AppNav.booksTab, Icons.menu_book, 'Audiobooks'),
      tab(AppNav.videosTab, Icons.video_library, 'Videos'),
      tab(AppNav.settingsTab, Icons.settings, 'Settings'),
      const Divider(height: 24),
      // Liked Songs and the playlists open on the Library tab; the favourites on their own tabs.
      entry(
        key: 'sidebar-liked',
        icon: Icons.favorite,
        iconColour: accent,
        label: 'Liked Songs',
        dense: true,
        onTap: () {
          nav.selectTab(AppNav.libraryTab);
          nav.openLiked();
        },
      ),
      entry(
        key: 'sidebar-favourite-books',
        icon: Icons.auto_stories,
        iconColour: accent,
        label: 'Favourite audiobooks',
        dense: true,
        onTap: () => nav.openView(AppNav.booksTab, AppNav.favouriteBooksView),
      ),
      entry(
        key: 'sidebar-favourite-videos',
        icon: Icons.movie,
        iconColour: accent,
        label: 'Favourite videos',
        dense: true,
        onTap: () => nav.openView(AppNav.videosTab, AppNav.favouriteVideosView),
      ),
      if (!iconsOnly)
        Expanded(
          child: ListView(children: [
            for (final p in pl.playlists)
              ListTile(
                dense: true,
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  nav.selectTab(AppNav.libraryTab);
                  nav.openPlaylist(p);
                },
              ),
          ]),
        ),
    ]);
  }
}
