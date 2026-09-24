import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/cards.dart';
import '../widgets/collection_header.dart';
import '../widgets/track_tile.dart';

class AlbumScreen extends StatelessWidget {
  final String albumKey;
  const AlbumScreen({super.key, required this.albumKey});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final album = lib.albumByKey(albumKey);
    if (album == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.album, title: 'Album not found'));
    }
    final tracks = album.tracks;
    final multiDisc = tracks.map((t) => t.discNumber ?? 1).toSet().length > 1;
    final label = 'Album · ${album.title}';

    final children = <Widget>[];
    int? disc;
    for (var i = 0; i < tracks.length; i++) {
      final d = tracks[i].discNumber ?? 1;
      if (multiDisc && d != disc) {
        disc = d;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(children: [
            const Icon(Icons.album, size: 18, color: AppColors.textDim),
            const SizedBox(width: 8),
            Text('Disc $d', style: const TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
          ]),
        ));
      }
      children.add(TrackTile(track: tracks[i], list: tracks, index: i, showNumber: true, contextLabel: label));
    }

    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        CollectionHeader(
          art: ArtworkFill(track: album.artTrack),
          kind: 'Album',
          title: album.title,
          subtitle: [
            album.artist,
            if (album.year != null) '${album.year}',
            '${tracks.length} songs, ${formatLong(album.totalDuration)}',
          ].join(' · '),
          tracks: tracks,
          contextLabel: label,
          extraActions: [
            IconButton(
              tooltip: 'Add album to playlist',
              icon: const Icon(Icons.playlist_add),
              onPressed: () => showAddToPlaylist(context, tracks),
            ),
            TextButton(
              onPressed: () => context.read<AppNav>().openArtist(album.artist),
              child: Text(album.artist),
            ),
          ],
        ),
        ...children,
      ]),
    );
  }
}
