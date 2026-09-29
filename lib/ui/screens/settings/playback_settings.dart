// Settings › Playback: gapless playback on/off and ReplayGain (even out volume).
//
// Both are saved in LibraryModel; PlayerModel reads them from there and passes them to mpv
// (gapless-audio / prefetch-playlist / replaygain properties), only when they change.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/equalizer_model.dart';
import '../../../state/library_model.dart';
import '../equalizer_screen.dart';
import '../../theme.dart';
import 'settings_widgets.dart';

/// Settings › Playback: how songs sound and join up.
class PlaybackSettings extends StatelessWidget {
  const PlaybackSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final eq = context.watch<EqualizerModel>();
    return SettingsPageList(children: [
      const SettingsGroupTitle('Sound'),
      SettingTarget(
        'equaliser',
        child: ListTile(
          leading: const Icon(Icons.equalizer),
          title: const Text('Equaliser'),
          subtitle: Text(!eq.enabled
              ? 'Off'
              : eq.separateBooks
                  ? 'Music: ${eq.musicPreset.name} · Audiobooks: ${eq.bookPreset.name}'
                  : eq.musicPreset.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => openEqualizer(context),
        ),
      ),
      SettingTarget(
        'gapless',
        child: SwitchListTile(
          title: const Text('Gapless playback'),
          subtitle: const Text('Songs follow each other with no silence in between – live albums and mixes play '
              'straight through. Also joins up an audiobook\'s files.'),
          value: lib.gaplessPlayback,
          onChanged: (v) => lib.updatePlaybackSettings(gaplessPlayback: v),
        ),
      ),
      SettingTarget(
        'swipe-to-skip',
        child: SwitchListTile(
          title: const Text('Swipe gestures'),
          subtitle: const Text('On a touch screen, swipe the player left or right to go to the next or previous song. '
              'In an audiobook it skips forward or back by the lengths set under Audiobooks.'),
          value: lib.swipeToSkip,
          onChanged: (v) => lib.updatePlaybackSettings(swipeToSkip: v),
        ),
      ),
      SettingTarget(
        'replaygain',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ChoiceTile<ReplayGainMode>(
            title: 'Even out volume (ReplayGain)',
            subtitle: 'Uses the loudness info many music files carry, so quiet and loud songs play at a similar level',
            value: lib.replayGain,
            options: ReplayGainMode.values,
            label: (m) => switch (m) {
              ReplayGainMode.off => 'Off',
              ReplayGainMode.track => 'By song',
              ReplayGainMode.album => 'By album',
            },
            onChanged: (m) => lib.updatePlaybackSettings(replayGain: m),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '"By album" keeps an album\'s own quiet and loud moments; "By song" makes every song about as loud as '
              'the next. Files without loudness info play as they are.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
        ]),
      ),
    ]);
  }
}
