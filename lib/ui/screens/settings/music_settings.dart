// Settings › Music (0.1.40): general settings for listening to music — for now its music videos:
// whether Now Playing shows them at all, and whether they start by themselves or wait for the
// video button. (How songs sound — equaliser, gapless, ReplayGain — stays under Playback.)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/music_permission.dart';
import '../../../state/library_model.dart';
import '../../theme.dart';
import 'settings_widgets.dart';

/// Settings › Music.
class MusicSettings extends StatelessWidget {
  const MusicSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    return SettingsPageList(children: [
      const SettingsGroupTitle('Music videos', 'A video beside a song with the same name (like Song.m4a and Song.mp4)'),
      // 0.1.40: a song with a video file of the same name beside it, or an .mp4 song with
      // pictures, can show the video on Now Playing, muted and in step with the song.
      SettingTarget(
        'music-videos',
        child: SwitchListTile(
          title: const Text('Show music videos'),
          subtitle: const Text('Play the video on Now Playing in place of the cover, in time with the song. '
              'Off: songs always show their cover, and there\'s no video button.'),
          value: lib.showMusicVideos,
          onChanged: (v) => lib.updatePlaybackSettings(showMusicVideos: v),
        ),
      ),
      SettingTarget(
        'music-video-autoplay',
        child: SwitchListTile(
          key: const ValueKey('music-video-autoplay'),
          title: const Text('Play music videos automatically'),
          subtitle: Text(lib.autoPlayMusicVideos
              ? 'The video starts as soon as a song that has one plays.'
              : 'The cover shows first; press the video button on Now Playing to watch the video.'),
          value: lib.autoPlayMusicVideos,
          onChanged: lib.showMusicVideos ? (v) => lib.updatePlaybackSettings(autoPlayMusicVideos: v) : null,
        ),
      ),
      if (Platform.isAndroid && lib.showMusicVideos) const VideoAccessNote(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Text(
          'Either way, the video button on Now Playing switches between the video and the cover for the song '
          'that\'s playing.',
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      ),
    ]);
  }
}

/// Android 13+: music videos need "Photos and videos" access (with only "Music and audio", the
/// video files beside songs aren't even listed). Shows a button to allow it when it's missing.
class VideoAccessNote extends StatefulWidget {
  const VideoAccessNote({super.key});

  @override
  State<VideoAccessNote> createState() => _VideoAccessNoteState();
}

class _VideoAccessNoteState extends State<VideoAccessNote> {
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
