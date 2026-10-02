// Changing an artist's picture (0.1.53, the user asked: "Allow the artists page to be
// customised too, I want to be able to change the image that's used").
//
// Artists have no picture of their own in the music files, so HomeTunes shows their first
// album's cover. "Change picture…" (on the artist page, and in the right-click / press-and-hold
// menu of an artist anywhere: the Artists tab's list and grid, Home, Search) offers:
//   - Choose an image file…      copied into HomeTunes' own picture folder (art/custom);
//   - Use one of their album covers…   a grid of their albums to pick from;
//   - Use the automatic picture  back to the first album's cover (only when one was chosen).
// The choice is kept in LibraryModel.artistPictures (settings.json, so it's in backups) and
// every artist picture (Artwork(artist: …)) follows it straight away.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/library_model.dart';
import '../theme.dart';
import 'artwork.dart';
import 'quick_actions.dart';

/// The right-click / press-and-hold menu on an artist.
Future<void> showArtistMenu(BuildContext context, Artist artist, Offset at) {
  final lib = context.read<LibraryModel>();
  return showQuickActions(context, at, [
    QuickAction(Icons.image_outlined, 'Change picture…', () => showArtistPictureOptions(context, artist)),
    if (lib.hasArtistPicture(artist))
      QuickAction(Icons.restore, 'Use the automatic picture', () => _reset(context, artist)),
  ]);
}

Future<void> _reset(BuildContext context, Artist artist) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await context.read<LibraryModel>().setArtistPicture(artist);
  messenger?.showSnackBar(const SnackBar(content: Text('Back to the automatic picture')));
}

/// Change picture… for an artist: an image file, one of their album covers, or automatic.
Future<void> showArtistPictureOptions(BuildContext context, Artist artist) async {
  final lib = context.read<LibraryModel>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  Widget option(BuildContext ctx, String value, IconData icon, String label, String detail) => SimpleDialogOption(
        key: ValueKey('artist-picture-$value'),
        onPressed: () => Navigator.of(ctx).pop(value),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(label),
          subtitle: Text(detail, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ),
      );
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Picture for ${artist.name}', maxLines: 2, overflow: TextOverflow.ellipsis),
      children: [
        option(ctx, 'file', Icons.image_outlined, 'Choose an image file…', 'A photo or picture you already have'),
        if (artist.albums.isNotEmpty)
          option(ctx, 'album', Icons.album_outlined, 'Use one of their album covers…',
              '${artist.albums.length} album${artist.albums.length == 1 ? '' : 's'} to pick from'),
        if (lib.hasArtistPicture(artist))
          option(ctx, 'auto', Icons.restore, 'Use the automatic picture', 'Their first album\'s cover'),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'auto':
      await _reset(context, artist);
    case 'album':
      final album = await _pickAlbum(context, artist);
      if (album == null) return;
      await lib.setArtistPicture(artist, album: album);
      messenger?.showSnackBar(SnackBar(content: Text('${artist.name} now shows "${album.title}"')));
    case 'file':
      try {
        final file = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Choose a picture for ${artist.name}');
        final path = file?.path;
        if (path == null) return;
        final copy = await lib.importCover(path);
        await lib.setArtistPicture(artist, file: copy);
        messenger?.showSnackBar(SnackBar(content: Text('New picture for ${artist.name}')));
      } catch (e) {
        messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t use that picture: $e')));
      }
  }
}

/// A grid of the artist's album covers; returns the one tapped (null if closed).
Future<Album?> _pickAlbum(BuildContext context, Artist artist) {
  final lib = context.read<LibraryModel>();
  final current = lib.artistAlbumArt(artist);
  return showDialog<Album>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Pick a cover for ${artist.name}', maxLines: 2, overflow: TextOverflow.ellipsis),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: SizedBox(
        width: 520,
        child: GridView.extent(
          shrinkWrap: true,
          maxCrossAxisExtent: 150,
          childAspectRatio: 0.78,
          children: [
            for (final a in artist.albums)
              InkWell(
                key: ValueKey('artist-album-pick:${a.key}'),
                borderRadius: AppShape.circular(8),
                onTap: () => Navigator.of(ctx).pop(a),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        // The cover used now has a ring round it.
                        decoration: identical(a.artTrack, current) && lib.hasArtistPicture(artist)
                            ? BoxDecoration(
                                border: Border.all(color: Theme.of(ctx).colorScheme.primary, width: 3),
                                borderRadius: AppShape.circular(8))
                            : null,
                        child: ArtworkFill(track: a.artTrack),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  ]),
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel'))],
    ),
  );
}
