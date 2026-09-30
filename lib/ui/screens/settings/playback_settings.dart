// Settings › Playback: gapless playback on/off and ReplayGain (even out volume).
//
// Both are saved in LibraryModel; PlayerModel reads them from there and passes them to mpv
// (gapless-audio / prefetch-playlist / replaygain properties), only when they change.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/music_permission.dart';
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
      // 0.1.32: a song with a video file of the same name beside it (Song.m4a + Song.mp4), or an
      // .mp4 song with pictures, shows the video on Now Playing, muted and in step with the song.
      SettingTarget(
        'music-videos',
        child: SwitchListTile(
          title: const Text('Music videos'),
          subtitle: const Text('When a song has a video beside it with the same name (like Song.m4a and Song.mp4), '
              'play the video on Now Playing in place of the cover, in time with the song. '
              'The video button on Now Playing switches this too.'),
          value: lib.showMusicVideos,
          onChanged: (v) => lib.updatePlaybackSettings(showMusicVideos: v),
        ),
      ),
      if (Platform.isAndroid && lib.showMusicVideos) const _VideoAccessNote(),
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

/// Android 13+: music videos need "Photos and videos" access (with only "Music and audio", the
/// video files beside songs aren't even listed). Shows a button to allow it when it's missing.
class _VideoAccessNote extends StatefulWidget {
  const _VideoAccessNote();

  @override
  State<_VideoAccessNote> createState() => _VideoAccessNoteState();
}

class _VideoAccessNoteState extends State<_VideoAccessNote> {
  MusicAccess? _access;

  @override
  void initState() {
    super.initState();
    MusicPermission.checkVideos().then((a) {
      if (mounted) setState(() => _access = a);
    });
  }

  Future<void> _allow() async {
    final lib = context.read<LibraryModel>();
    final a = await MusicPermission.requestVideos();
    if (!mounted) return;
    setState(() => _access = a);
    if (a == MusicAccess.allowed) {
      await lib.scanLocal(); // finds the videos beside songs now
    } else if (a == MusicAccess.blocked) {
      await MusicPermission.openSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_access == null || _access == MusicAccess.allowed) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('Music videos need "Photos and videos" access on this phone'),
      trailing: TextButton(onPressed: _allow, child: const Text('Allow')),
    );
  }
}
