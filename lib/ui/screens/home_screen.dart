// The Home tab: the first page you see. It greets you by time of day and shows shelves of
// things to jump back into: books you're part-way through, quick tiles (Shuffle all, Liked
// Songs, your playlists), recently added albums, albums from your Liked Songs, and artists.
//
// It watches LibraryModel, PlaylistsModel and ListeningModel, so it refreshes as scans finish
// or you like songs. With an empty library it shows a single "Add music" button instead, which
// jumps straight to Settings > Library > Music folders.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/book_card.dart';
import '../widgets/cards.dart';
import '../widgets/music_access_banner.dart';

/// The Home tab page.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// "Good morning / afternoon / evening", based on the device clock.
  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final pl = context.watch<PlaylistsModel>();
    final nav = context.read<AppNav>();
    final listening = context.watch<ListeningModel>();
    // Books with a saved place that aren't finished, most recent first.
    final continueBooks = listening.inProgress(lib.books);
    // Book covers can be square or tall (a setting), which changes the shelf height.
    final ratio = bookCoverRatio(context);

    // Nothing in the library yet: show a single helpful message (or "scanning" while busy).
    if (lib.tracks.isEmpty && lib.books.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_greeting())),
        body: EmptyState(
          icon: Icons.library_music_outlined,
          title: lib.busy ? 'Scanning your music…' : 'No music yet',
          message: lib.busy
              ? 'Progress is shown at the bottom of the screen.'
              : 'Point HomeTunes at the folder where your music lives, or connect a music server.',
          action: lib.busy
              ? null
              : FilledButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Add music'),
                  onPressed: () => nav.openSettings('library', setting: 'music-folders'),
                ),
        ),
      );
    }

    // "Recently added": newest local files first.
    final recent = lib.albumsByNewest;
    // Liked Songs are stored as ids; drop any whose song is no longer in the library.
    final likedTracks = [for (final id in pl.liked) lib.byId(id)].whereType<Track>().toList();

    return Scaffold(
      appBar: AppBar(title: Text(_greeting(), style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        // Warns (on Android) when the app doesn't have permission to read music.
        const MusicAccessBanner(),
        if (continueBooks.isNotEmpty)
          Shelf(
            title: 'Continue listening',
            height: bookCardHeight(150, ratio),
            children: [
              for (final b in continueBooks.take(12))
                BookCard(book: b, width: 150, scope: [for (final x in continueBooks.take(12)) x.id]),
            ],
          ),
        // Quick tiles
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: LayoutBuilder(builder: (context, c) {
            // 2 to 4 columns of tiles depending on the width.
            final cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 560 ? 3 : 2);
            final tiles = <Widget>[
              _QuickTile(
                icon: Icons.shuffle,
                label: 'Shuffle all',
                onTap: () => context.read<PlayerModel>().shufflePlay(lib.tracks, label: 'All songs'),
              ),
              _QuickTile(icon: Icons.favorite, label: 'Liked Songs', onTap: nav.openLiked),
              // Up to six playlists get a tile, using the first song's cover as the picture.
              for (final p in pl.playlists.take(6))
                _QuickTile(
                  icon: Icons.queue_music,
                  label: p.name,
                  track: p.trackIds.isEmpty ? null : lib.byId(p.trackIds.first),
                  onTap: () => nav.openPlaylist(p),
                ),
            ];
            // A non-scrolling grid inside the page's own scrolling list.
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 3.6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: tiles,
            );
          }),
        ),
        Shelf(
          title: 'Recently added',
          children: [
            for (final a in recent.take(15))
              AlbumCard(album: a, width: 170, scope: [for (final x in recent.take(15)) x.key]),
          ],
        ),
        if (likedTracks.isNotEmpty)
          Shelf(
            title: 'From your Liked Songs',
            children: [
              for (final a in _albumsOf(likedTracks, lib).take(15))
                AlbumCard(album: a, width: 170, scope: [for (final x in _albumsOf(likedTracks, lib).take(15)) x.key]),
            ],
          ),
        Shelf(
          title: 'Artists',
          height: 220,
          children: [for (final a in lib.artists.take(20)) ArtistCard(artist: a, width: 160)],
        ),
      ]),
    );
  }

  /// The albums that [tracks] belong to, in order, each listed once. Used for the
  /// "From your Liked Songs" shelf.
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

/// A wide, short tile on Home: a square picture (a cover, or an [icon] on a tinted square)
/// with a bold label beside it.
class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Track? track;
  final VoidCallback onTap;
  const _QuickTile({required this.icon, required this.label, required this.onTap, this.track});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(children: [
          AspectRatio(
            aspectRatio: 1,
            child: track != null
                ? ArtworkFill(track: track, radius: 0)
                : Container(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                    child: Icon(icon, color: Colors.white),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ]),
      ),
    );
  }
}
