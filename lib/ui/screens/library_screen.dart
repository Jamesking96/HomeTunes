// The Library tab ("Your Library"): four swipeable tabs listing playlists, artists, albums
// and every song. There's also a + button to create a new playlist.
//
// Each tab is its own small widget that watches LibraryModel / PlaylistsModel, so only the
// visible tab's list is built. Tapping an item opens its page through AppNav, which pushes it
// on this tab's own navigator (so the bottom bar stays in place).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/cards.dart';
import '../widgets/track_tile.dart';

/// Tabs: Playlists · Artists · Albums · Songs.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.read<AppNav>();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your Library', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'New playlist',
              icon: const Icon(Icons.add),
              // Ask for a name, create the playlist, then open it straight away.
              onPressed: () async {
                final name = await askForName(context, title: 'New playlist');
                if (name != null && context.mounted) {
                  nav.openPlaylist(context.read<PlaylistsModel>().create(name));
                }
              },
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Playlists'), Tab(text: 'Artists'), Tab(text: 'Albums'), Tab(text: 'Songs')],
          ),
        ),
        body: const TabBarView(children: [_PlaylistsTab(), _ArtistsTab(), _AlbumsTab(), _SongsTab()]),
      ),
    );
  }
}

/// Liked Songs (always first) followed by the user's playlists.
class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context) {
    final pl = context.watch<PlaylistsModel>();
    final lib = context.watch<LibraryModel>();
    final nav = context.read<AppNav>();
    final accent = Theme.of(context).colorScheme.primary;
    return ListView(children: [
      // Liked Songs gets a gradient tile in the accent colour instead of a cover.
      ListTile(
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.35)]),
          ),
          child: const Icon(Icons.favorite, color: Colors.white),
        ),
        title: const Text('Liked Songs', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${pl.liked.length} songs'),
        onTap: nav.openLiked,
      ),
      for (final p in pl.playlists)
        ListTile(
          leading: Artwork(
            track: p.trackIds.isEmpty ? null : lib.byId(p.trackIds.first),
            size: 52,
            placeholder: Icons.queue_music,
          ),
          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('Playlist · ${p.trackIds.length} songs'),
          onTap: () => nav.openPlaylist(p),
        ),
      if (pl.playlists.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Create a playlist with the + button above.', style: TextStyle(color: AppColors.textDim)),
        ),
    ]);
  }
}

/// Every artist (grouped by album artist), with a round picture from their first album.
class _ArtistsTab extends StatelessWidget {
  const _ArtistsTab();

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final nav = context.read<AppNav>();
    if (lib.artists.isEmpty) return const EmptyState(icon: Icons.person_outline, title: 'No artists yet');
    // .builder only builds the rows on screen, which keeps big libraries smooth.
    return ListView.builder(
      itemCount: lib.artists.length,
      itemBuilder: (_, i) {
        final a = lib.artists[i];
        return ListTile(
          leading: Artwork(
            track: a.albums.first.artTrack,
            size: 52,
            radius: 26,
            placeholder: Icons.person,
          ),
          title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${a.albums.length} album${a.albums.length == 1 ? '' : 's'}'),
          onTap: () => nav.openArtist(a.name),
        );
      },
    );
  }
}

/// A grid of every album's cover card.
class _AlbumsTab extends StatelessWidget {
  const _AlbumsTab();

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    if (lib.albums.isEmpty) return const EmptyState(icon: Icons.album_outlined, title: 'No albums yet');
    final keys = [for (final a in lib.albums) a.key];
    return LayoutBuilder(builder: (context, c) {
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridColumns(c.maxWidth),
          childAspectRatio: 0.78,
        ),
        itemCount: lib.albums.length,
        itemBuilder: (_, i) => AlbumCard(album: lib.albums[i], scope: keys),
      );
    });
  }
}

/// Every song, sorted by title, with a Shuffle button at the top.
class _SongsTab extends StatelessWidget {
  const _SongsTab();

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final songs = lib.songsByTitle;
    if (songs.isEmpty) return const EmptyState(icon: Icons.music_note_outlined, title: 'No songs yet');
    return ListView.builder(
      // One extra row at the top for the song count and Shuffle button, so rows are shifted by one.
      itemCount: songs.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Text('${songs.length} songs', style: const TextStyle(color: AppColors.textDim)),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.shuffle),
                label: const Text('Shuffle'),
                onPressed: () => context.read<PlayerModel>().shufflePlay(songs, label: 'All songs'),
              ),
            ]),
          );
        }
        return TrackTile(track: songs[i - 1], list: songs, index: i - 1, contextLabel: 'All songs');
      },
    );
  }
}
