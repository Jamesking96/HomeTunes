// The page for one artist: a header with a round picture and play/shuffle buttons, a grid of
// the artist's albums, then a list of every song by them.
//
// Opened through AppNav.openArtist (from album pages, cards and song menus). Artists are grouped
// by album artist in LibraryModel, and this page looks the artist up by name on every build so
// edits show straight away.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';
import '../widgets/artwork.dart';
import '../widgets/cards.dart';
import '../widgets/collection_header.dart';
import '../widgets/track_tile.dart';

/// Shows one artist, found by [name] in the library.
class ArtistScreen extends StatelessWidget {
  final String name;
  const ArtistScreen({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final artist = lib.artistByName(name);
    // The artist may disappear after an edit (e.g. all their songs were renamed to someone else).
    if (artist == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.person, title: 'Artist not found'));
    }
    final tracks = artist.tracks;
    final label = 'Artist · ${artist.name}';
    // There's no separate artist photo, so borrow the first album's cover (drawn as a circle).
    final art = artist.albums.first.artTrack;

    return Scaffold(
      appBar: AppBar(),
      // A scrolling list of "slivers" so the grid and the long song list share one scroll.
      body: CustomScrollView(slivers: [
        // 1. Header: round picture, name, counts and the play/shuffle buttons.
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
        // 2. "Albums" heading and a grid of album cards (column count follows the width).
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
              itemBuilder: (_, i) => AlbumCard(
                album: artist.albums[i],
                showArtist: false,
                scope: [for (final a in artist.albums) a.key],
              ),
            ),
          );
        }),
        // 3. "All songs" heading and every song by this artist.
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
