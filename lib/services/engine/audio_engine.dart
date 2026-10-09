// What the music player needs from an audio engine (refactor phase 4, 9 Oct 2026). PlayerModel
// used to make a media_kit Player itself, so its queue, gapless and audiobook logic could only be
// checked on the real engine (tool/bench). Now it talks to an AudioEngine: MediaKitAudioEngine in
// the app (media_kit_audio_engine.dart), and a fake one in tests (test/fake_audio_engine.dart).
// It's exactly what PlayerModel uses, nothing more.

/// One file or stream to play, starting part-way in when [start] is given.
class EngineMedia {
  const EngineMedia(this.uri, {this.start});
  final String uri;
  final Duration? start;
}

abstract class AudioEngine {
  // ---- what the engine tells us ----
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<Duration> get durationStream;
  Stream<Duration> get positionStream;

  /// True at the end of every file (just before moving on to one loaded ahead).
  Stream<bool> get completedStream;

  /// Which item of the engine's list is playing (it moves on by itself to one loaded ahead).
  Stream<int> get indexStream;

  /// The playing file's sample rate, when known.
  Stream<int?> get sampleRateStream;
  Stream<String> get errorStream;

  bool get isPlaying;
  Duration get position;
  Duration get duration;
  int get index;

  // ---- what we tell it ----

  /// Replaces the engine's list with [items] and starts at the first.
  Future<void> openList(List<EngineMedia> items, {required bool play});
  Future<void> add(EngineMedia item);
  Future<void> remove(int index);
  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> stop();
  Future<void> seek(Duration to);

  /// Loops the current file by itself (repeat-one), or not.
  Future<void> setLoopOne(bool loop);

  /// The engine's volume (100 = normal; more is amplified).
  Future<void> setVolume(double volume);
  Future<void> setRate(double rate);

  /// Whether [setOption] reaches the engine (mpv's properties: libmpv only).
  bool get hasOptions;

  /// Sets one of the engine's own options (an mpv property such as 'af' or 'replaygain').
  /// Throws if the engine refuses it.
  Future<void> setOption(String name, String value);

  Future<void> dispose();
}
