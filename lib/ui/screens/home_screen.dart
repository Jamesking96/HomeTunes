// The Home tab: the first page you see (revamped in 0.1.45 to cover music, audiobooks and
// videos). From the top:
//  * a greeting by time of day;
//  * Jump back in: whatever you were last doing, mixed and newest first (videos and audiobooks
//    you're part-way through, the albums, playlists and artists you last played; see
//    widgets/jump_back_in.dart and state/play_history.dart);
//  * quick tiles: Shuffle all, Liked Songs, Favourite audiobooks, Favourite videos and your
//    playlists;
//  * a Music section (recently added, your favourite albums, from your Liked Songs, artists);
//  * an Audiobooks section (recently added, your favourites);
//  * a Videos section (up next in what you're watching, recently added, favourite collections).
// Each section has a heading with "See all", which opens its tab, and only shows when there's
// something in it. With nothing anywhere it shows "Add music" / "Add videos" buttons instead.
//
// It watches the library, playlists, listening, play history and video models, so it refreshes
// as scans finish or you play something. The video model and play history are optional (some
// tests leave them out).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../models/track.dart';
import '../../models/video_item.dart';
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../../state/play_history.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/book_card.dart';
import '../widgets/cards.dart';
import '../widgets/jump_back_in.dart';
import '../widgets/music_access_banner.dart';
import '../widgets/playlist_art.dart';
import 'video_collection_screen.dart' show CollectionCard, collectionCardHeight;
import 'videos_screen.dart' show VideoCard, videoCardHeight;

