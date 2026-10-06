// Playlist icons (0.1.67, the user's request: "an option on playlists to customise their icons").
//
// A playlist can have a built-in icon on a colour, or a picture the user chose; otherwise it
// shows its first song's cover as before. [PlaylistArt] draws whichever it has (the Library's
// Playlists tab, a playlist's page, Home's tiles, the sidebar's quick links use the icon), and
// [showPlaylistIconPicker] is the "Change icon…" dialog (a playlist page's ⋮ menu, or a click on
// its picture there).
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../state/library_model.dart';
import '../../state/playlists_model.dart';
import '../theme.dart';
import 'artwork.dart';

/// The built-in icons, by the name saved in playlists.json (names never change once used).
const playlistIcons = <String, IconData>{
  'music': Icons.music_note,
  'queue': Icons.queue_music,
  'headphones': Icons.headphones,
  'album': Icons.album,
  'mic': Icons.mic,
  'piano': Icons.piano,
  'radio': Icons.radio,
  'heart': Icons.favorite,
  'star': Icons.star,
  'mood': Icons.mood,
  'fire': Icons.local_fire_department,
  'bolt': Icons.bolt,
  'party': Icons.celebration,
  'nightlife': Icons.nightlife,
  'run': Icons.directions_run,
  'fitness': Icons.fitness_center,
  'car': Icons.directions_car,
  'plane': Icons.flight,
  'beach': Icons.beach_access,
  'sun': Icons.wb_sunny,
  'snow': Icons.ac_unit,
  'sleep': Icons.bedtime,
  'spa': Icons.spa,
  'coffee': Icons.local_cafe,
  'work': Icons.work_outline,
  'study': Icons.school,
  'game': Icons.sports_esports,
  'home': Icons.home,
  'pets': Icons.pets,
  'rocket': Icons.rocket_launch,
};

/// The colours offered behind an icon (null in a playlist = the theme's accent).
const playlistColours = <int>[
  0xFFE53935, 0xFFD81B60, 0xFF8E24AA, 0xFF5E35B1, 0xFF3949AB, 0xFF1E88E5, 0xFF00ACC1,
  0xFF00897B, 0xFF43A047, 0xFF7CB342, 0xFFFDD835, 0xFFFB8C00, 0xFF6D4C41, 0xFF546E7A,
];

/// The icon of [pl] for small places (the sidebar's quick link): its own, else the usual one.
IconData playlistIconOf(Playlist pl) => playlistIcons[pl.iconName] ?? Icons.queue_music;

/// A playlist's picture: its own picture, its icon on its colour, or its first song's cover.
/// [size] null fills the space it's given (a playlist's page, Home's tiles).
class PlaylistArt extends StatelessWidget {
  final Playlist playlist;
  final double? size;
  final double radius;
  const PlaylistArt({super.key, required this.playlist, this.size, this.radius = 4});

  @override
  Widget build(BuildContext context) {
    final pl = context.watch<PlaylistsModel>();
    final picture = pl.pictureFile(playlist);
    final Widget art;
    if (picture != null) {
      art = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(picture),
          key: const ValueKey('playlist-picture'),
          fit: BoxFit.cover,
          width: size,
          height: size,
          cacheWidth: size == null ? 600 : (size! * 2).round(),
          errorBuilder: (_, _, _) => _fallback(context),
        ),
      );
    } else if (playlistIcons[playlist.iconName] case final icon?) {
      art = PlaylistIconTile(icon: icon, colour: playlist.iconColour, size: size, radius: radius);
    } else {
      art = _fallback(context);
    }
    return size == null ? art : SizedBox(width: size, height: size, child: art);
  }

  Widget _fallback(BuildContext context) {
    final lib = context.read<LibraryModel>();
    final first = playlist.trackIds.isEmpty ? null : lib.byId(playlist.trackIds.first);
    return size == null
        ? ArtworkFill(track: first, radius: radius, placeholder: Icons.queue_music)
        : Artwork(track: first, size: size!, radius: radius, placeholder: Icons.queue_music);
  }
}

/// An icon on a coloured square (a playlist's own icon, and the chooser's preview).
class PlaylistIconTile extends StatelessWidget {
  final IconData icon;
  final int? colour;
  final double? size;
  final double radius;
  const PlaylistIconTile({super.key, required this.icon, this.colour, this.size, this.radius = 4});

