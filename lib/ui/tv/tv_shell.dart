// The TV interface's frame (0.2.0, step 1 of the TV interface; mockups "HomeTunes TV Interface",
// agreed 23 Oct). On a TV (Settings › Appearance › TV mode) the app opens in this instead of
// Shell: the rail on the left (tv_rail.dart) and the page beside it, with the hint bubble.
// The pages are the same six tabs and their page stacks as Shell's (AppNav's navigators), so
// everything opens and works as before; steps 2–7 replace each page with its TV version.
// Step 2 (23 Oct): Home, Music, Audiobooks and Videos start on their TV screens (tv_home.dart,
// tv_music.dart, tv_books.dart, tv_videos.dart); the pages they open are still the old ones
// until step 3. Search and Settings come in steps 6 and 7. The page showing sets the hint
// bubble's words (TvHintBoard).
//
// Back, in order: back a page in this tab; from a tab's first page, onto the rail; from the
// rail, to Home; on Home, the app goes to the background (music keeps playing), as in Shell.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/now_watching.dart';
import '../../state/player_model.dart';
import '../../state/settings/settings_groups.dart' as prefs;
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/player_controls.dart' show openNowPlaying;
import 'tv_books.dart';
import 'tv_browse.dart';
import 'tv_focus.dart';
import 'tv_home.dart';
import 'tv_music.dart';
import 'tv_rail.dart';
import 'tv_search.dart';
import 'tv_settings.dart';
import 'tv_videos.dart';
import 'tv_widgets.dart';

/// The app's first screen: the TV frame in TV mode, else the usual Shell. Switching TV mode in
/// Settings swaps them straight away (each tab keeps its pages: the navigators are AppNav's).
class AppHome extends StatelessWidget {
  const AppHome({super.key});

  @override
  Widget build(BuildContext context) {
    final tv = context.select<prefs.AppearanceSettings, bool>((s) => s.tvLayout);
    // Pages opened from here on are the TV ones in TV mode (step 3).
    Provider.of<AppNav?>(context, listen: false)?.tv = tv;
    return tv ? const TvShell() : const Shell();
  }
}

/// The rail's places, in order, and the AppNav tab each one shows.
const tvRailPlaces = <(TvRailItem, int)>[
  (TvRailItem('Home', Icons.home_outlined), 0),
  (TvRailItem('Music', Icons.library_music_outlined), AppNav.libraryTab),
  (TvRailItem('Audiobooks', Icons.menu_book_outlined), AppNav.booksTab),
  (TvRailItem('Videos', Icons.video_library_outlined), AppNav.videosTab),
  (TvRailItem('Search', Icons.search), 1),
  (TvRailItem('Settings', Icons.tune), AppNav.settingsTab),
];

class TvShell extends StatefulWidget {
  const TvShell({super.key});

  @override
  State<TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<TvShell> {
  final _rail = GlobalKey<TvRailState>();
  // Holds the page, so picking a place on the rail can move the remote into it.
  final _page = FocusNode(debugLabel: 'tv page', skipTraversal: true, canRequestFocus: false);
  bool _railOpen = false;
  final _hints = TvHintBoard();

  @override
  void dispose() {
    _hints.dispose();
    _page.dispose();
    super.dispose();
  }

  void _select(AppNav nav, int place) {
    nav.selectTab(tvRailPlaces[place].$2);
    // Into the page just picked, once it's drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) tvFocusFirstIn(_page);
    });
  }

  Future<void> _back(AppNav nav) async {
    final pages = nav.current;
    if (pages != null && pages.canPop()) {
      pages.pop();
    } else if (!(_rail.currentState?.isOpen ?? false)) {
      _rail.currentState?.focusSelected();
    } else if (nav.tab != 0) {
      nav.selectTab(0);
    } else {
      await sendAppToBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<AppNav>();
    final player = context.watch<PlayerModel>();
    final watching = context.watch<NowWatching?>();
    final track = player.current;
    final video = (watching?.inFront ?? false) ? watching : null;
    final place = tvRailPlaces.indexWhere((p) => p.$2 == nav.tab);

    final tabs = IndexedStack(
      index: nav.tab,
      children: [
        TabPages(navKey: nav.keys[0], root: const TvHomeScreen()),
        TabPages(navKey: nav.keys[1], root: const TvSearchScreen()),
        TabPages(navKey: nav.keys[AppNav.libraryTab], root: const TvMusicScreen()),
        TabPages(navKey: nav.keys[AppNav.booksTab], root: const TvBooksScreen()),
        TabPages(navKey: nav.keys[AppNav.videosTab], root: const TvVideosScreen()),
        TabPages(navKey: nav.keys[AppNav.settingsTab], root: const TvSettingsScreen()),
      ],
    );

    return ChangeNotifierProvider.value(
     value: _hints,
     child: Scaffold(
      backgroundColor: AppColors.bg,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back(nav);
        },
        child: Stack(children: [
          Positioned.fill(
            left: TvRail.width,
            child: TvRegion(child: Focus(focusNode: _page, child: tabs)),
          ),
          // The page dims while the rail is open over it.
          if (_railOpen)
            const Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Color(0x9E050608)))),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: TvRegion(
              child: TvRail(
                key: _rail,
                items: [for (final p in tvRailPlaces) p.$1],
                selected: place < 0 ? 0 : place,
                onSelect: (i) => _select(nav, i),
                onOpenChange: (open) => setState(() => _railOpen = open),
                nowPlaying: video != null
                    ? const ColoredBox(color: Color(0xFF24272E), child: Icon(Icons.movie_outlined, size: 20))
                    : (track == null ? null : Artwork(track: track, size: 36)),
                nowPlayingLabel: video != null ? video.video?.title : (track == null ? null : '${track.title} · ${track.artist}'),
                onNowPlaying: () {
                  if (video != null) {
                    video.onOpen?.call();
                  } else {
                    openNowPlaying(context);
                  }
                },
              ),
            ),
          ),
          Positioned(
            right: 24,
            bottom: 16,
            child: ListenableBuilder(
              listenable: _hints,
              builder: (context, _) => TvHints(_hints.forTab(nav.tab) ?? TvHints.browsing),
            ),
          ),
        ]),
      ),
     ),
    );
  }
}
