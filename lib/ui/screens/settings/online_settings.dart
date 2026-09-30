// Settings › Online lookups: three on/off switches for the only times HomeTunes goes online
// on its own (apart from a music server): covers and song details from MusicBrainz / Cover Art
// Archive, and lyrics from LRCLIB. Each switch saves straight to LibraryModel (settings.json).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/library_model.dart';
import 'settings_widgets.dart';

/// Settings › Online lookups: the switches for everything that looks things up online.
class OnlineLookupSettings extends StatelessWidget {
  const OnlineLookupSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    return SettingsPageList(
      intro: 'HomeTunes only goes online for these when they\'re switched on. Nothing about your files is '
          'sent apart from the names shown below.',
      children: [
      SettingTarget('online-covers', child: SwitchListTile(
        title: const Text('Find missing covers online'),
        subtitle: const Text(
          'Offer to look up album covers on MusicBrainz / Cover Art Archive when a song or album '
          'has an artist or album name. Only the artist, album and song names are sent.',
        ),
        value: lib.onlineCovers,
        onChanged: lib.setOnlineCovers,
      )),
      SettingTarget('online-details', child: SwitchListTile(
        title: const Text('Find missing song details online'),
        subtitle: const Text(
          'Offer to look up year, artist, album, album artist, genre and track numbers on MusicBrainz, '
          'from the edit screen and on album pages with missing details.',
        ),
        value: lib.onlineDetails,
        onChanged: lib.setOnlineDetails,
      )),
      SettingTarget('online-lyrics', child: SwitchListTile(
        title: const Text('Find lyrics online'),
        subtitle: const Text(
          'When you open the lyrics of a song that has none of its own, look them up on LRCLIB '
          '(lrclib.net). Only the title, artist, album and length are sent, and what\'s found is saved. '
          '"Find lyrics on LRCLIB" in a song\'s menu works either way.',
        ),
        value: lib.onlineLyrics,
        onChanged: lib.setOnlineLyrics,
      )),
      SettingTarget('online-video-art', child: SwitchListTile(
        title: const Text('Find video pictures online'),
        subtitle: const Text(
          'Offer "Search online" when changing a video\'s picture or a collection\'s poster: posters, '
          'stills and banners from TVmaze, AniList and Wikipedia. Only the name you search for (and a '
          'season and episode number) is sent, and only when you search.',
        ),
        value: lib.onlineVideoArt,
        onChanged: lib.setOnlineVideoArt,
      )),
      ],
    );
  }
}
