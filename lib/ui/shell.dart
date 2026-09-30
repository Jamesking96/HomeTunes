// The app's outer frame: everything that stays on screen around the pages.
//
// main.dart shows [Shell] as the MaterialApp's home. It lays out the six tabs (each with its
// own Navigator from AppNav), plus the status strip (scan progress / errors), the multi-select
// bar and the player. Wide windows (desktop) get a left sidebar and a full player bar along the
// bottom; phones get a mini player above a bottom navigation bar. It also decides what the
// Android Back button does.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/library_model.dart';
import '../models/book.dart';
import '../models/track.dart';
import '../state/player_model.dart';
import '../state/playlists_model.dart';
import '../state/selection_model.dart';
import 'nav.dart';
import 'screens/books_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/edit_book.dart';
import 'screens/edit_details.dart';
import 'screens/search_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/videos_screen.dart';
import 'theme.dart';
import 'widgets/player_controls.dart';
import 'widgets/quick_actions.dart';
import 'widgets/track_tile.dart';

/// Wide screens get a sidebar + bottom player bar; phones get a mini player
/// above a bottom navigation bar.
class Shell extends StatelessWidget {
  const Shell({super.key});

  /// Window width (in logical pixels) at which the desktop layout takes over.
  static const wideBreakpoint = 840.0;

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<AppNav>();
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;

    // All six tabs stay alive in an IndexedStack (only the chosen one is shown), so each tab
    // keeps its scroll position and open pages while you're on another tab.
    final tabs = IndexedStack(
      index: nav.tab,
      children: [
        _TabNavigator(navKey: nav.keys[0], root: const HomeScreen()),
        _TabNavigator(navKey: nav.keys[1], root: const SearchScreen()),
        _TabNavigator(navKey: nav.keys[2], root: const LibraryScreen()),
        _TabNavigator(navKey: nav.keys[AppNav.booksTab], root: const BooksScreen()),
        _TabNavigator(navKey: nav.keys[AppNav.videosTab], root: const VideosScreen()),
        _TabNavigator(navKey: nav.keys[AppNav.settingsTab], root: const SettingsScreen()),
      ],
    );

    // The Back button / gesture. We never let the system close the app; instead, in order:
    // leave select mode, go back a page in this tab, jump to the Home tab, then (on Home)
    // hide the app so music keeps playing.
    final body = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final selection = context.read<SelectionModel>();
        if (selection.active) {
          selection.clear(); // Back leaves select mode first
          return;
        }
        final n = nav.current;
        if (n != null && n.canPop()) {
          n.pop();
        } else if (nav.tab != 0) {
          nav.selectTab(0);
        } else {
          await _sendToBackground();
        }
      },
      child: tabs,
    );

    // Desktop layout: sidebar | pages, with the strips and the player bar underneath.
    if (wide) {
      return Scaffold(
        body: Column(children: [
          Expanded(
            child: Row(children: [
              const _Sidebar(),
              VerticalDivider(width: 1, color: AppColors.divider),
              Expanded(child: body),
            ]),
          ),
          const _StatusStrip(),
          const _SelectionBar(),
          const DesktopPlayerBar(),
        ]),
      );
    }

    // Phone layout: pages fill the screen; the strips, mini player and tab bar stack at the
    // bottom. (The tab order here must match the tab numbers in AppNav.)
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const _StatusStrip(),
        const _SelectionBar(),
        const MiniPlayer(),
        NavigationBar(
          selectedIndex: nav.tab,
          onDestinationSelected: nav.selectTab,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(
                icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
            NavigationDestination(
                icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Books'),
            NavigationDestination(
                icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library), label: 'Videos'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ]),
    );
  }
}

/// Android: Back on the Home screen hides the app like the Home button does,
/// so the music keeps playing (closing the app would stop it).
const _appChannel = MethodChannel('hometunes/app');

// Asks the Android side (MainActivity.kt) to move the app to the background. Does nothing on
// Windows, where there's no Back button to handle.
Future<void> _sendToBackground() async {
  if (!Platform.isAndroid) return;
  try {
    await _appChannel.invokeMethod<void>('moveToBackground');
  } on PlatformException catch (e) {
    debugPrint('HomeTunes: could not move to background: $e');
  } on MissingPluginException {
    // Older Android shell without the hook: do nothing, as before.
  }
}

