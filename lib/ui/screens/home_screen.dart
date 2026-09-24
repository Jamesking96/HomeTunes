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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
    final continueBooks = listening.inProgress(lib.books);
    final ratio = bookCoverRatio(context);

    if (lib.tracks.isEmpty && lib.books.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_greeting())),
        body: EmptyState(
          icon: Icons.library_music_outlined,
          title: lib.busy ? 'Scanning your music…' : 'No music yet',
          message: lib.busy
              ? lib.status
              : 'Point HomeTunes at the folder where your music lives, or connect a music server.',
          action: lib.busy
              ? null
              : FilledButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Add music'),
                  onPressed: () => nav.selectTab(AppNav.settingsTab),
                ),
        ),
      );
    }

    // "Recently added": newest local files first.
    final recent = [...lib.albums]..sort((a, b) => _newest(b).compareTo(_newest(a)));
    final likedTracks = [for (final id in pl.liked) lib.byId(id)].whereType<Track>().toList();

    return Scaffold(
      appBar: AppBar(title: Text(_greeting(), style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (continueBooks.isNotEmpty)
          Shelf(
            title: 'Continue listening',
            height: bookCardHeight(150, ratio),
            children: [for (final b in continueBooks.take(12)) BookCard(book: b, width: 150)],
          ),
        // Quick tiles
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 560 ? 3 : 2);
            final tiles = <Widget>[
              _QuickTile(
                icon: Icons.shuffle,
                label: 'Shuffle all',
                onTap: () => context.read<PlayerModel>().shufflePlay(lib.tracks, label: 'All songs'),
              ),
              _QuickTile(icon: Icons.favorite, label: 'Liked Songs', onTap: nav.openLiked),
              for (final p in pl.playlists.take(6))
                _QuickTile(
                  icon: Icons.queue_music,
                  label: p.name,
                  track: p.trackIds.isEmpty ? null : lib.byId(p.trackIds.first),
                  onTap: () => nav.openPlaylist(p),
                ),
            ];
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
          children: [for (final a in recent.take(15)) AlbumCard(album: a, width: 170)],
        ),
        if (likedTracks.isNotEmpty)
          Shelf(
            title: 'From your Liked Songs',
            children: [
              for (final a in _albumsOf(likedTracks, lib).take(15)) AlbumCard(album: a, width: 170),
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

  static int _newest(Album a) =>
      a.tracks.fold<int>(0, (m, t) => (t.modifiedMs ?? 0) > m ? (t.modifiedMs ?? 0) : m);

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