  @override
  Widget build(BuildContext context) {
    final base = colour == null ? Theme.of(context).colorScheme.primary : Color(colour!);
    // White or black on the colour, whichever reads better.
    final fg = ThemeData.estimateBrightnessForColor(base) == Brightness.dark ? Colors.white : Colors.black87;
    return Container(
      key: const ValueKey('playlist-icon'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, Colors.black, 0.35)!],
        ),
      ),
      child: LayoutBuilder(
        builder: (_, box) => Icon(icon, color: fg, size: (box.biggest.shortestSide * 0.55).clamp(12, 120)),
      ),
    );
  }
}

/// What the chooser came back with.
sealed class _IconChoice {}

class _UseIcon extends _IconChoice {
  final String name;
  final int? colour;
  _UseIcon(this.name, this.colour);
}

class _UsePicture extends _IconChoice {}

class _UseCover extends _IconChoice {}

/// "Change icon…": pick a built-in icon and colour, choose a picture, or go back to the first
/// song's cover.
Future<void> showPlaylistIconPicker(BuildContext context, Playlist playlist) async {
  final model = context.read<PlaylistsModel>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final choice = await showDialog<_IconChoice>(
    context: context,
    builder: (_) => _PlaylistIconDialog(playlist: playlist),
  );
  switch (choice) {
    case _UseIcon(:final name, :final colour):
      model.setIcon(playlist, name, colour);
    case _UseCover():
      model.clearIcon(playlist);
    case _UsePicture():
      try {
        final file = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Choose a picture for ${playlist.name}');
        final path = file?.path;
        if (path == null) return;
        await model.setPicture(playlist, path);
      } catch (e) {
        messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t use that picture: $e')));
      }
    case null:
  }
}

class _PlaylistIconDialog extends StatefulWidget {
  final Playlist playlist;
  const _PlaylistIconDialog({required this.playlist});

  @override
  State<_PlaylistIconDialog> createState() => _PlaylistIconDialogState();
}

class _PlaylistIconDialogState extends State<_PlaylistIconDialog> {
  late String name = playlistIcons.containsKey(widget.playlist.iconName) ? widget.playlist.iconName! : 'music';
  late int? colour = widget.playlist.iconColour;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    Widget swatch(int? c) {
      final selected = colour == c;
      return Tooltip(
        message: c == null ? 'The app\'s colour' : '',
        child: InkWell(
          key: ValueKey('playlist-colour:${c ?? 'accent'}'),
          customBorder: const CircleBorder(),
          onTap: () => setState(() => colour = c),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c == null ? accent : Color(c),
              border: Border.all(color: selected ? AppColors.text : Colors.transparent, width: 3),
            ),
            child: c == null ? Icon(Icons.palette_outlined, size: 16, color: AppColors.current.onAccent) : null,
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text('Icon for ${widget.playlist.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: PlaylistIconTile(icon: playlistIcons[name]!, colour: colour, size: 96, radius: 8),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final e in playlistIcons.entries)
                IconButton(
                  key: ValueKey('playlist-icon:${e.key}'),
                  isSelected: name == e.key,
                  style: IconButton.styleFrom(
                    backgroundColor: name == e.key ? accent.withValues(alpha: 0.25) : null,
                  ),
                  icon: Icon(e.value),
                  onPressed: () => setState(() => name = e.key),
                ),
            ]),
            const SizedBox(height: 12),
            Text('Colour', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [swatch(null), for (final c in playlistColours) swatch(c)]),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton.icon(
                key: const ValueKey('playlist-picture-choose'),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Choose a picture…'),
                onPressed: () => Navigator.pop(context, _UsePicture()),
              ),
              if (widget.playlist.hasOwnIcon)
                TextButton.icon(
                  key: const ValueKey('playlist-icon-reset'),
                  icon: const Icon(Icons.restore),
                  label: const Text('Use the first song\'s cover'),
                  onPressed: () => Navigator.pop(context, _UseCover()),
                ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('playlist-icon-save'),
          onPressed: () => Navigator.pop(context, _UseIcon(name, colour)),
          child: const Text('Use this icon'),
        ),
      ],
    );
  }
}
