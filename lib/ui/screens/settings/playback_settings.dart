// Settings › Playback: gapless playback on/off, ReplayGain (even out volume) and, since 0.1.61,
// the volume boost (louder than 100 %, up to 500 %, off by default).
//
// All are saved in LibraryModel; PlayerModel reads them from there and passes them to mpv
// (gapless-audio / prefetch-playlist / replaygain properties, volume), only when they change.
// The video page reads the boost too (models/volume_boost.dart).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/volume_boost.dart';
import '../../../state/equalizer_model.dart';
import '../../../state/library_model.dart';
import '../../../state/play_history.dart';
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
    final history = Provider.of<PlayHistory?>(context);
    final played = history?.items.length ?? 0;
    return SettingsPageList(
      children: [
        const SettingsGroupTitle('Sound'),
        SettingTarget(
          'equaliser',
          child: ListTile(
            leading: const Icon(Icons.equalizer),
            title: const Text('Equaliser'),
            subtitle: Text(
              !eq.enabled
                  ? 'Off'
                  : eq.separateBooks
                  ? 'Music: ${eq.musicPreset.name} · Audiobooks: ${eq.bookPreset.name}'
                  : eq.musicPreset.name,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openEqualizer(context),
          ),
        ),
        SettingTarget(
          'gapless',
          child: SwitchListTile(
            title: const Text('Gapless playback'),
            subtitle: const Text(
              'Songs follow each other with no silence in between – live albums and mixes play '
              'straight through. Also joins up an audiobook\'s files.',
            ),
            value: lib.gaplessPlayback,
            onChanged: (v) => lib.updatePlaybackSettings(gaplessPlayback: v),
          ),
        ),
        SettingTarget(
          'swipe-to-skip',
          child: SwitchListTile(
            title: const Text('Swipe gestures'),
            subtitle: const Text(
              'On a touch screen, swipe the player left or right to go to the next or previous song. '
              'In an audiobook it skips forward or back by the lengths set under Audiobooks.',
            ),
            value: lib.swipeToSkip,
            onChanged: (v) => lib.updatePlaybackSettings(swipeToSkip: v),
          ),
        ),
        // Music videos moved to Settings › Music (0.1.40).
        SettingTarget(
          'replaygain',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChoiceTile<ReplayGainMode>(
                title: 'Even out volume (ReplayGain)',
                subtitle:
                    'Uses the loudness info many music files carry, so quiet and loud songs play at a similar level',
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
            ],
          ),
        ),
        // Volume boost (0.1.61): louder than 100 %, like VLC (models/volume_boost.dart). Since
        // 0.1.62 the slider here only sets how far the volume sliders go.
        SettingTarget(
          'volume-boost',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              key: const ValueKey('volume-boost-switch'),
              title: const Text('Volume boost'),
              subtitle: Text(lib.volumeBoost
                  ? 'Every volume slider now goes up to ${lib.volumeBoostPercent}%. Past 100% is louder than normal.'
                  : 'Let the volume sliders go past 100%, up to 500% (like VLC). Off: they stop at 100%.'),
              value: lib.volumeBoost,
              onChanged: (v) => lib.setVolumeBoost(on: v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(children: [
                Text('100%', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                Expanded(
                  child: Slider(
                    key: const ValueKey('volume-boost-amount'),
                    value: lib.volumeBoostPercent.toDouble(),
                    min: volumeBoostMin.toDouble(),
                    max: volumeBoostMax.toDouble(),
                    divisions: (volumeBoostMax - volumeBoostMin) ~/ volumeBoostStep,
                    label: '${lib.volumeBoostPercent}%',
                    onChanged: lib.volumeBoost ? (v) => lib.setVolumeBoost(percent: v.round()) : null,
                  ),
                ),
                Text('500%', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Loudest the sliders go: ${lib.volumeBoostPercent}%. You choose how loud with the volume '
                'sliders as usual. Very high volumes can make loud parts crackle, as in VLC; turn it down if '
                'they do. Mind your ears and speakers.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ),
          ]),
        ),
        // The "65%" bubble over the volume sliders while they change (0.1.65).
        SettingTarget(
          'volume-percent',
          child: SwitchListTile(
            key: const ValueKey('volume-percent-switch'),
            title: const Text('Show the volume percentage'),
            subtitle: const Text('While you change the volume, a small bubble above the slider shows how loud, '
                'e.g. 65%.'),
            value: lib.showVolumePercent,
            onChanged: lib.setShowVolumePercent,
          ),
        ),
        // Home's "Jump back in" (0.1.45): what's been played recently.
        const SettingsGroupTitle('Recently played'),
        SettingTarget(
          'recently-played',
          child: ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Forget recently played music'),
            subtitle: Text(
              played == 0
                  ? 'Nothing played yet. Home\'s "Jump back in" shows the albums, playlists and artists you play.'
                  : '$played albums, playlists and artists shown in Home\'s "Jump back in". '
                        'Videos and audiobooks you\'re part-way through stay.',
            ),
            trailing: TextButton(onPressed: played == 0 ? null : history?.clear, child: const Text('Forget')),
          ),
        ),
      ],
    );
  }
}
