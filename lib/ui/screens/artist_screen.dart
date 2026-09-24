import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';
import '../widgets/artwork.dart';
import '../widgets/cards.dart';
import '../widgets/collection_header.dart';
import '../widgets/track_tile.dart';

class ArtistScreen extends StatelessWidget {
  final String name;
  const ArtistScreen({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final artist = lib.artistByName(name);
    if (artist == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.person, title: 'Artist not found'));
    }
    final tracks = artist.tracks;
    final label = 'Artist · ${artist.name}';
    final art = artist.albums.first.artTrack;

    return Scaffold(
      appBar: AppBar(),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: CollectionHeader(
            art: LayoutBuilder(
              builder: (_, c) => Artwork(track: art, size: c.maxWidth, radius: c.maxWidth / 2, placeholder: Icons.person),
            ),
            kind: 'Artist',
            title: artist.name,
            subtitle: '${artist.albums.length} albums · ${tracks.length} songs',
            tracks: tracks,
            contextLabel: label,
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Albums', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
        ),
        SliverLayoutBuilder(builder: (context, c) {
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridColumns(c.crossAxisExtent),
                childAspectRatio: 0.78,
              ),
              itemCount: artist.albums.length,
              itemBuilder: (_, i) => AlbumCard(album: artist.albums[i], showArtist: false),
            ),
          );
        }),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('All songs', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
        ),
        SliverList.builder(
          itemCount: tracks.length,
          itemBuilder: (_, i) => TrackTile(track: tracks[i], list: tracks, index: i, contextLabel: label),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }
}
