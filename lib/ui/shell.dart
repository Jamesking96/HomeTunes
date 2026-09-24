import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/library_model.dart';
import '../models/track.dart';
import '../state/player_model.dart';
import '../state/playlists_model.dart';
import '../state/selection_model.dart';
import 'nav.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/edit_details.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'theme.dart';
import 'widgets/player_controls.dart';
import 'widgets/track_tile.dart';

/// Wide screens get a sidebar + bottom player bar; phones get a mini player
/// above a bottom navigation bar.
class Shell extends StatelessWidget {
  const Shell({super.key});

  static const wideBreakpoint = 840.0;

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<AppNav>();
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;

    final tabs = IndexedStack(
      index: nav.tab,
      children: [
        _TabNavigator(navKey: nav.keys[0], root: const HomeScreen()),
        _TabNavigator(navKey: nav.keys[1], root: const SearchScreen()),
        _TabNavigator(navKey: nav.keys[2], root: const LibraryScreen()),
        _TabNavigator(navKey: nav.keys[3], root: const SettingsScreen()),
      ],
    );

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

    if (wide) {
      return Scaffold(
        body: Column(children: [
          Expanded(
            child: Row(children: [
              const _Sidebar(),
              const VerticalDivider(width: 1, color: Colors.black),
              Expanded(child: body),
            ]),
          ),
          const _StatusStrip(),
          const _SelectionBar(),
          const DesktopPlayerBar(),
        ]),
      );
    }

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
    final text = lib.status ?? lib.error;
    if (text == null) return const SizedBox.shrink();
    final isError = lib.status == null;
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

    Widget item(int i, IconData icon, String label) => ListTile(
          leading: Icon(icon, color: nav.tab == i ? Colors.white : null),
          title: Text(label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: nav.tab == i ? Colors.white : AppColors.textDim,
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
        item(2, Icons.library_music, 'Your Library'),
        item(AppNav.settingsTab, Icons.settings, 'Settings'),
        const Divider(height: 24),
        ListTile(
          dense: true,
          leading: Icon(Icons.favorite, color: accent),
          title: const Text('Liked Songs'),
          onTap: () {
            nav.selectTab(2);
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
                  nav.selectTab(2);
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
    final lib = context.read<LibraryModel>();
    final accent = Theme.of(context).colorScheme.primary;
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
              tooltip: 'Add to queue',
              icon: const Icon(Icons.queue_music),
              onPressed: () async {
                final player = context.read<PlayerModel>();
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
