// Every player HomeTunes makes, set up in one place (refactor phase 4, 9 Oct 2026). Before, each
// screen or service built its own media_kit Player and reached into mpv itself (NativePlayer /
// setProperty) to switch sound, pictures or subtitles off. Now:
//  * [createEngine] makes the player for a use, with its title (shown in the Playback log and the
//    system's sound mixer) and configuration;
//  * [prepareEngine] gives it that use's fixed mpv settings;
//  * [Mpv] reaches mpv's own properties and commands for what's left (subtitle files, the frame
//    picker's frame steps, the track in use), and is null when the engine isn't mpv.
// The music player itself is a MediaKitAudioEngine (media_kit_audio_engine.dart).
// Agreed deviation from the plan's phase 7 rule: screens that show a video still create their
// player (through here), as the Video widget needs it.

import 'dart:io';

import 'package:media_kit/media_kit.dart';

/// What a player is for.
enum EngineUse {
  /// The video page: sound and pictures; on Windows the engine draws subtitles (libass), so
  /// styled and picture subtitles work.
  videoPage('HomeTunes video'),

  /// A song's music video: pictures only, kept in time with the song (which plays in the music
  /// player).
  musicVideo('HomeTunes music video'),

  /// Picking a video's picture from its frames: pictures only, landing on the exact frame.
  framePicker('HomeTunes frame picker'),

  /// Reading what's inside a video file (Details): no sound device and no subtitles; no picture
  /// is decoded without a video view.
  probe('HomeTunes details'),

  /// Taking videos' pictures for the Videos tab: pictures only.
  thumbnails('HomeTunes thumbnails'),

  /// The small picture above a video's progress bar (0.1.84, services/seek_preview.dart):
  /// pictures only, jumping to key frames (fast) rather than the exact frame.
  seekPreview('HomeTunes seek preview');

  const EngineUse(this.title);
  final String title;
}

/// A new player for [use].
Player createEngine(EngineUse use) => Player(
      configuration: PlayerConfiguration(
        title: use.title,
        libass: use == EngineUse.videoPage && !Platform.isAndroid,
      ),
    );

/// The fixed mpv settings for [use] (media_kit starts every player with pictures off: vid=no).
/// Does nothing when the engine isn't mpv. Throws if mpv refuses one.
Future<void> prepareEngine(Player player, EngineUse use) async {
  final mpv = Mpv.of(player);
  if (mpv == null) return;
  for (final (name, value) in engineSettings(use)) {
    await mpv.set(name, value);
  }
}

/// The mpv settings [prepareEngine] gives a player for [use], in order.
List<(String, String)> engineSettings(EngineUse use) => switch (use) {
      EngineUse.videoPage => const [],
      EngineUse.musicVideo => const [('aid', 'no'), ('sid', 'no')],
      EngineUse.framePicker => const [('vid', 'auto'), ('aid', 'no'), ('sid', 'no'), ('hr-seek', 'yes')],
      EngineUse.probe => const [('ao', 'null'), ('sid', 'no')],
      EngineUse.thumbnails => const [('vid', 'auto'), ('aid', 'no'), ('sid', 'no')],
      EngineUse.seekPreview => const [
          ('vid', 'auto'),
          ('aid', 'no'),
          ('sid', 'no'),
          ('hr-seek', 'no'),
          ('screenshot-format', 'jpg'),
          ('screenshot-jpeg-quality', '85'),
        ],
    };

/// How the video page's player buffers what it plays (0.2.12). The user (8 Nov 2026): "Are we
/// also able to buffer the streamed content to help preventing issues with playbacks
/// stuttering?"
///
/// What it was: media_kit's defaults, `cache=yes` and `cache-on-disk=yes` with a 32 MB limit ahead
/// and 32 MB behind, but no `cache-dir`, and mpv only buffers on disk when it has one: so the
/// buffer was in memory, on TVs already short of it. 32 MB is also only ~20–30 s of a big
/// original from a server.
///
/// Now, for something streamed: the buffer goes on disk in the app's temporary folder
/// ([cacheDir], set by main.dart; mpv deletes its file when the video closes), up to
/// [streamAhead] ahead and [streamBehind] behind (going back a little needs no fetching again),
/// and a short head start: playing begins, and carries on after it had to wait (a skip, a slow
/// moment), once [headStart] is in hand, so a skip isn't play, stall, play.
/// Files on the device keep mpv's usual settings: they're read straight from the disk.
///
/// **0.2.13+140 (8 Nov 2026): back in memory, and only a minute ahead.** Measured on the Sony TV
/// (KD-55XH8096, 2 GB, Wi-Fi): with the buffer on disk the limit wasn't kept. mpv's disk cache only
/// ever grows (space it lets go of isn't reused), so it read the whole film as fast as the Wi-Fi
/// allowed (~80 Mbit/s, "read ahead 6309 s" of a 1 h 49 film within 3 minutes), wrote it all to
/// the TV's small storage (+400 MB, under 1 GB left), and the picture froze for up to 1 s every
/// few seconds while it did; once the whole film was in, it played smoothly. Now a streamed video
/// keeps at most [streamSeconds] ahead and [streamAhead] bytes, in memory: after the first minute
/// it reads only as fast as it plays.
abstract final class VideoBuffer {
  /// The old disk buffer's folder; main.dart empties it at start (left-overs from 0.2.12).
  static String? cacheDir;

  /// At most this much ahead of where you are (whichever comes first) and kept behind.
  static const streamAhead = 64 * 1024 * 1024, streamBehind = 16 * 1024 * 1024;
  static const streamSeconds = 60;

  /// Seconds of video in hand before playing starts or carries on.
  static const headStart = 3;

  /// media_kit's own (PlayerConfiguration.bufferSize), for files on the device.
  static const fileBuffer = 32 * 1024 * 1024;

  /// mpv's own `cache-secs` (1000 hours: no time limit), for files on the device.
  static const noTimeLimit = 3600000;

  /// The mpv settings for the next file the video page opens.
  static List<(String, String)> settings({required bool streamed}) => streamed
      ? const [
          ('cache-on-disk', 'no'),
          ('cache-dir', ''),
          ('cache-secs', '$streamSeconds'),
          ('demuxer-max-bytes', '$streamAhead'),
          ('demuxer-max-back-bytes', '$streamBehind'),
          ('cache-pause-initial', 'yes'),
          ('cache-pause-wait', '$headStart'),
        ]
      : const [
          ('cache-on-disk', 'no'),
          ('cache-dir', ''),
          ('cache-secs', '$noTimeLimit'),
          ('demuxer-max-bytes', '$fileBuffer'),
          ('demuxer-max-back-bytes', '$fileBuffer'),
          ('cache-pause-initial', 'no'),
          ('cache-pause-wait', '1'),
        ];
}

/// mpv's own properties and commands for a player.
class Mpv {
  Mpv._(this._native);
  final NativePlayer _native;

  /// Null when the player's engine isn't mpv (e.g. on the web).
  static Mpv? of(Player player) {
    final p = player.platform;
    return p is NativePlayer ? Mpv._(p) : null;
  }

  Future<void> set(String name, String value) => _native.setProperty(name, value);

  Future<String> get(String name, {bool waitForInitialization = true}) =>
      _native.getProperty(name, waitForInitialization: waitForInitialization);

  Future<void> command(List<String> args) => _native.command(args);
}
