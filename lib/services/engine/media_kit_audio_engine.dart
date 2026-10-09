// The music player's audio engine in the app: media_kit, which uses libmpv (refactor phase 4,
// 9 Oct 2026). A thin pass-through: every call is the media_kit call PlayerModel used to make.
import 'package:media_kit/media_kit.dart' show Media, NativePlayer, Player, Playlist, PlaylistMode;

import 'audio_engine.dart';

class MediaKitAudioEngine implements AudioEngine {
  MediaKitAudioEngine([Player? player]) : _player = player ?? Player();

  final Player _player;

  @override
  Stream<bool> get playingStream => _player.stream.playing;
  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;
  @override
  Stream<Duration> get durationStream => _player.stream.duration;
  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<bool> get completedStream => _player.stream.completed;
  @override
  Stream<int> get indexStream => _player.stream.playlist.map((p) => p.index);
  @override
  Stream<int?> get sampleRateStream => _player.stream.audioParams.map((a) => a.sampleRate);
  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  bool get isPlaying => _player.state.playing;
  @override
  Duration get position => _player.state.position;
  @override
  Duration get duration => _player.state.duration;
  @override
  int get index => _player.state.playlist.index;

  @override
  Future<void> openList(List<EngineMedia> items, {required bool play}) =>
      _player.open(Playlist([for (final m in items) Media(m.uri, start: m.start)], index: 0), play: play);
  @override
  Future<void> add(EngineMedia item) => _player.add(Media(item.uri, start: item.start));
  @override
  Future<void> remove(int index) => _player.remove(index);
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> playOrPause() => _player.playOrPause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> seek(Duration to) => _player.seek(to);
  @override
  Future<void> setLoopOne(bool loop) => _player.setPlaylistMode(loop ? PlaylistMode.single : PlaylistMode.none);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  bool get hasOptions => _player.platform is NativePlayer;
  @override
  Future<void> setOption(String name, String value) async {
    final engine = _player.platform;
    if (engine is NativePlayer) await engine.setProperty(name, value);
  }

  @override
  Future<void> dispose() => _player.dispose();
}
