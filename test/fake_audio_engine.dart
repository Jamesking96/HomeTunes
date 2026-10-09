// A pretend audio engine for PlayerModel's tests (refactor phase 4, 9 Oct 2026). It behaves like
// the real one where PlayerModel relies on it (checked on the real engine by
// tool/bench/engine_test.dart and player_gapless_test.dart):
// - it holds a list of files and plays the first; at the end of a file it reports "completed",
//   then moves on by itself to the next one in its list, if there is one;
// - with loop-one on it starts the same file again instead;
// - at the end of its list it stops playing.
// Tests move time on with [finishCurrent] (the file ends) and read what PlayerModel asked for.
import 'dart:async';

import 'package:hometunes/services/engine/audio_engine.dart';

class FakeAudioEngine implements AudioEngine {
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _index = StreamController<int>.broadcast();
  final _sampleRate = StreamController<int?>.broadcast();
  final _error = StreamController<String>.broadcast();

  /// What the engine holds now, by uri.
  List<EngineMedia> items = [];
  @override
  int index = 0;
  @override
  bool isPlaying = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = Duration.zero;
  bool loopOne = false;
  double volume = 100;
  double rate = 1.0;

  /// Options set with [setOption] (mpv properties), latest value each.
  final Map<String, String> options = {};

  /// Options this engine refuses (throws), e.g. 'af' on a device without the filter.
  final Set<String> refuse = {};

  /// Every call, in order ("open One, Two", "remove 0", "add Three", "seek 0:00:05"…).
  final List<String> calls = [];

  /// The uris it holds, shortened to file names without folder or extension.
  List<String> get names => [for (final m in items) nameOf(m.uri)];
  static String nameOf(String uri) {
    final file = uri.split(RegExp(r'[\\/]')).last;
    final dot = file.lastIndexOf('.');
    final name = dot > 0 ? file.substring(0, dot) : file;
    // Drop a leading track number ("01 One" -> "One") so names match titles.
    return name.replaceFirst(RegExp(r'^\d+\s+'), '');
  }

  String? get currentName => items.isEmpty ? null : nameOf(items[index].uri);

  void _setPlaying(bool v) {
    if (isPlaying == v) return;
    isPlaying = v;
    _playing.add(v);
  }

  // ---- test helpers ----

  /// The playing file ends: "completed", then the next file in the list (or the same one with
  /// loop-one, or nothing at the end of the list).
  void finishCurrent() {
    if (items.isEmpty) return;
    _completed.add(true);
    if (loopOne) {
      position = Duration.zero;
      return;
    }
    if (index + 1 < items.length) {
      index++;
      position = items[index].start ?? Duration.zero;
      _index.add(index);
      _completed.add(false);
    } else {
      _setPlaying(false);
    }
  }

  /// The engine learns the open file's real length.
  void reportDuration(Duration d) {
    duration = d;
    _duration.add(d);
  }

  void reportSampleRate(int rate) => _sampleRate.add(rate);
  void reportError(String e) => _error.add(e);

  // ---- AudioEngine ----

  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<bool> get bufferingStream => _buffering.stream;
  @override
  Stream<Duration> get durationStream => _duration.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<bool> get completedStream => _completed.stream;
  @override
  Stream<int> get indexStream => _index.stream;
  @override
  Stream<int?> get sampleRateStream => _sampleRate.stream;
  @override
  Stream<String> get errorStream => _error.stream;

  @override
  Future<void> openList(List<EngineMedia> items, {required bool play}) async {
    calls.add('open ${[for (final m in items) nameOf(m.uri)].join(', ')}'
        '${items.first.start != null ? ' at ${items.first.start}' : ''}');
    this.items = List.of(items);
    index = 0;
    position = items.first.start ?? Duration.zero;
    _index.add(0);
    _setPlaying(play);
  }

  @override
  Future<void> add(EngineMedia item) async {
    calls.add('add ${nameOf(item.uri)}');
    items.add(item);
  }

  @override
  Future<void> remove(int i) async {
    calls.add('remove $i');
    items.removeAt(i);
    if (i < index) index--;
    _index.add(index);
  }

  @override
  Future<void> play() async => _setPlaying(items.isNotEmpty);
  @override
  Future<void> pause() async => _setPlaying(false);
  @override
  Future<void> playOrPause() async => _setPlaying(!isPlaying);

  @override
  Future<void> stop() async {
    calls.add('stop');
    items = [];
    index = 0;
    position = Duration.zero;
    _setPlaying(false);
  }

  @override
  Future<void> seek(Duration to) async {
    calls.add('seek $to');
    position = to;
  }

  @override
  Future<void> setLoopOne(bool loop) async {
    calls.add('loop one $loop');
    loopOne = loop;
  }

  @override
  Future<void> setVolume(double v) async => volume = v;
  @override
  Future<void> setRate(double r) async => rate = r;

  @override
  bool get hasOptions => true;
  @override
  Future<void> setOption(String name, String value) async {
    if (refuse.contains(name)) throw StateError('refused $name');
    options[name] = value;
  }

  @override
  Future<void> dispose() async {
    for (final c in [_playing, _buffering, _duration, _position, _completed, _index, _sampleRate, _error]) {
      await c.close();
    }
  }
}
