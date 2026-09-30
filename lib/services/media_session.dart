// The bridge between the player and the phone's / PC's own media controls.
// main() calls MediaSession.start once, after the PlayerModel exists. From then on the session
// listens to the player and copies its state out (what's playing, playing/paused, position),
// and turns button presses from the notification, lock screen, headset or keyboard media keys
// into player calls. For audiobooks the buttons skip back/forward by seconds instead.
import 'dart:io';

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../state/library_model.dart';
import '../state/now_watching.dart';
import '../state/play_queue.dart';
import '../state/playback_guard.dart';
import '../state/player_model.dart';
import 'playback_log.dart';

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

  /// Keeps "playing" shown through the moment the engine pauses while opening a song, so Android
  /// keeps the app running with the screen locked (see [SystemPlayingState]).
  final SystemPlayingState _systemPlaying = SystemPlayingState();
  Timer? _graceTimer;
  bool? _lastReported;

  /// The video playing on its page, when there is one (30 Sep): while it's in front the system
  /// controls show it and play / pause / skip it instead of the music.
  final NowWatching? watching;

  MediaSession(this.player, this.library, {this.watching}) {
    player.addListener(_sync);
    watching?.addListener(_sync);
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
  static Future<MediaSession?> start(PlayerModel player, LibraryModel library, {NowWatching? watching}) async {
    if (!(Platform.isAndroid || Platform.isWindows)) return null;  // e.g. Linux while developing
    try {
      return await AudioService.init(
        builder: () => MediaSession(player, library, watching: watching),
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

  /// A video is what's playing (its page is open and it was started after the music).
  bool get _video => watching?.inFront ?? false;

  /// Shows the video playing on its page in the system controls.
  void _syncVideo(NowWatching w) {
    final v = w.video!;
    final picture = w.picture;
    final item = MediaItem(
      id: v.id,
      title: v.title,
      artist: [v.collection, ?v.episodeLabel].join(' · '),
      album: v.category ?? 'Videos',
      duration: w.duration > Duration.zero ? w.duration : v.duration,
      artUri: picture == null ? null : Uri.file(picture),
    );
    final old = _shownItem;
    if (old == null ||
        old.id != item.id ||
        old.title != item.title ||
        old.artist != item.artist ||
        old.duration != item.duration ||
        old.artUri != item.artUri) {
      _shownItem = item;
      mediaItem.add(item);
    }
    playbackState.add(PlaybackState(
      controls: [MediaControl.rewind, w.playing ? MediaControl.pause : MediaControl.play, MediaControl.fastForward],
      androidCompactActionIndices: const [0, 1, 2],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      processingState: AudioProcessingState.ready,
      playing: w.playing,
      updatePosition: w.position,
      speed: w.transport?.rate ?? 1.0,
    ));
  }

  /// Sends the player's current state to the system controls.
  void _sync() {
    final w = watching;
    if (w != null && w.inFront) {
      if (w.playing) _stopped = false;
      if (!_stopped) {
        _syncVideo(w);
        return;
      }
    }
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

    // What to tell the system: a pause nobody asked for is hidden for a few seconds.
    final now = DateTime.now();
    final playing = _systemPlaying.report(playing: player.playing, pausedOnPurpose: player.pausedOnPurpose, now: now);
    _graceTimer?.cancel();
    final ends = _systemPlaying.graceEndsAt;
    if (ends != null) _graceTimer = Timer(ends.difference(now) + const Duration(milliseconds: 50), _sync);
    if (playing != _lastReported) {
      _lastReported = playing;
      PlaybackLog.add('Media controls told: ${playing ? 'playing' : 'paused'}'
          '${playing && !player.playing ? ' (the engine paused by itself; waiting a moment)' : ''}');
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
      // A server cover is downloaded first and passed as a file (0.1.21, security review #2);
      // _sync runs again when it arrives.
      artUri: library.artUriFor(t, onDownloaded: _sync),
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
              playing ? MediaControl.pause : MediaControl.play,
              MediaControl.fastForward,
            ]
          : [
              MediaControl.skipToPrevious,
              playing ? MediaControl.pause : MediaControl.play,
              MediaControl.skipToNext,
            ],
      androidCompactActionIndices: const [0, 1, 2],  // all three in the small notification
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      processingState: player.buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
      playing: playing,
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

  // While a video is in front, every button goes to it (next / previous skip by seconds, as for
  // books).
  @override
  Future<void> play() => _video ? watching!.play() : player.play();

  @override
  Future<void> pause() => _video ? watching!.pause() : player.pause();

  @override
  Future<void> stop() async {
    if (_video) {
      await watching!.pause();
    } else {
      await player.pause();
    }
    _stopped = true;
    _sync();
  }

  // Next / previous (headset buttons, keyboard media keys, the Windows media
  // overlay) skip by seconds while a book plays.
  @override
  Future<void> skipToNext() =>
      _video ? watching!.skip(forward: true) : (player.inBook ? player.skipForward() : player.next());

  @override
  Future<void> skipToPrevious() =>
      _video ? watching!.skip(forward: false) : (player.inBook ? player.skipBack() : player.previous());

  @override
  Future<void> fastForward() => _video ? watching!.skip(forward: true) : player.skipForward();

  @override
  Future<void> rewind() => _video ? watching!.skip(forward: false) : player.skipBack();

  @override
  Future<void> seek(Duration position) => _video ? watching!.seek(position) : player.seek(position);
}
