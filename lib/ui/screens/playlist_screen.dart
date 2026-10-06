// The page for one playlist, or for Liked Songs (the same page in a special mode).
//
// Playlists only store song ids (PlaylistsModel, playlists.json). This page looks each id up in
// LibraryModel; songs that can't be found right now (file gone, server off) are counted as
// "unavailable" but kept in the playlist so they come back when the song does.
// Songs can be dragged to reorder, removed from the ⋮ menu, and the playlist renamed or deleted.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/library_model.dart';
import '../../state/playlists_model.dart';
import '../theme.dart';
import '../widgets/cards.dart';
import '../widgets/collection_header.dart';
import '../widgets/playlist_art.dart';
import '../widgets/quick_links.dart';
import '../widgets/track_tile.dart';

/// A user playlist, or Liked Songs when [playlistId] is null.
class PlaylistScreen extends StatelessWidget {
  /// The playlist's id, or null for Liked Songs.
  final String? playlistId;
  /// Opens a normal playlist.
  const PlaylistScreen({super.key, required String this.playlistId});
  /// Opens Liked Songs.
  const PlaylistScreen.liked({super.key}) : playlistId = null;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final pl = context.watch<PlaylistsModel>();
    final accent = Theme.of(context).colorScheme.primary;

    if (playlistId == null) {
      // Liked Songs
      final tracks = [for (final id in pl.liked) lib.byId(id)].whereType<Track>().toList();
      return Scaffold(
        appBar: AppBar(),
        // Rows are built lazily as you scroll, so a long Liked list stays fast.
        body: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: CollectionHeader(
            art: Container(
              decoration: BoxDecoration(
                borderRadius: AppShape.circular(6),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent, accent.withValues(alpha: 0.3)],
                ),
              ),
              child: Icon(Icons.favorite, size: 72, color: AppColors.current.onAccent),
            ),
            kind: 'Playlist',
            title: 'Liked Songs',
            subtitle: [
              '${tracks.length} songs',
              // Liked songs that aren't on this device are kept for when they come back.
              if (pl.liked.length > tracks.length) '${pl.liked.length - tracks.length} unavailable',
            ].join(' · '),
            tracks: tracks,
            contextLabel: 'Liked Songs',
            ),
          ),
          if (tracks.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.favorite_border,
                title: 'Songs you like will appear here',
                message: 'Tap the heart on any song.',
              ),
            ),
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (_, i) => TrackTile(track: tracks[i], list: tracks, index: i, contextLabel: 'Liked Songs'),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ]),
      );
    }

    // ---- A normal playlist ----
    final playlist = pl.byId(playlistId!);
    if (playlist == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.queue_music, title: 'Playlist not found'));
    }

    // Keep the playlist index for each visible track so removing works even if
    // some songs are missing (e.g. server switched off).
    final entries = <(int, Track)>[];
    for (var i = 0; i < playlist.trackIds.length; i++) {
      final t = lib.byId(playlist.trackIds[i]);
      if (t != null) entries.add((i, t));
    }
    final tracks = [for (final e in entries) e.$2];
    final missing = playlist.trackIds.length - tracks.length;
    final total = tracks.fold(Duration.zero, (a, t) => a + t.duration);
    final label = 'Playlist · ${playlist.name}';

    // App bar with a ⋮ menu for Rename and Delete.
    return Scaffold(
      appBar: AppBar(actions: [
        // Add to / remove from the sidebar's quick links (6 Oct).
        QuickLinkButton(link: QuickLink(QuickLinkKind.playlist, playlist.id, playlist.name)),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'icon') {
              await showPlaylistIconPicker(context, playlist);
            } else if (v == 'rename') {
              final name = await askForName(context, title: 'Rename playlist', initial: playlist.name);
              if (name != null) pl.rename(playlist, name);
            } else if (v == 'delete') {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Delete "${playlist.name}"?'),
                  content: const Text('Your music files are not touched.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                  ],
                ),
              );
              // Leave the page first, then delete, so we're not showing a playlist that's gone.
              if (ok == true && context.mounted) {
                Navigator.of(context).pop();
                pl.delete(playlist);
                // Its quick link in the sidebar goes too.
                lib.removeQuickLink(QuickLinkKind.playlist, playlist.id);
              }
            }
          },
          itemBuilder: (_) => const [
            // Its own icon or picture (0.1.67).
            PopupMenuItem(key: ValueKey('playlist-change-icon'), value: 'icon', child: Text('Change icon…')),
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
          ],
        ),
      ]),
      // Header, an "empty" hint if needed, then the draggable song list.
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: CollectionHeader(
            // Its own icon or picture, else the first song's cover; a click changes it (0.1.67).
            art: Tooltip(
              message: 'Change icon',
              child: InkWell(
                key: const ValueKey('playlist-art'),
                onTap: () => showPlaylistIconPicker(context, playlist),
                child: PlaylistArt(playlist: playlist, radius: 6),
              ),
            ),
            kind: 'Playlist',
            title: playlist.name,
            subtitle: [
              '${tracks.length} songs',
              if (tracks.isNotEmpty) formatLong(total),
              // Kept for when they're back (files missing, or server switched off).
              if (missing > 0) '$missing unavailable',
            ].join(' · '),
            tracks: tracks,
            contextLabel: label,
          ),
        ),
        if (tracks.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.playlist_add,
              title: 'This playlist is empty',
              message: 'Use "Add to playlist…" from any song\'s ⋮ menu.',
            ),
          ),
        SliverReorderableList(
          itemCount: entries.length,
          onReorderItem: (oldI, newI) {
            // Reorder the visible songs; unavailable ones keep their place at the end.
            final order = [for (final e in entries) e.$1];
            order.insert(newI, order.removeAt(oldI));
            final visible = order.toSet();
            pl.setOrder(playlist, [
              for (final i in order) playlist.trackIds[i],
              for (var i = 0; i < playlist.trackIds.length; i++)
                if (!visible.contains(i)) playlist.trackIds[i],
            ]);
          },
          // pIndex is the song's real position in the playlist (used for removing it).
          itemBuilder: (context, i) {
            final (pIndex, t) = entries[i];
            return Material(
              key: ValueKey('${t.id}#$pIndex'),
              color: Colors.transparent,
              child: Row(children: [
                ReorderableDragStartListener(
                  index: i,
                  child: Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.drag_indicator, color: AppColors.textDim),
                  ),
                ),
                Expanded(
                  child: TrackTile(
                    track: t,
                    list: tracks,
                    index: i,
                    contextLabel: label,
                    // An extra item in the song's ⋮ menu. Its value is the action to run
                    // when it's picked.
                    extraAction: PopupMenuItem(
                      value: () => pl.removeAt(playlist, pIndex),
                      child: const Row(children: [
                        Icon(Icons.remove_circle_outline, size: 20),
                        SizedBox(width: 12),
                        Text('Remove from this playlist'),
                      ]),
                    ),
                  ),
                ),
              ]),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }
}
