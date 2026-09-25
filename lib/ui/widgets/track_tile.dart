// Song rows and the song "⋮" menu, used in every list of songs (albums, playlists, search,
// Library, queue, Now Playing), plus two small shared dialogs: "Add to playlist" and a
// one-line name prompt (also used for new playlists and book genres).
//
// A row plays its list from that song when tapped, and handles multi-select (long-press to
// start, then taps tick/untick) through SelectionModel; Shell shows the selection bar.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../state/library_model.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../../state/selection_model.dart';
import '../nav.dart';
import '../screens/edit_details.dart';
import '../screens/lyrics_dialogs.dart';
import '../theme.dart';
import 'artwork.dart';

/// One song row. Tapping plays [list] starting at [index].
class TrackTile extends StatelessWidget {
  final Track track;
  /// The whole list this row belongs to; tapping plays all of it, starting here.
  final List<Track> list;
  /// This song's place in [list].
  final int index;
  /// Where the music is playing from (e.g. the album or playlist name), shown by the player.
  final String? contextLabel;

  /// Show a track number instead of artwork (album pages).
  final bool showNumber;

  /// Extra menu entry, e.g. "Remove from this playlist".
  final PopupMenuEntry<VoidCallback>? extraAction;

  const TrackTile({
    super.key,
    required this.track,
    required this.list,
    required this.index,
    this.contextLabel,
    this.showNumber = false,
    this.extraAction,
  });

  @override
  Widget build(BuildContext context) {
    // Only rebuild this row when the current song changes, not on every
    // buffering/volume/play-state update.
    final currentId = context.select<PlayerModel, String?>((p) => p.current?.id);
    final isCurrent = currentId == track.id;
    final accent = Theme.of(context).colorScheme.primary;
    final selecting = context.select<SelectionModel, bool>((s) => s.selecting(SelectKind.songs));
    final selected = context.select<SelectionModel, bool>((s) => s.contains(track.id));

    // Left side: a tick box in select mode, else the track number (album pages; a sound-wave
    // icon for the song playing), else the cover.
    Widget leading;
    if (selecting) {
      leading = SizedBox(
        width: showNumber ? 28 : 44,
        child: Checkbox(value: selected, onChanged: (_) => context.read<SelectionModel>().toggle(track.id)),
      );
    } else if (showNumber) {
      leading = SizedBox(
        width: 28,
        child: isCurrent
            ? Icon(Icons.graphic_eq, color: accent, size: 18)
            : Text('${track.trackNumber ?? index + 1}',
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textDim)),
      );
    } else {
      leading = Artwork(track: track, size: 44);
    }

    return ListTile(
      dense: false,
      selected: selected,
      selectedTileColor: accent.withValues(alpha: 0.12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: leading,
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: isCurrent ? accent : null, fontWeight: FontWeight.w500),
      ),
      // Subtitle: a small cloud for server songs, then artist (and album, unless we're on the
      // album's own page).
      subtitle: Row(children: [
        if (!track.isLocal)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Icons.cloud_outlined, size: 13, color: AppColors.textDim),
          ),
        Expanded(
          child: Text(
            showNumber ? track.artist : '${track.artist} · ${track.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        // The song length only fits on wider screens. The menu is hidden while selecting.
        if (MediaQuery.sizeOf(context).width > 600)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(formatDuration(track.duration), style: const TextStyle(color: AppColors.textDim)),
          ),
        if (!selecting) TrackMenuButton(track: track, extraAction: extraAction),
      ]),
      // In select mode a tap ticks/unticks; otherwise it plays. Long-press starts selecting.
      onTap: selecting
          ? () => context.read<SelectionModel>().toggle(track.id)
          : () => context.read<PlayerModel>().playTracks(list, start: index, label: contextLabel),
      onLongPress: () => context.read<SelectionModel>().toggle(track.id),
    );
  }
}

/// The "⋮" menu used on songs everywhere.
class TrackMenuButton extends StatelessWidget {
  final Track track;
  final PopupMenuEntry<VoidCallback>? extraAction;
  /// Set when the menu is on a page shown over the tabs (like Now Playing): that page is closed
  /// before going to an album or artist, so the new page can be seen.
  final bool closeRouteFirst;

  const TrackMenuButton({super.key, required this.track, this.extraAction, this.closeRouteFirst = false});

