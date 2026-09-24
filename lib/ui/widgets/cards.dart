import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../nav.dart';
import '../theme.dart';
import 'artwork.dart';

/// Album tile for grids and carousels.
class AlbumCard extends StatelessWidget {
  final Album album;
  final double? width;
  final bool showArtist;
  const AlbumCard({super.key, required this.album, this.width, this.showArtist = true});

  @override
  Widget build(BuildContext context) {
    final card = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.read<AppNav>().openAlbum(album),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(aspectRatio: 1, child: ArtworkFill(track: album.artTrack)),
          const SizedBox(height: 8),
          Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            showArtist ? album.artist : (album.year?.toString() ?? 'Album'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ]),
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// Round artist tile.
class ArtistCard extends StatelessWidget {
  final Artist artist;
  final double? width;
  const ArtistCard({super.key, required this.artist, this.width});

  @override
  Widget build(BuildContext context) {
    final art = artist.albums.isEmpty ? null : artist.albums.first.artTrack;
    final card = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.read<AppNav>().openArtist(artist.name),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (_, c) => Artwork(track: art, size: c.maxWidth, radius: c.maxWidth / 2, placeholder: Icons.person),
            ),
          ),
          const SizedBox(height: 8),
          Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const Text('Artist', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        ]),
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// Section header + horizontal carousel.
class Shelf extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final double height;
  const Shelf({super.key, required this.title, required this.children, this.height = 230});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      ),
      SizedBox(
        height: height,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: children,
        ),
      ),
    ]);
  }
}

/// Responsive grid column count for album grids.
int gridColumns(double width) => (width / 190).floor().clamp(2, 8);

/// Friendly empty message.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: AppColors.textDim),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textDim)),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}
