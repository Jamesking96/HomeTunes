import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/library_model.dart';
import '../../theme.dart';
import 'settings_widgets.dart';

/// Settings › Playback: how songs sound and join up.
class PlaybackSettings extends StatelessWidget {
  const PlaybackSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    return SettingsPageList(children: [
      const SettingsGroupTitle('Sound'),
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
          const Padding(
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