/// The Home tab page.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// "Good morning / afternoon / evening", based on the device clock.
  static String greeting([DateTime? at]) {
    final h = (at ?? DateTime.now()).hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  static const _videoCardWidth = 220.0;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final pl = context.watch<PlaylistsModel>();
    final listening = context.watch<ListeningModel>();
    final history = Provider.of<PlayHistory?>(context);
    final videos = Provider.of<VideoLibraryModel?>(context);
    final nav = context.read<AppNav>();
    final hasMusic = lib.tracks.isNotEmpty; // music only (books are in lib.books)
    final hasBooks = lib.books.isNotEmpty;
    final hasVideos = videos != null && videos.videos.isNotEmpty;

    // Nothing anywhere yet: one helpful message (or "scanning" while busy).
    if (!hasMusic && !hasBooks && !hasVideos) {
      final busy = lib.busy || (videos?.busy ?? false);
      return Scaffold(
        appBar: AppBar(title: Text(greeting())),
        body: EmptyState(
          icon: Icons.library_music_outlined,
          title: busy ? 'Looking through your folders…' : 'Nothing here yet',
          message: busy
              ? 'Progress is shown at the bottom of the screen.'
              : 'Point HomeTunes at the folders where your music, audiobooks and videos live, or connect a server.',
          action: busy
              ? null
              : Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Add music'),
                      onPressed: () => nav.openSettings('library', setting: 'music-folders'),
                    ),
                    if (videos != null)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.video_library_outlined),
                        label: const Text('Add videos'),
                        onPressed: () => nav.openSettings('library', setting: 'library-video-folders'),
                      ),
                  ],
                ),
        ),
      );
    }

    final jumps = jumpsFrom(lib: lib, listening: listening, playlists: pl, history: history, videos: videos);
    final ratio = bookCoverRatio(context);

    // Music shelves.
    final recentAlbums = lib.albumsByNewest.take(15).toList();
    final favAlbums = lib.albums.where(pl.isFavouriteAlbum).take(15).toList();
    final likedTracks = [for (final id in pl.liked) ?lib.byId(id)];
    final likedAlbums = _albumsOf(likedTracks, lib).take(15).toList();

    // Audiobook shelves: newest first, and favourites.
    final recentBooks = ([...lib.books]..sort((a, b) => b.addedMs.compareTo(a.addedMs))).take(12).toList();
    final favBooks = lib.books.where(pl.isFavouriteBook).take(12).toList();

    // Video shelves.
    final upNext = videos == null ? const <VideoItem>[] : upNextVideos(videos).take(12).toList();
    final recentCollections = videos == null
        ? const <VideoCollection>[]
        : ([...videos.collections]..sort((a, b) => b.addedMs.compareTo(a.addedMs))).take(12).toList();
    final favCollections = videos?.favouriteCollections.take(12).toList() ?? const <VideoCollection>[];
    double collectionsHeight(List<VideoCollection> list) =>
        list.map((c) => collectionCardHeight(_videoCardWidth, videos!.collectionShapeOf(c))).fold(0.0, math.max);

    Widget books(String title, List<Book> list, String key) => Shelf(
      key: ValueKey(key),
      title: title,
      height: bookCardHeight(150, ratio),
      children: [
        for (final b in list) BookCard(book: b, width: 150, scope: [for (final x in list) x.id]),
      ],
    );
    Widget albums(String title, List<Album> list, String key) => Shelf(
      key: ValueKey(key),
      title: title,
      children: [
        for (final a in list) AlbumCard(album: a, width: 170, scope: [for (final x in list) x.key]),
      ],
    );
    Widget collections(String title, List<VideoCollection> list, String key) => Shelf(
      key: ValueKey(key),
      title: title,
      height: collectionsHeight(list),
      children: [
        for (final c in list)
          SizedBox(
            width: _videoCardWidth,
            child: CollectionCard(collection: c, onTap: () => nav.openVideoCollection(c.name)),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(greeting(), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Warns (on Android) when the app doesn't have permission to read music.
          const MusicAccessBanner(),
          if (jumps.isNotEmpty)
            Shelf(
              key: const ValueKey('home-jump-back-in'),
              title: 'Jump back in',
              height: jumpCardHeightFor(context),
              children: [for (final j in jumps) JumpCard(jump: j)],
            ),
          _QuickTiles(
            lib: lib,
            pl: pl,
            hasFavouriteBooks: favBooks.isNotEmpty,
            hasFavouriteVideos: favCollections.isNotEmpty,
          ),

          // ---- Music ----
          if (hasMusic) ...[
            _SectionHeading(
              'Music',
              icon: Icons.library_music_outlined,
              onSeeAll: () => nav.selectTab(AppNav.libraryTab),
            ),
            albums('Recently added', recentAlbums, 'home-recent-albums'),
            if (favAlbums.isNotEmpty) albums('Your favourite albums', favAlbums, 'home-favourite-albums'),
            if (likedAlbums.isNotEmpty) albums('From your Liked Songs', likedAlbums, 'home-liked-albums'),
            Shelf(
              key: const ValueKey('home-artists'),
              title: 'Artists',
              height: 220,
              children: [for (final a in lib.artists.take(20)) ArtistCard(artist: a, width: 160)],
            ),
          ],

          // ---- Audiobooks ----
          if (hasBooks) ...[
            _SectionHeading(
              'Audiobooks',
              icon: Icons.menu_book_outlined,
              onSeeAll: () => nav.selectTab(AppNav.booksTab),
            ),
            books('Recently added', recentBooks, 'home-recent-books'),
            if (favBooks.isNotEmpty) books('Your favourite audiobooks', favBooks, 'home-favourite-books'),
          ],

          // ---- Videos ----
          if (hasVideos) ...[
            _SectionHeading(
              'Videos',
              icon: Icons.video_library_outlined,
              onSeeAll: () => nav.selectTab(AppNav.videosTab),
            ),
            if (upNext.isNotEmpty)
              Shelf(
                key: const ValueKey('home-up-next'),
                title: 'Up next',
                height: upNext.map((v) => videoCardHeight(_videoCardWidth, videos.shapeOf(v))).fold(0.0, math.max),
                children: [
                  for (final v in upNext)
                    SizedBox(
                      width: _videoCardWidth,
                      child: VideoCard(video: v),
                    ),
                ],
              ),
            collections('Recently added', recentCollections, 'home-recent-collections'),
            if (favCollections.isNotEmpty)
              collections('Your favourite collections', favCollections, 'home-favourite-collections'),
          ],
        ],
      ),
    );
  }

  /// The albums that [tracks] belong to, in order, each listed once ("From your Liked Songs").
  static List<Album> _albumsOf(List<Track> tracks, LibraryModel lib) {
    final seen = <String>{};
    final out = <Album>[];
    for (final t in tracks) {
      if (seen.add(t.albumKey)) {
        final a = lib.albumByKey(t.albumKey);
        if (a != null) out.add(a);
      }
    }
    return out;
  }
}

