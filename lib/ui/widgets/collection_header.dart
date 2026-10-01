// The big header at the top of album, artist and playlist pages: cover, "ALBUM"-style label,
// title, subtitle, and Play / Shuffle buttons (plus any extra buttons the page adds).
//
// On wide windows it's laid out side by side (cover left, text right); on phones everything is
// stacked and centred. The background fades from the accent colour into the page colour.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/player_model.dart';
import '../theme.dart';
import 'selectable_title.dart';

/// Big header used on album, artist and playlist pages, with Play / Shuffle.
class CollectionHeader extends StatelessWidget {
  final Widget art;
  final String kind; // "Album", "Playlist", "Artist"
  final String title;
  final String subtitle;
  /// The songs Play / Shuffle will play, in order.
  final List<Track> tracks;
  /// Where the music is playing from, e.g. the album name (shown in the player).
  final String contextLabel;
  /// More buttons after Shuffle (like, edit, menu…), supplied by the page.
  final List<Widget> extraActions;

  const CollectionHeader({
    super.key,
    required this.art,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.tracks,
    required this.contextLabel,
    this.extraActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerModel>();
    final wide = MediaQuery.sizeOf(context).width > 600;
    final artSize = wide ? 200.0 : 180.0;

    // The text block: kind, title, subtitle.
    final info = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(kind.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: AppColors.textDim)),
        const SizedBox(height: 6),
        SelectableTitle(title,
            textAlign: wide ? TextAlign.start : TextAlign.center,
            maxLines: 2,
            style: TextStyle(fontSize: wide ? 40 : 26, fontWeight: FontWeight.w800, height: 1.1)),
        const SizedBox(height: 8),
        Text(subtitle, style: TextStyle(color: AppColors.textDim)),
      ],
    );

    // Play and Shuffle (greyed out when there's nothing to play), then the page's own buttons.
    final actions = Row(
      mainAxisAlignment: wide ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: [
        IconButton.filled(
          iconSize: 32,
          tooltip: 'Play',
          icon: const Icon(Icons.play_arrow_rounded),
          onPressed: tracks.isEmpty ? null : () => player.playTracks(tracks, shuffle: false, label: contextLabel),
        ),
        const SizedBox(width: 8),
        IconButton(
          iconSize: 28,
          tooltip: 'Shuffle play',
          icon: const Icon(Icons.shuffle),
          onPressed: tracks.isEmpty ? null : () => player.shufflePlay(tracks, label: contextLabel),
        ),
        ...extraActions,
      ],
    );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Theme.of(context).colorScheme.primary.withValues(alpha: 0.22), AppColors.bg],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      // Wide: cover and text side by side, buttons below. Phone: everything in one centred column.
      child: wide
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(width: artSize, height: artSize, child: art),
                const SizedBox(width: 24),
                Expanded(child: info),
              ]),
              const SizedBox(height: 16),
              actions,
            ])
          : Column(children: [
              SizedBox(width: artSize, height: artSize, child: art),
              const SizedBox(height: 16),
              info,
              const SizedBox(height: 12),
              actions,
            ]),
    );
  }
}
