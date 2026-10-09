// A pretend video player for VideoSession tests (refactor phase 5): no sound or pictures, it
// records what it was asked to do and the test says what the "file" did (opened, its tracks, the
// end). Like test/fake_audio_engine.dart for the music player.
import 'dart:async';
import 'dart:typed_data';

import 'package:hometunes/services/engine/video_engine.dart';

class FakeVideoEngine implements VideoEngine {
  final _completed = StreamController<bool>.broadcast(sync: true);
  final _error = StreamController<String>.broadcast(sync: true);
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _buffering = StreamController<bool>.broadcast(sync: true);
  final _duration = StreamController<Duration>.broadcast(sync: true);
  final _volume = StreamController<double>.broadcast(sync: true);
  final _sampleRate = StreamController<int?>.broadcast(sync: true);
  final _tracks = StreamController<void>.broadcast(sync: true);
  final _track = StreamController<void>.broadcast(sync: true);

  /// Every call, in order ("open S01E01", "open S01E01 at 0:00:42.000000", "rate 1.5", "audio 2",
  /// "subtitles off", "seek …", "pause", "sub-add …").
  final List<String> calls = [];

  /// The file open now (just the file name, without folder or extension).
  String? openName;

  /// mpv options set, and what `aid` / `sid` read back.
  final Map<String, String> options = {};
  String aid = 'auto', sid = 'auto';
  bool disposed = false;

  @override
  bool isPlaying = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = Duration.zero;
  @override
  double volume = 100;
  @override
  double rate = 1.0;
  @override
  List<MediaTrack> audioTracks = const [];
  @override
  List<MediaTrack> subtitleTracks = const [];

  static String nameOf(String path) {
    final file = path.split(RegExp(r'[\\/]')).last;
    final dot = file.lastIndexOf('.');
    return dot > 0 ? file.substring(0, dot) : file;
  }

  // ---- test helpers: what the "file" did ----

  /// The file opened and started playing: its length, and its tracks (listed by the engine).
  void loaded({Duration length = const Duration(minutes: 20), List<MediaTrack>? audio, List<MediaTrack>? subtitles}) {
    duration = length;
    _duration.add(length);
    audioTracks = audio ?? const [MediaTrack('1', language: 'eng')];
    subtitleTracks = subtitles ?? const [];
    setPlaying(true);
    _tracks.add(null);
  }

  void setPlaying(bool v) {
    isPlaying = v;
    _playing.add(v);
  }

  void moveTo(Duration at) {
    position = at;
    _position.add(at);
  }

  /// The end of the file.
  void finish() {
    position = duration;
    setPlaying(false);
    _completed.add(true);
  }

  void fail(String message) => _error.add(message);

  // ---- VideoEngine ----

  @override
  Stream<bool> get completedStream => _completed.stream;
  @override
  Stream<String> get errorStream => _error.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<bool> get bufferingStream => _buffering.stream;
  @override
  Stream<Duration> get durationStream => _duration.stream;
  @override
  Stream<double> get volumeStream => _volume.stream;
  @override
  Stream<int?> get sampleRateStream => _sampleRate.stream;
  @override
  Stream<void> get tracksStream => _tracks.stream;
  @override
  Stream<void> get trackStream => _track.stream;

  @override
  Future<void> open(String path, {Duration? start}) async {
    openName = nameOf(path);
    calls.add('open $openName${start != null ? ' at $start' : ''}');
    position = start ?? Duration.zero;
    duration = Duration.zero;
    audioTracks = const [];
    subtitleTracks = const [];
    aid = 'auto';
    sid = 'auto';
  }

  @override
  Future<void> play() async => setPlaying(true);
  @override
  Future<void> pause() async {
    calls.add('pause');
    setPlaying(false);
  }

  @override
  Future<void> playOrPause() => isPlaying ? pause() : play();
  @override
  Future<void> seek(Duration to) async {
    calls.add('seek $to');
    position = to;
  }

  @override
  Future<void> setRate(double value) async {
    calls.add('rate $value');
    rate = value;
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
    _volume.add(value);
  }

  @override
  Future<void> setAudioTrack(String? id) async {
    calls.add('audio ${id ?? 'off'}');
    aid = id ?? 'no';
    _track.add(null);
  }

  @override
  Future<void> setSubtitleTrack(String? id) async {
    calls.add('subtitles ${id ?? 'off'}');
    sid = id ?? 'no';
    _track.add(null);
  }

  @override
  bool get hasOptions => true;
  @override
  Future<void> setOption(String name, String value) async => options[name] = value;
  @override
  Future<String> getOption(String name) async => switch (name) { 'aid' => aid, 'sid' => sid, _ => options[name] ?? '' };
  @override
  Future<void> command(List<String> args) async => calls.add(args.join(' '));

  @override
  Future<Uint8List?> screenshot() async => null;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