  @override
  Widget build(BuildContext context) {
    final playlists = context.read<PlaylistsModel>();
    final player = context.read<PlayerModel>();
    final nav = context.read<AppNav>();
    final lib = context.read<LibraryModel>();
    final liked = context.watch<PlaylistsModel>().isLiked(track);

    // Runs a "go to" action, closing the covering page first if needed.
    void goto(VoidCallback f) {
      if (closeRouteFirst) Navigator.of(context).pop();
      f();
    }

    // Each item's value is the action to run, so onSelected just calls it.
    // Sections: like / queue / playlists; go to album / artist; edit, lyrics, Books, select.
    return PopupMenuButton<VoidCallback>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'More',
      onSelected: (f) => f(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: () => playlists.toggleLike(track),
          child: _row(liked ? Icons.favorite : Icons.favorite_border, liked ? 'Remove from Liked Songs' : 'Like'),
        ),
        PopupMenuItem(value: () => player.playNext(track), child: _row(Icons.playlist_play, 'Play next')),
        PopupMenuItem(value: () => player.addToQueue(track), child: _row(Icons.queue_music, 'Add to queue')),
        PopupMenuItem(
          value: () => showAddToPlaylist(context, [track]),
          child: _row(Icons.playlist_add, 'Add to playlist…'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => goto(() {
            final a = lib.albumByKey(track.albumKey);
            if (a != null) nav.openAlbum(a);
          }),
          child: _row(Icons.album, 'Go to album'),
        ),
        PopupMenuItem(
          value: () => goto(() => nav.openArtist(track.albumArtist)),
          child: _row(Icons.person, 'Go to artist'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          // Opens on top of whatever is showing (including Now Playing).
          value: () => showEditDetails(context, [track]),
          child: _row(Icons.edit_outlined, 'Edit details…'),
        ),
        PopupMenuItem(
          value: () => showLyricsDialog(context, track),
          child: _row(Icons.lyrics_outlined, 'Lyrics'),
        ),
        PopupMenuItem(
          value: () => findLyricsOnline(context, track),
          child: _row(Icons.travel_explore, 'Find lyrics on LRCLIB…'),
        ),
        PopupMenuItem(
          value: () async {
            final messenger = ScaffoldMessenger.maybeOf(context);
            // Sets the user's override; Undo puts it back to automatic (null), not "music".
            await lib.setIsBook([track.id], true);
            messenger?.showSnackBar(SnackBar(
              content: Text('"${track.title}" moved to Books'),
              action: SnackBarAction(label: 'Undo', onPressed: () => lib.setIsBook([track.id], null)),
            ));
          },
          child: _row(Icons.menu_book_outlined, 'Move to Books'),
        ),
        if (!closeRouteFirst) // selecting only makes sense in song lists
          PopupMenuItem(
            value: () => context.read<SelectionModel>().toggle(track.id),
            child: _row(Icons.check_box_outlined, 'Select'),
          ),
        if (extraAction != null) ...[const PopupMenuDivider(), extraAction!],
      ],
    );
  }

  /// Icon + text for a menu item.
  static Widget _row(IconData i, String s) => Row(children: [Icon(i, size: 20), const SizedBox(width: 12), Text(s)]);
}

/// Bottom sheet listing playlists (plus "New playlist").
Future<void> showAddToPlaylist(BuildContext context, List<Track> tracks) async {
  final model = context.read<PlaylistsModel>();
  // Grab the messenger now; the sheet closing may leave `context` unusable later.
  final messenger = ScaffoldMessenger.maybeOf(context);
  // The sheet returns the chosen (or newly made) playlist, or null if dismissed.
  final Playlist? chosen = await showModalBottomSheet<Playlist>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('New playlist'),
          onTap: () async {
            final name = await askForName(ctx, title: 'New playlist');
            if (name != null && ctx.mounted) Navigator.pop(ctx, model.create(name));
          },
        ),
        for (final p in model.playlists)
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: Text(p.name),
            subtitle: Text('${p.trackIds.length} songs'),
            onTap: () => Navigator.pop(ctx, p),
          ),
      ]),
    ),
  );
  if (chosen == null) return;
  // addTracks skips songs already in the playlist and returns how many were really added.
  final n = model.addTracks(chosen, tracks);
  messenger?.showSnackBar(SnackBar(
    content: Text(n == 0 ? 'Already in ${chosen.name}' : 'Added to ${chosen.name}'),
    duration: const Duration(seconds: 2),
  ));
}

/// Simple text prompt dialog. Returns the trimmed name, or null if cancelled/empty.
Future<String?> askForName(BuildContext context, {required String title, String initial = ''}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: initial),
  );
}

/// The dialog behind [askForName]. Stateful only so the text controller can be disposed.
class _NameDialog extends StatefulWidget {
  final String title;
  final String initial;
  const _NameDialog({required this.title, required this.initial});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    Navigator.pop(context, v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
