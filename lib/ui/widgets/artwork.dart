// Cover pictures for songs and albums, used almost everywhere (lists, grids, player bar), and
// artists' pictures (0.1.53: `artist:`, see LibraryModel.artistImage).
//
// LibraryModel.artFor works out where the picture comes from (a cached file on disk, the
// user's own cover, or the server's cover URL); this widget just draws it at the right size, or
// a grey box with an icon when there isn't one or it fails to load.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/library_model.dart';
import '../theme.dart';

/// Square cover art with a placeholder when there's none.
class Artwork extends StatelessWidget {
  /// Whose cover to show (null shows the placeholder).
  final Track? track;
  /// Width and height in logical pixels.
  final double size;
  /// Corner rounding.
  final double radius;
  /// Icon drawn in the grey box when there's no cover.
  final IconData placeholder;

  /// Draw this artist's picture instead of [track]'s cover (0.1.53): the picture chosen for them,
  /// or else their first album's cover. Redraws when their picture is changed.
  final Artist? artist;

  const Artwork(
      {super.key, this.track, required this.size, this.radius = 4, this.placeholder = Icons.music_note, this.artist});

  @override
  Widget build(BuildContext context) {
    final lib = context.read<LibraryModel>();
    // Ask the server for roughly the size we draw, times 2 for sharp screens.
    final px = (size * 2).clamp(64, 800).round();
    final a = artist;
    if (a != null) context.select<LibraryModel, String?>((l) => l.artistPictures[a.name]);
    final image = a != null ? lib.artistImage(a, size: px) : lib.artFor(track, size: px);
    final ph = Container(
      width: size,
      height: size,
      color: AppColors.surfaceHigh,
      child: Icon(placeholder, color: AppColors.textDim, size: size * 0.4),
    );
    return ClipRRect(
      borderRadius: AppShape.circular(radius),
      child: image == null
          ? ph
          : Image(
              // Decode the picture at the size we need, not its full size: a 3000 px cover in a
              // 48 px list row would otherwise waste a lot of memory.
              image: ResizeImage.resizeIfNeeded(px, null, image),
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Keep showing the old cover until the new one is ready (no flash when the song
              // changes), and fall back to the placeholder if the file is missing or broken.
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => ph,
            ),
    );
  }
}

/// Artwork that fills its parent (for grids).
class ArtworkFill extends StatelessWidget {
  final Track? track;
  final double radius;
  final IconData placeholder;
  const ArtworkFill({super.key, this.track, this.radius = 6, this.placeholder = Icons.album});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => Artwork(track: track, size: c.maxWidth, radius: radius, placeholder: placeholder),
    );
  }
}
