// The video page's player, as its session sees it (refactor phase 5, 9 Oct 2026). Like
// AudioEngine for the music player: `VideoSession` (state/video_session.dart) drives a
// [VideoEngine], which is [MediaKitVideoEngine] in the app (media_kit / mpv) and a fake in tests.
// The page itself still draws the picture from the media_kit player inside
// ([MediaKitVideoEngine.player]): the Video widget needs it.
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

import 'engines.dart';

/// One audio or subtitle track in a video file, as the engine lists it. 'auto' and 'no' are the
/// engine's own "pick for me" and "off" entries.
class MediaTrack {
  const MediaTrack(this.id, {this.title, this.language, this.codec, this.channels});
  final String id;
  final String? title, language, codec, channels;

  bool get isReal => id != 'auto' && id != 'no';
}

/// What a video page needs from its player.
abstract class VideoEngine {
  Stream<bool> get completedStream;
  Stream<String> get errorStream;
  Stream<Duration> get positionStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<Duration> get durationStream;

  /// The engine's own volume (above 100 when the volume boost amplifies, models/volume_boost.dart).
  Stream<double> get volumeStream;
  Stream<int?> get sampleRateStream;

  /// The file's list of tracks changed (it's known once the file has opened).
  Stream<void> get tracksStream;

  /// The tracks in use changed.
  Stream<void> get trackStream;

  bool get isPlaying;
  Duration get position;
  Duration get duration;
  double get volume;
  double get rate;
  List<MediaTrack> get audioTracks;
  List<MediaTrack> get subtitleTracks;

  Future<void> open(String path, {Duration? start});
  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration to);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);

  /// Uses the track with [id]; null switches that kind off.
  Future<void> setAudioTrack(String? id);
  Future<void> setSubtitleTrack(String? id);

  /// mpv's own properties and commands: [hasOptions] is false when the engine isn't mpv, and then
  /// the others do nothing ([getOption] gives '').
  bool get hasOptions;
  Future<void> setOption(String name, String value);
  Future<String> getOption(String name);
  Future<void> command(List<String> args);

  /// The picture on screen now, as a JPEG; null when there isn't one yet.
  Future<Uint8List?> screenshot();

  Future<void> dispose();
}

/// The video page's media_kit player (`createEngine(EngineUse.videoPage)`).
class MediaKitVideoEngine implements VideoEngine {
  MediaKitVideoEngine([Player? player]) : player = player ?? createEngine(EngineUse.videoPage);

  /// The player itself, for the Video widget and the video bar's own controls.
  final Player player;

  Mpv? get _mpv => Mpv.of(player);

  static MediaTrack _audio(AudioTrack t) =>
      MediaTrack(t.id, title: t.title, language: t.language, codec: t.codec, channels: t.channels);
  static MediaTrack _subtitle(SubtitleTrack t) =>
      MediaTrack(t.id, title: t.title, language: t.language, codec: t.codec);

  @override
  Stream<bool> get completedStream => player.stream.completed;
  @override
  Stream<String> get errorStream => player.stream.error;
  @override
  Stream<Duration> get positionStream => player.stream.position;
  @override
  Stream<bool> get playingStream => player.stream.playing;
  @override
  Stream<bool> get bufferingStream => player.stream.buffering;
  @override
  Stream<Duration> get durationStream => player.stream.duration;
  @override
  Stream<double> get volumeStream => player.stream.volume;
  @override
  Stream<int?> get sampleRateStream => player.stream.audioParams.map((a) => a.sampleRate);
  @override
  Stream<void> get tracksStream => player.stream.tracks.map((_) {});
  @override
  Stream<void> get trackStream => player.stream.track.map((_) {});

  @override
  bool get isPlaying => player.state.playing;
  @override
  Duration get position => player.state.position;
  @override
  Duration get duration => player.state.duration;
  @override
  double get volume => player.state.volume;
  @override
  double get rate => player.state.rate;
  @override
  List<MediaTrack> get audioTracks => [for (final t in player.state.tracks.audio) _audio(t)];
  @override
  List<MediaTrack> get subtitleTracks => [for (final t in player.state.tracks.subtitle) _subtitle(t)];

  @override
  Future<void> open(String path, {Duration? start}) => player.open(Media(path, start: start));
  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> playOrPause() => player.playOrPause();
  @override
  Future<void> seek(Duration to) => player.seek(to);
  @override
  Future<void> setRate(double rate) => player.setRate(rate);
  @override
  Future<void> setVolume(double volume) => player.setVolume(volume);

  @override
  Future<void> setAudioTrack(String? id) async {
    if (id == null) return player.setAudioTrack(AudioTrack.no());
    final t = player.state.tracks.audio.where((t) => t.id == id).firstOrNull;
    if (t != null) await player.setAudioTrack(t);
  }

  @override
  Future<void> setSubtitleTrack(String? id) async {
    if (id == null) return player.setSubtitleTrack(SubtitleTrack.no());
    final t = player.state.tracks.subtitle.where((t) => t.id == id).firstOrNull;
    if (t != null) await player.setSubtitleTrack(t);
  }

  @override
  bool get hasOptions => _mpv != null;
  @override
  Future<void> setOption(String name, String value) async => _mpv?.set(name, value);
  @override
  Future<String> getOption(String name) async => await _mpv?.get(name) ?? '';
  @override
  Future<void> command(List<String> args) async => _mpv?.command(args);

  @override
  Future<Uint8List?> screenshot() => player.screenshot(format: 'image/jpeg');

  @override
  Future<void> dispose() => player.dispose();
}