/// One tab's own page stack. It starts with [root] (e.g. HomeScreen) and AppNav pushes album,
/// artist, book pages etc. on top using [navKey].
class _TabNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navKey;
  final Widget root;
  const _TabNavigator({required this.navKey, required this.root});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navKey,
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => root),
    );
  }
}

/// Thin line showing scan / sync progress or an error.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip();

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    // Progress text changes many times a second during a scan: only this strip
    // redraws for it.
    return ValueListenableBuilder<String?>(
      valueListenable: lib.statusText,
      builder: (context, status, _) => _strip(lib, status),
    );
  }

  Widget _strip(LibraryModel lib, String? status) {
    // Progress wins over an old error, and an error over a message about damaged data files;
    // with none of them, the strip takes no space at all.
    final text = status ?? lib.error ?? lib.dataProblem;
    if (text == null) return const SizedBox.shrink();
    final isError = status == null;
    return Material(
      color: isError ? const Color(0xFF5A1F1F) : AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          if (!isError)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          else
            const Icon(Icons.error_outline, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
          if (isError)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              onPressed: lib.clearError,
            ),
        ]),
      ),
    );
  }
}

/// Desktop sidebar: nav items + playlists.
class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<AppNav>();
    final pl = context.watch<PlaylistsModel>();
    final accent = Theme.of(context).colorScheme.primary;

    // One sidebar entry; the selected tab is shown in white, the rest dimmed.
    Widget item(int i, IconData icon, String label) => ListTile(
          leading: Icon(icon, color: nav.tab == i ? AppColors.text : null),
          title: Text(label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: nav.tab == i ? AppColors.text : AppColors.textDim,
              )),
          onTap: () => nav.selectTab(i),
        );

    // Material (not a plain coloured box) so the ListTiles' hover/tap
    // highlights can paint on it.
    return Material(
      color: AppColors.bg,
      child: SizedBox(
      width: 250,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(children: [
            Icon(Icons.graphic_eq, color: accent),
            const SizedBox(width: 8),
            const Text('HomeTunes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
        ),
        item(0, Icons.home, 'Home'),
        item(1, Icons.search, 'Search'),
        item(AppNav.libraryTab, Icons.library_music, 'Your Library'),
        item(AppNav.booksTab, Icons.menu_book, 'Audiobooks'),
        item(AppNav.videosTab, Icons.video_library, 'Videos'),
        item(AppNav.settingsTab, Icons.settings, 'Settings'),
        const Divider(height: 24),
        // Liked Songs and the playlists open on the Library tab.
        ListTile(
          dense: true,
          leading: Icon(Icons.favorite, color: accent),
          title: const Text('Liked Songs'),
          onTap: () {
            nav.selectTab(AppNav.libraryTab);
            nav.openLiked();
          },
        ),
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
      ]),
      ),
    );
  }
}

/// Shown while songs are ticked: edit them together, add to a playlist, queue them.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar();

  @override
  Widget build(BuildContext context) {
    final sel = context.watch<SelectionModel>();
    if (!sel.active) return const SizedBox.shrink();
    if (sel.kind != SelectKind.songs) return _GroupSelectionBar(sel: sel);
    final lib = context.read<LibraryModel>();
    final accent = Theme.of(context).colorScheme.primary;
    // The ticked songs as Track objects (ids that no longer exist are skipped). Worked out
    // fresh at each button press so it's never stale.
    List<Track> picked() => [for (final id in sel.ids) lib.byId(id)].whereType<Track>().toList();

    return Material(
      color: accent.withValues(alpha: 0.18),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(children: [
            IconButton(tooltip: 'Clear selection', icon: const Icon(Icons.close), onPressed: sel.clear),
            Expanded(
              child: Text('${sel.count} selected', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: 'Edit details',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final saved = await showEditDetails(context, picked());
                if (saved) sel.clear();
              },
            ),
            IconButton(
              tooltip: 'Add to playlist',
              icon: const Icon(Icons.playlist_add),
              onPressed: () async {
                await showAddToPlaylist(context, picked());
                sel.clear();
              },
            ),
            IconButton(
              tooltip: 'Move to Books',
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: () async {
                final ids = [for (final t in picked()) t.id];
                await lib.setIsBook(ids, true);
                sel.clear();
                // Undo sets the override back to null ("decide automatically"), not to false.
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Moved ${ids.length} to Books'),
                    action: SnackBarAction(label: 'Undo', onPressed: () => lib.setIsBook(ids, null)),
                  ));
                }
              },
            ),
            IconButton(
              tooltip: 'Add to queue',
              icon: const Icon(Icons.queue_music),
              onPressed: () async {
                final player = context.read<PlayerModel>();
                // One at a time, in the order they appear in the selection.
                for (final t in picked()) {
                  await player.addToQueue(t);
                }
                sel.clear();
              },
            ),
          ]),
        ),
      ),
    );
  }
}

