import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../state/library_model.dart';
import '../state/play_queue.dart';
import '../state/player_model.dart';

/// Connects HomeTunes' player to the operating system's media controls:
///
/// * **Android** – media notification, lock-screen controls, Bluetooth/headset
///   buttons, and a foreground service so playback isn't killed in the background.
/// * **Windows** – media keys and the volume/media overlay (System Media
///   Transport Controls), via the `audio_service_win` plugin.
///
/// It doesn't play audio itself: it mirrors [PlayerModel]'s state out to the
/// system, and forwards button presses from the system back to [PlayerModel].
class MediaSession extends BaseAudioHandler with SeekHandler {
  final PlayerModel player;
  final LibraryModel library;

  String? _shownItemId;
  Duration? _shownDuration;

  /// Set when the system asked us to stop (e.g. the notification was swiped
  /// away while paused). Keeps the session idle until music plays again.
  bool _stopped = false;

  MediaSession(this.player, this.library) {
    player.addListener(_sync);
    _sync();
  }

  /// Starts the media session on platforms that support it. Returns null (and
  /// the app carries on without system controls) if it isn't available.
  static Future<MediaSession?> start(PlayerModel player, LibraryModel library) async {
    if (!(Platform.isAndroid || Platform.isWindows)) return null;
    try {
      return await AudioService.init(
        builder: () => MediaSession(player, library),
        config: const AudioServiceConfig(
          // Also required by the Windows implementation.
          androidNotificationChannelId: 'com.hometunes.hometunes.channel.audio',
          androidNotificationChannelName: 'Music playback',
          // While playing the notification can't be swiped away; once paused it can.
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('HomeTunes: media controls unavailable: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------- app → system

  void _sync() {
    final t = player.current;
    if (player.playing) _stopped = false;

    if (t == null || _stopped) {
      if (t == null && _shownItemId != null) {
        _shownItemId = null;
        mediaItem.add(null);
      }
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ));
      return;
    }

    final duration = player.duration > Duration.zero ? player.duration : t.duration;
    if (t.id != _shownItemId || duration != _shownDuration) {
      _shownItemId = t.id;
      _shownDuration = duration;
      mediaItem.add(MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: duration,
        artUri: library.artUriFor(t),
      ));
    }

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      processingState: player.buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
      playing: player.playing,
      updatePosition: player.position,
      queueIndex: player.queue.position,
      repeatMode: switch (player.repeat) {
        RepeatSetting.off => AudioServiceRepeatMode.none,
        RepeatSetting.all => AudioServiceRepeatMode.all,
        RepeatSetting.one => AudioServiceRepeatMode.one,
      },
      shuffleMode: player.shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    ));
  }

  // ---------------------------------------------------------------- system → app

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() async {
    await player.pause();
    _stopped = true;
    _sync();
  }

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.previous();

  @override
  Future<void> seek(Duration position) => player.seek(position);
}
