// The video page's controls (media_kit's, in the chosen look, with our buttons and keys) and its
// Speed and Audio and subtitles dialogs. Part of video_player_screen.dart (refactor phase 6,
// 9 Oct 2026: moved here unchanged, as an extension on the page's state).
part of '../video_player_screen.dart';

extension _VideoPageControls on _VideoPageState {
  Future<void> _chooseSpeed(BuildContext from) async {
    final collection = context.read<VideoLibraryModel>().byId(_session.id)?.collection;
    final speed = _session.speed;
    final picked = await showDialog<double>(
      context: from,
      useRootNavigator: true,
      builder: (context) => SimpleDialog(
        title: const Text('Speed'),
        children: [
          for (final s in PlayerModel.speeds)
            SimpleDialogOption(
              key: ValueKey('speed-$s'),
              onPressed: () => Navigator.of(context).pop(s),
              child: Row(children: [
                Icon(s == speed ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 20, color: s == speed ? Theme.of(context).colorScheme.primary : null),
                const SizedBox(width: 12),
                Text(SpeedButton.label(s)),
              ]),
            ),
          if (collection != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text('Used for the rest of "$collection" too.', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ),
        ],
      ),
    );
    if (picked != null) await _session.setSpeed(picked);
  }

  /// The frame on screen now becomes the video's picture.
  Future<void> _useThisFrame(VideoItem v) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final videos = context.read<VideoLibraryModel>();
    try {
      final shot = await _engine.screenshot();
      if (shot == null) throw const FormatException('No picture came from the video yet');
      await videos.setPicture(v, await preparePicture(shot));
      messenger?.showSnackBar(const SnackBar(content: Text('This frame is now its picture')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t use this frame: ${e is FormatException ? e.message : e}')));
    }
  }

  Future<void> _chooseTracks(BuildContext from) async {
    await showDialog<void>(
      context: from,
      useRootNavigator: true,
      builder: (_) => StatefulBuilder(builder: (context, setDialog) {
        final audio = [for (final t in _session.audioTracks) if (t.isReal) t];
        final subs = [for (final t in _session.subtitleTracks) if (t.isReal) t];
        final collection = context.read<VideoLibraryModel>().byId(_session.id)?.collection;
        Future<void> pickAudio(MediaTrack? t) async {
          await _session.chooseAudio(t);
          setDialog(() {});
        }

        Future<void> pickSub(MediaTrack? t) async {
          await _session.chooseSubtitles(t);
          setDialog(() {});
        }

        Widget option(String label, bool selected, VoidCallback onTap, {Key? key}) => ListTile(
              key: key,
              dense: true,
              leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? Theme.of(context).colorScheme.primary : null),
              title: Text(label),
              onTap: onTap,
            );

        final aid = _session.aid, sid = _session.sid;
        return AlertDialog(
          title: const Text('Audio and subtitles'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Audio', style: TextStyle(fontWeight: FontWeight.w700)),
                for (var i = 0; i < audio.length; i++)
                  option(trackLabel('audio', audio[i], i + 1), aid == audio[i].id, () => pickAudio(audio[i]),
                      key: ValueKey('audio-${audio[i].id}')),
                option('Off (no sound)', aid == 'no', () => pickAudio(null), key: const ValueKey('audio-off')),
                const SizedBox(height: 12),
                const Text('Subtitles', style: TextStyle(fontWeight: FontWeight.w700)),
                option('Off', sid == 'no', () => pickSub(null), key: const ValueKey('subtitles-off')),
                for (var i = 0; i < subs.length; i++)
                  option(trackLabel('subtitles', subs[i], i + 1), sid == subs[i].id, () => pickSub(subs[i]),
                      key: ValueKey('subtitles-${subs[i].id}')),
                if (subs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text('This video has no subtitles.', style: TextStyle(color: AppColors.textDim)),
                  ),
                if (collection != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Your choice is used for the rest of "$collection" too.',
                        style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
        );
      }),
    );
  }

  /// The video with its controls, plus the Audio and subtitles button (in full screen too).
  Widget _videoWidget() {
    final player = _engine.player;
    final tracksButton = Builder(
      builder: (context) => MaterialDesktopCustomButton(
        icon: const Icon(Icons.subtitles_outlined),
        onPressed: () => _chooseTracks(context),
      ),
    );
    // Skip buttons and speed (Settings › Videos sets how far the skips go).
    final back = _settings.videoSkipBackSeconds, ahead = _settings.videoSkipForwardSeconds;
    // Colours, sizes and the backing behind each button (Settings › Appearance › Video player).
    final look = _settings.videoPlayerLook, accent = AppColors.accent;
    final speedButton = Builder(
      builder: (context) => MaterialDesktopCustomButton(icon: const Icon(Icons.speed), onPressed: () => _chooseSpeed(context)),
    );
    // Previous / next video in the collection (30 Sep); greyed out at either end. Worked out from
    // the video on screen each time it changes, and again when pressed (0.1.71): full screen keeps
    // these controls from when it opened, so nothing here may hold on to one video.
    final buttonColour = look.buttons(accent);
    Widget jump({required bool forward, required double size}) => ValueListenableBuilder<String>(
          valueListenable: _session.shownId,
          builder: (context, id, _) {
            final target = _session.neighbour(id, forward: forward);
            return IconButton(
              key: ValueKey(forward ? 'video-next' : 'video-previous'),
              tooltip: target == null
                  ? (forward ? 'No next video' : 'No previous video')
                  : '${forward ? 'Next' : 'Previous'}: ${[?target.episodeLabel, target.title].join(' · ')}',
              iconSize: size,
              color: buttonColour,
              disabledColor: buttonColour.withValues(alpha: 0.3),
              icon: Icon(forward ? Icons.skip_next_rounded : Icons.skip_previous_rounded),
              onPressed: target == null ? null : () => _session.jump(forward: forward),
            );
          },
        );

    final desktopBar = [
      jump(forward: false, size: look.size.desktop),
      MaterialDesktopCustomButton(
          icon: Icon(_VideoPageState.skipIcon(forward: false, seconds: back)), onPressed: () => _session.skip(forward: false)),
      const MaterialDesktopPlayOrPauseButton(),
      MaterialDesktopCustomButton(
          icon: Icon(_VideoPageState.skipIcon(forward: true, seconds: ahead)), onPressed: () => _session.skip(forward: true)),
      jump(forward: true, size: look.size.desktop),
      // 0.1.62: our own volume (media_kit's stops at 100), up to the volume boost's top.
      _VideoBarVolume(player: player, maxVolume: () => _settings.maxVolume, look: look, accent: accent),
      paddedTime(MaterialDesktopPositionIndicator(style: timeTextStyle(look, accent))),
      const Spacer(),
      // The sleep timer (0.1.63).
      VideoSleepTimerButton(iconSize: look.size.desktop, color: look.buttons(accent)),
      speedButton,
      tracksButton,
      const MaterialDesktopFullscreenButton(),
    ];
    // Keys: as media_kit's, but ← → and J / L skip by the chosen amounts.
    final keys = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.mediaPlay): _engine.play,
      const SingleActivator(LogicalKeyboardKey.mediaPause): _engine.pause,
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): _engine.playOrPause,
      const SingleActivator(LogicalKeyboardKey.space): _engine.playOrPause,
      const SingleActivator(LogicalKeyboardKey.keyK): _engine.playOrPause,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _session.skip(forward: false),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => _session.skip(forward: true),
      const SingleActivator(LogicalKeyboardKey.keyJ): () => _session.skip(forward: false),
      const SingleActivator(LogicalKeyboardKey.keyL): () => _session.skip(forward: true),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _session.stepVolume(5),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _session.stepVolume(-5),
      // Shift+N / Shift+P: next / previous video (as on YouTube).
      // (Worked out when pressed, 0.1.71: full screen keeps these keys from when it opened.)
      const SingleActivator(LogicalKeyboardKey.keyN, shift: true): () => _session.jump(forward: true),
      const SingleActivator(LogicalKeyboardKey.keyP, shift: true): () => _session.jump(forward: false),
      const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () => _session.jump(forward: true),
      const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () => _session.jump(forward: false),
      const SingleActivator(LogicalKeyboardKey.keyF): () => _videoKey.currentState?.toggleFullscreen(),
      const SingleActivator(LogicalKeyboardKey.escape): () => _videoKey.currentState?.exitFullscreen(),
    };
    final phoneTracks = Builder(
      builder: (context) => MaterialCustomButton(
        icon: const Icon(Icons.subtitles_outlined),
        onPressed: () => _chooseTracks(context),
      ),
    );
    final phoneSpeed = Builder(
      builder: (context) => MaterialCustomButton(icon: const Icon(Icons.speed), onPressed: () => _chooseSpeed(context)),
    );
    final phoneBar = [
      jump(forward: false, size: look.size.phone),
      MaterialCustomButton(
          icon: Icon(_VideoPageState.skipIcon(forward: false, seconds: back)), onPressed: () => _session.skip(forward: false)),
      MaterialCustomButton(
          icon: Icon(_VideoPageState.skipIcon(forward: true, seconds: ahead)), onPressed: () => _session.skip(forward: true)),
      jump(forward: true, size: look.size.phone),
      paddedTime(MaterialPositionIndicator(style: timeTextStyle(look, accent, phone: true))),
      const Spacer(),
      VideoSleepTimerButton(iconSize: look.size.phone, color: look.buttons(accent)), // 0.1.63
      phoneSpeed,
      phoneTracks,
      const MaterialFullscreenButton(),
    ];
    // Full screen (0.1.59): a round "Leave full screen" button in the top corner, like the ones
    // on the picture in the page, shown and hidden with the other controls.
    final fullTop = <Widget>[
      // (No padding: media_kit gives the row its side margins, and a button bar's height.)
      Builder(
        builder: (context) => _OverlayButton(
          key: const ValueKey('video-leave-fullscreen'),
          icon: Icons.fullscreen_exit,
          tooltip: 'Leave full screen',
          onPressed: () => exitFullscreen(context),
        ),
      ),
      // And the "Always on top" pin in the other corner (0.1.60, the PC only).
      const Spacer(),
      const AlwaysOnTopButton(round: true),
    ];
    // Double-tap the left or right of the picture on a phone: skip by the chosen amounts too.
    MaterialVideoControlsThemeData phone({bool full = false}) => phoneControlsTheme(look, accent,
        bar: phoneBar,
        skipBack: Duration(seconds: back),
        skipForward: Duration(seconds: ahead),
        top: full ? fullTop : const []);
    MaterialDesktopVideoControlsThemeData desktop({bool full = false}) =>
        desktopControlsTheme(look, accent, bar: desktopBar, keys: keys, top: full ? fullTop : const []);
    return MaterialDesktopVideoControlsTheme(
      normal: desktop(),
      fullscreen: desktop(full: true),
      child: MaterialVideoControlsTheme(
        normal: phone(),
        fullscreen: phone(full: true),
        child: Video(
          key: _videoKey,
          controller: _controller,
          fill: Colors.black,
          // The mouse wheel: 5 s skips over the progress bar, volume elsewhere (30 Sep).
          controls: (state) => VideoWheel(
              player: player,
              look: look,
              maxVolume: () => _settings.maxVolume,
              child: AdaptiveVideoControls(state)),
          // With libass the engine draws the subtitles into the picture; the app's own text
          // subtitles would show them twice.
          subtitleViewConfiguration: SubtitleViewConfiguration(visible: Platform.isAndroid),
        ),
      ),
    );
  }
}
