// Shared playlists (Profiles, phase 4; the user's decision 2: "playlists are each person's own,
// with a sharing switch; the owner chooses: play it, or play and change it").
//
// The owner picks Not shared / Others can play it / Others can play and change it here (a
// dialog, or the options panel on a TV). Everyone else sees the playlist in their Playlists with
// "From <name>"; PlaylistsModel keeps what they may do.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../state/playlists_model.dart';
import '../tv/tv_focus.dart' show tvModeOf;
import '../tv/tv_options.dart';

/// The line that says whose a shared playlist is and what you can do with it.
String sharedByLine(Playlist p) => [
      'From ${p.ownerName ?? 'someone else'}',
      p.canChangeSongs ? 'you can add and move songs' : 'you can play it',
    ].join(' · ');

/// A short tag for lists ("From Sam"), or null for your own.
String? sharedTag(Playlist p) => p.isMine ? null : 'From ${p.ownerName ?? 'someone else'}';

/// The owner chooses what the other profiles may do with [playlist].
Future<void> showPlaylistSharing(BuildContext context, Playlist playlist) async {
  final model = context.read<PlaylistsModel>();
  if (!playlist.isMine) return;
  if (tvModeOf(context)) {
    await showTvOptions(
      context,
      title: 'Share "${playlist.name}"',
      subtitle: 'Who else can use it on this device',
      focusIndex: PlaylistSharing.values.indexOf(playlist.sharing),
      options: [
        for (final s in PlaylistSharing.values)
          TvOption(
            s.label,
            s == playlist.sharing ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            () => model.setSharing(playlist, s),
            subtitle: s == playlist.sharing ? 'Chosen now · ${s.detail}' : s.detail,
          ),
      ],
    );
    return;
  }
  final chosen = await showDialog<PlaylistSharing>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Share "${playlist.name}"'),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('Choose what everyone else on this device can do with it. '
              'Only you can rename it, change its picture or delete it.'),
        ),
        RadioGroup<PlaylistSharing>(
          groupValue: playlist.sharing,
          onChanged: (s) => Navigator.pop(ctx, s),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final s in PlaylistSharing.values)
              RadioListTile<PlaylistSharing>(
                key: ValueKey('sharing-${s.name}'),
                value: s,
                title: Text(s.label),
                subtitle: Text(s.detail),
              ),
          ]),
        ),
      ],
    ),
  );
  if (chosen != null) model.setSharing(playlist, chosen);
}