/// Shown while albums or audiobooks are ticked: tick them all, or edit them together.
class _GroupSelectionBar extends StatelessWidget {
  final SelectionModel sel;
  const _GroupSelectionBar({required this.sel});

  Future<void> _edit(BuildContext context) async {
    final lib = context.read<LibraryModel>();
    bool saved;
    if (sel.kind == SelectKind.albums) {
      final albums = [for (final k in sel.ids) lib.albumByKey(k)].whereType<Album>().toList();
      if (albums.isEmpty) return;
      saved = await showEditDetails(
        context,
        [for (final a in albums) ...a.tracks],
        album: albums.length == 1,
        albumCount: albums.length,
      );
    } else {
      final books = [for (final id in sel.ids) lib.bookById(id)].whereType<Book>().toList();
      if (books.isEmpty) return;
      saved = await showEditBooks(context, books);
    }
    if (saved) sel.clear();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final albums = sel.kind == SelectKind.albums;
    final lib = context.read<LibraryModel>();
    final playlists = context.watch<PlaylistsModel>();
    final pickedAlbums = albums ? [for (final k in sel.ids) lib.albumByKey(k)].whereType<Album>().toList() : <Album>[];
    final pickedBooks = albums ? <Book>[] : [for (final id in sel.ids) lib.bookById(id)].whereType<Book>().toList();
    // The heart removes them from favourites only when every one is already a favourite.
    final allFavourite = albums
        ? pickedAlbums.isNotEmpty && pickedAlbums.every(playlists.isFavouriteAlbum)
        : pickedBooks.isNotEmpty && pickedBooks.every(playlists.isFavouriteBook);
    final n = sel.count;
    final noun = albums ? (n == 1 ? 'album' : 'albums') : (n == 1 ? 'book' : 'books');
    return Material(
      color: accent.withValues(alpha: 0.18),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            IconButton(tooltip: 'Clear selection', icon: const Icon(Icons.close), onPressed: sel.clear),
            Expanded(
              child: Text('$n $noun selected',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (sel.canSelectAll) TextButton(onPressed: sel.selectScope, child: const Text('Select all')),
            IconButton(
              key: const ValueKey('favourite-selected'),
              tooltip: allFavourite ? 'Remove from favourites' : 'Add to favourites',
              icon: Icon(allFavourite ? Icons.favorite : Icons.favorite_border, color: allFavourite ? accent : null),
              onPressed: () {
                if (albums) {
                  playlists.setFavouriteAlbums(pickedAlbums, !allFavourite);
                } else {
                  playlists.setFavouriteBooks(pickedBooks, !allFavourite);
                }
                sel.clear();
              },
            ),
            Builder(
              builder: (context) => IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  final box = context.findRenderObject() as RenderBox;
                  final actions = albums ? albumActions(context, pickedAlbums) : bookActions(context, pickedBooks);
                  showQuickActions(context, box.localToGlobal(box.size.center(Offset.zero)), actions);
                },
              ),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              key: const ValueKey('edit-selected'),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text('Edit $noun'),
              onPressed: () => _edit(context),
            ),
          ]),
        ),
      ),
    );
  }
}
