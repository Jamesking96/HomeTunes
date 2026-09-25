// The bridge between the player and the phone's / PC's own media controls.
// main() calls MediaSession.start once, after the PlayerModel exists. From then on the session
// listens to the player and copies its state out (what's playing, playing/paused, position),
// and turns button presses from the notification, lock screen, headset or keyboard media keys
// into player calls. For audiobooks the buttons skip back/forward by seconds instead.
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

  /// What the system is currently showing, so we only send changes.
  MediaItem? _shownItem;

  /// Set when the system asked us to stop (e.g. the notification was swiped
  /// away while paused). Keeps the session idle until music plays again.
  bool _stopped = false;

  /// Chapter last shown, so the title follows the book as it plays.
  int _shownChapter = -1;

  MediaSession(this.player, this.library) {
    player.addListener(_sync);
    // Lives as long as the app, like the session itself.
    // The player doesn't notify on every position change, so watch the position too, just to
    // spot a new chapter starting in a book and update the title shown.
    player.positionStream.listen((_) {
      if (player.inBook && player.currentChapterIndex != _shownChapter) _sync();
    });
    _sync();
  }

  /// Starts the media session on platforms that support it. Returns null (and
  /// the app carries on without system controls) if it isn't available.
  static Future<MediaSession?> start(PlayerModel player, LibraryModel library) async {
    if (!(Platform.isAndroid || Platform.isWindows)) return null;  // e.g. Linux while developing
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

  /// Sends the player's current state to the system controls.
  void _sync() {
    final t = player.current;
    if (player.playing) _stopped = false;

    // Nothing to show (or told to stop): show an idle, paused session.
    if (t == null || _stopped) {
      if (t == null && _shownItem != null) {
        _shownItem = null;
        mediaItem.add(null);
      }
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ));
      return;
    }

    final duration = player.duration > Duration.zero ? player.duration : t.duration;  // engine first
    final book = player.book;
    _shownChapter = player.currentChapterIndex;
    final item = MediaItem(
      id: t.id,
      // Books show the chapter, the author and the book's title.
      title: book != null ? (player.currentChapter?.title ?? t.title) : t.title,
      artist: book != null ? book.author : t.artist,
      album: book != null ? book.title : t.album,
      duration: duration,
      artUri: library.artUriFor(t),
    );
    // Only resend when something visible changed (new song, or its details edited).
    final old = _shownItem;
    if (old == null ||
        old.id != item.id ||
        old.title != item.title ||
        old.artist != item.artist ||
        old.album != item.album ||
        old.duration != item.duration ||
        old.artUri != item.artUri) {
      _shownItem = item;
      mediaItem.add(item);
    }

    playbackState.add(PlaybackState(
      // Books: skip back / forward by seconds instead of changing file.
      controls: book != null
          ? [
              MediaControl.rewind,
              player.playing ? MediaControl.pause : MediaControl.play,
              MediaControl.fastForward,
            ]
          : [
              MediaControl.skipToPrevious,
              player.playing ? MediaControl.pause : MediaControl.play,
              MediaControl.skipToNext,
            ],
      androidCompactActionIndices: const [0, 1, 2],  // all three in the small notification
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

  // Next / previous (headset buttons, keyboard media keys, the Windows media
  // overlay) skip by seconds while a book plays.
  @override
  Future<void> skipToNext() => player.inBook ? player.skipForward() : player.next();

  @override
  Future<void> skipToPrevious() => player.inBook ? player.skipBack() : player.previous();

  @override
  Future<void> fastForward() => player.skipForward();

  @override
  Future<void> rewind() => player.skipBack();

  @override
  Future<void> seek(Duration position) => player.seek(position);
}
