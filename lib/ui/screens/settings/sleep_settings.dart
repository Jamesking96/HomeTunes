// Settings › Sleep timer: whether the moon button shows, how long the timer runs for music and
// for books, and how long the fade-out lasts. Kept on its own page (not under Audiobooks)
// because it applies to music too. The timer itself is SleepTimer in the state folder.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/library_model.dart';
import 'settings_widgets.dart';

/// Settings › Sleep timer: for music and audiobooks.
class SleepTimerSettings extends StatelessWidget {
  const SleepTimerSettings({super.key});

  // Choices in minutes. The last one, sleepAtEnd, is a special value meaning "end of the song"
  // for music or "end of the chapter" for books.
  static const _lengths = [5, 10, 15, 20, 30, 45, 60, 90, 120, LibraryModel.sleepAtEnd];

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    return SettingsPageList(
      intro: 'The sleep timer pauses playback after a while, fading the volume out first. '
          'Music and audiobooks each have their own timer length.',
      children: [
        SettingTarget(
          'sleep-button',
          child: SwitchListTile(
            title: const Text('Show sleep timer button'),
            subtitle: const Text('The moon beside play/pause: tap once to start the timer, again to stop it'),
            value: lib.sleepButtonShown,
            onChanged: (v) => lib.updateListeningSettings(sleepButtonShown: v),
          ),
        ),
        const SettingsGroupTitle('Timer length'),
        SettingTarget(
          'sleep-music',
          child: ChoiceTile<int>(
            title: 'Timer length for music',
            value: lib.sleepMusicMinutes,
            options: _lengths,
            label: (v) => v == LibraryModel.sleepAtEnd ? 'End of song' : '$v minutes',
            onChanged: (v) => lib.updateListeningSettings(sleepMusicMinutes: v),
          ),
        ),
        SettingTarget(
          'sleep-books',
          child: ChoiceTile<int>(
            title: 'Timer length for books',
            value: lib.sleepBookMinutes,
            options: _lengths,
            label: (v) => v == LibraryModel.sleepAtEnd ? 'End of chapter' : '$v minutes',
            onChanged: (v) => lib.updateListeningSettings(sleepBookMinutes: v),
          ),
        ),
        const SettingsGroupTitle('When the timer ends'),
        SettingTarget(
          'sleep-fade',
          child: ChoiceTile<int>(
            title: 'Fade out before pausing',
            value: lib.sleepFadeSeconds,
            options: const [0, 5, 10, 30],
            label: (v) => v == 0 ? 'Off' : '$v seconds',
            onChanged: (v) => lib.updateListeningSettings(sleepFadeSeconds: v),
          ),
        ),
      ],
    );
  }
}
