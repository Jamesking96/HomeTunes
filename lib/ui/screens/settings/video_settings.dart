// Settings › Videos (0.1.32): like Settings › Audiobooks, for the Videos tab.
//   Watching: skip back / forward amounts (the player's buttons, ← → and J / L, double-tap on a
//             phone), the speed for collections that haven't had one chosen, rewinding a little
//             when carrying on, and a separate equaliser preset for videos.
//   Where your videos are: the video folders (the same list as Settings › Folders & scanning).
//   Your edits: whether edits are also saved into .nfo files beside the videos.
//   Look: the usual picture shape for videos and for collections (wide, tall or square); each
//         video or collection can have its own in Edit details / Edit collection.
// Settings are saved through LibraryModel (settings.json), EqualizerModel (equalizer.json) and
// VideoLibraryModel (videos.json).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/video_item.dart';
import '../../../state/equalizer_model.dart';
import '../../../state/library_model.dart';
import '../../../state/player_model.dart';
import '../../../state/video_library_model.dart';
import '../../theme.dart';
import '../../widgets/listening_controls.dart' show SpeedButton;
import '../../widgets/save_nfo.dart' show canSaveNfo;
import '../equalizer_screen.dart';
import 'library_settings.dart' show VideoFoldersSection;
import 'settings_widgets.dart';

class VideoSettings extends StatelessWidget {
  const VideoSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final eq = context.watch<EqualizerModel>();
    final videos = context.watch<VideoLibraryModel>();
    const skips = [5, 10, 15, 30, 45, 60];

    Widget shapes(String title, PictureShape value, ValueChanged<PictureShape> onChanged, String key) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<PictureShape>(
                key: ValueKey(key),
                segments: const [
                  ButtonSegment(value: PictureShape.wide, icon: Icon(Icons.crop_16_9), label: Text('Wide')),
                  ButtonSegment(value: PictureShape.tall, icon: Icon(Icons.crop_portrait), label: Text('Tall')),
                  ButtonSegment(value: PictureShape.square, icon: Icon(Icons.crop_square), label: Text('Square')),
                ],
                selected: {value},
                onSelectionChanged: (v) => onChanged(v.first),
              ),
            ),
          ],
        );

    return SettingsPageList(
      intro: 'How videos play on the Videos tab. Music and audiobooks have their own settings.',
      children: [
        // --- Watching ---
        const SettingsGroupTitle('Watching'),
        SettingTarget(
          'video-skip-back',
          child: ChoiceTile<int>(
            title: 'Skip back',
            subtitle: 'The player\'s back button, the ← and J keys, and a double-tap on the left on a phone',
            value: lib.videoSkipBackSeconds,
            options: skips,
            label: (v) => '$v seconds',
            onChanged: (v) => lib.updateVideoSettings(skipBackSeconds: v),
          ),
        ),
        SettingTarget(
          'video-skip-forward',
          child: ChoiceTile<int>(
            title: 'Skip forward',
            subtitle: 'The forward button, the → and L keys, and a double-tap on the right',
            value: lib.videoSkipForwardSeconds,
            options: skips,
            label: (v) => '$v seconds',
            onChanged: (v) => lib.updateVideoSettings(skipForwardSeconds: v),
          ),
        ),
        SettingTarget(
          'video-speed',
          child: ChoiceTile<double>(
            title: 'Speed',
            subtitle: 'Each collection remembers its own speed once you change it while watching',
            value: lib.defaultVideoSpeed,
            options: PlayerModel.speeds,
            label: SpeedButton.label,
            onChanged: (v) => lib.updateVideoSettings(defaultSpeed: v),
          ),
        ),
        SettingTarget(
          'video-rewind',
          child: SwitchListTile(
            title: const Text('Rewind a little when carrying on'),
            subtitle: const Text('A few seconds after a short pause, up to 30 seconds after a long break'),
            value: lib.videoRewindOnResume,
            onChanged: (v) => lib.updateVideoSettings(rewindOnResume: v),
          ),
        ),
        SettingTarget(
          'video-eq',
          child: SwitchListTile(
            title: const Text('Separate equaliser for videos'),
            subtitle: Text(eq.separateVideos
                ? 'Videos have their own preset (now ${eq.videoPreset.name}).'
                : 'Videos use the same equaliser preset as music.'),
            value: eq.separateVideos,
            onChanged: eq.setSeparateVideos,
            secondary: IconButton(
              tooltip: 'Open the equaliser',
              icon: const Icon(Icons.equalizer),
              onPressed: () => openEqualizer(context, forVideos: true),
            ),
          ),
        ),
        // --- Where your videos are ---
        const SettingsGroupTitle('Where your videos are'),
        // The same list as Settings › Folders & scanning.
        SettingTarget('video-folders', child: const VideoFoldersSection()),
        if (canSaveNfo)
          SettingTarget(
            'video-nfo',
            child: SwitchListTile(
              title: const Text('Also save edits into .nfo files'),
              subtitle: const Text(
                  'When you edit a video or a collection, its details are also written into small .nfo files beside '
                  'the videos, which Kodi, Jellyfin and Plex read too. The videos themselves aren\'t changed.'),
              value: videos.saveNfo,
              onChanged: videos.setSaveNfo,
            ),
          ),
        // --- Look ---
        const SettingsGroupTitle('Look'),
        SettingTarget(
          'video-shape',
          child: shapes('Video picture shape', lib.videoPictureShape, (s) => lib.updateVideoSettings(videoShape: s),
              'video-shape-choice'),
        ),
        SettingTarget(
          'collection-shape',
          child: shapes('Collection poster shape', lib.collectionPictureShape,
              (s) => lib.updateVideoSettings(collectionShape: s), 'collection-shape-choice'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text(
            'These are the usual shapes. Each video can have its own in Edit details, and each collection in Edit '
            'collection. Tall suits film and series posters.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
