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
import 'settings_screen.dart';

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
              onPressed: () async {
                final name = await askForName(context, title: 'New playlist');
                if (name != null && context.mounted) {
                  nav.openPlaylist(context.read<PlaylistsModel>().create(name));
                }
              },
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => nav.push(const SettingsScreen()),
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

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context) {
    final pl = context.watch<PlaylistsModel>();
    final lib = context.watch<LibraryModel>();
    final nav = context.read<AppNav>();
    final accent = Theme.of(context).colorScheme.primary;
    return ListView(children: [
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

class _ArtistsTab extends StatelessWidget {
  const _ArtistsTab();

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final nav = context.read<AppNav>();
    if (lib.artists.isEmpty) return const EmptyState(icon: Icons.person_outline, title: 'No artists yet');
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

class _AlbumsTab extends StatelessWidget {
  const _AlbumsTab();

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    if (lib.albums.isEmpty) return const EmptyState(icon: Icons.album_outlined, title: 'No albums yet');
    return LayoutBuilder(builder: (context, c) {
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridColumns(c.maxWidth),
          childAspectRatio: 0.78,
        ),
        itemCount: lib.albums.length,
        itemBuilder: (_, i) => AlbumCard(album: lib.albums[i]),
      );
    });
  }
}

class _SongsTab extends StatelessWidget {
  const _SongsTab();

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final songs = [...lib.tracks]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (songs.isEmpty) return const EmptyState(icon: Icons.music_note_outlined, title: 'No songs yet');
    return ListView.builder(
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
