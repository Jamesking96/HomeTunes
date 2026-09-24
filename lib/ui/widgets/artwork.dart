import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/library_model.dart';
import '../theme.dart';

/// Square cover art with a placeholder when there's none.
class Artwork extends StatelessWidget {
  final Track? track;
  final double size;
  final double radius;
  final IconData placeholder;

  const Artwork({super.key, this.track, required this.size, this.radius = 4, this.placeholder = Icons.music_note});

  @override
  Widget build(BuildContext context) {
    final lib = context.read<LibraryModel>();
    // Ask the server for roughly the size we draw, times 2 for sharp screens.
    final px = (size * 2).clamp(64, 800).round();
    final image = lib.artFor(track, size: px);
    final ph = Container(
      width: size,
      height: size,
      color: AppColors.surfaceHigh,
      child: Icon(placeholder, color: AppColors.textDim, size: size * 0.4),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: image == null
          ? ph
          : Image(
              image: ResizeImage.resizeIfNeeded(px, null, image),
              width: size,
              height: size,
              fit: BoxFit.cover,
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
