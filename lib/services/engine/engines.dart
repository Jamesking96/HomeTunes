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
  thumbnails('HomeTunes thumbnails');

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
    };

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