/// The next episode to watch in each collection you've been watching, most recently watched
/// collection first. Collections with an episode part-watched are left out (that one is in Jump
/// back in already), and so are ones you've finished.
List<VideoItem> upNextVideos(VideoLibraryModel model) {
  final watched = [
    for (final c in model.collections)
      if (model.lastWatchedMs(c) > 0) c,
  ]..sort((a, b) => model.lastWatchedMs(b).compareTo(model.lastWatchedMs(a)));
  final out = <VideoItem>[];
  for (final c in watched) {
    if (c.videos.any((v) => model.placeOf(v.id)?.inProgress ?? false)) continue;
    final next = model.nextUp(c);
    if (next == null || (model.placeOf(next.id)?.watched ?? false)) continue;
    // A collection that hasn't been started (its first episode) isn't "up next".
    if (!c.videos.any((v) => model.placeOf(v.id)?.watched ?? false)) continue;
    out.add(next);
  }
  return out;
}

/// "Music", "Audiobooks", "Videos": a section's heading, with "See all" opening its tab.
class _SectionHeading extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onSeeAll;
  const _SectionHeading(this.title, {required this.icon, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                ),
              ),
              TextButton(key: ValueKey('see-all-$title'), onPressed: onSeeAll, child: const Text('See all')),
            ],
          ),
          const SizedBox(height: 4),
          Divider(height: 1, color: accent.withValues(alpha: 0.35)),
        ],
      ),
    );
  }
}

/// The quick tiles under Jump back in: Shuffle all, Liked Songs, Favourite audiobooks,
/// Favourite videos (when there are any) and up to six playlists.
class _QuickTiles extends StatelessWidget {
  final LibraryModel lib;
  final PlaylistsModel pl;
  final bool hasFavouriteBooks, hasFavouriteVideos;
  const _QuickTiles({
    required this.lib,
    required this.pl,
    required this.hasFavouriteBooks,
    required this.hasFavouriteVideos,
  });

  @override
  Widget build(BuildContext context) {
    final nav = context.read<AppNav>();
    final songs = lib.tracks;
    final tiles = <Widget>[
      if (songs.isNotEmpty)
        _QuickTile(
          icon: Icons.shuffle,
          label: 'Shuffle all',
          onTap: () => context.read<PlayerModel>().shufflePlay(songs, label: 'All songs'),
        ),
      if (pl.liked.isNotEmpty) _QuickTile(icon: Icons.favorite, label: 'Liked Songs', onTap: nav.openLiked),
      if (hasFavouriteBooks)
        _QuickTile(
          icon: Icons.menu_book,
          label: 'Favourite audiobooks',
          onTap: () => nav.openView(AppNav.booksTab, AppNav.favouriteBooksView),
        ),
      if (hasFavouriteVideos)
        _QuickTile(
          icon: Icons.video_library,
          label: 'Favourite videos',
          onTap: () => nav.openView(AppNav.videosTab, AppNav.favouriteVideosView),
        ),
      // Up to six playlists, with their own icon or picture, else the first song's cover (0.1.67).
      for (final p in pl.playlists.take(6))
        _QuickTile(
          icon: Icons.queue_music,
          label: p.name,
          art: PlaylistArt(playlist: p, radius: 0),
          onTap: () => nav.openPlaylist(p),
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: LayoutBuilder(
        builder: (context, c) {
          // 2 to 4 columns of tiles depending on the width.
          final cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 560 ? 3 : 2);
          return GridView.count(
            key: const ValueKey('home-quick-tiles'),
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3.6,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: tiles,
          );
        },
      ),
    );
  }
}

/// A wide, short tile on Home: a square picture (a cover, or an [icon] on a tinted square)
/// with a bold label beside it.
class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;

  /// A picture of its own (a playlist's, 0.1.67), in place of [icon].
  final Widget? art;
  final VoidCallback onTap;
  const _QuickTile({required this.icon, required this.label, required this.onTap, this.art});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: AppShape.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: art ??
                  Container(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                    child: Icon(icon, color: AppColors.current.onAccent),
                  ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
