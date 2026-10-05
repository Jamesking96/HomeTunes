// Video playback stats in the Playback log (0.1.55). The user saw videos and music videos
// stutter now and then, more on the phone, and we agreed to measure before changing anything.
//
// While a video plays, a VideoStats reads a few numbers from the video engine (libmpv):
//   - when a file starts: its picture size, format (H.264, HEVC…, 10-bit or not), frame rate,
//     and how it's being decoded: by the device's video chip ("hardware") or by the main
//     processor ("software"), and whether the chip's pictures are copied before drawing;
//   - every 5 s: how many pictures were dropped (by the decoder, or because the screen couldn't
//     keep up), how much of the file is read ahead, and how often the picture paused to load
//     (0.1.56: the engine reports that after any seek too, so the pause after opening a file or
//     after a music video's jump back into step isn't counted; the jumps are counted on their
//     own, see [VideoStats.jumped]);
//   - Flutter's own frame timings: how often the app itself was slow to draw (its redraws can
//     take time away from the video on a phone).
// 0.1.57: a stutter line also says how far out each music video jump was ("video behind by
// 1.8–2.6 s"), the slowest app frame and whether building or drawing made it slow, and when the
// app was out of sight for part of the 30 s (coming back redraws everything and drops pictures,
// which isn't stutter while watching).
// Every 30 s, only if something went wrong, one "stutter" line goes in the log; when the
// video closes (or the next one starts) a one-line summary. The log is in Settings › About ›
// Playback log, where it can be copied and sent.
//
// Pure helpers (describeDecoder, startLine, stutterLine, summaryLine) are tested directly; the
// engine is read through [ReadProperty], so tests use a fake.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState;
import 'package:media_kit/media_kit.dart';

import 'playback_log.dart';

/// Reads one libmpv property as text ('' when it has no value).
typedef ReadProperty = Future<String> Function(String name);

/// How the video is being decoded, in plain words, from mpv's `hwdec-current`.
String describeDecoder(String hwdec) {
  final h = hwdec.trim();
  if (h.isEmpty || h == 'no') return 'software (main processor)';
  if (h.contains('copy')) return 'video chip, copied before drawing ($h)';
  return 'video chip ($h)';
}

/// How the pictures reach the screen, in plain words, from mpv's `current-vo` (0.1.57).
String describeDrawing(String vo) {
  final v = vo.trim();
  if (v.isEmpty) return '?';
  if (v == 'mediacodec_embed') return 'straight from the video chip ($v)';
  return v;
}

/// The music video's jumps back into step, by how far out it was (0.1.57): "video behind by
/// 1.8–2.6 s". [drifts] are video minus song: negative when the video was behind.
String jumpDetail(List<Duration> drifts) {
  String secs(Duration d) => _num((d.inMilliseconds.abs() / 1000).toString(), digits: 1);
  String range(List<Duration> ds, String how) {
    final ms = ds.map((d) => d.inMilliseconds.abs()).toList()..sort();
    final lo = Duration(milliseconds: ms.first), hi = Duration(milliseconds: ms.last);
    final a = secs(lo), b = secs(hi);
    return 'video $how by ${a == b ? a : '$a–$b'} s';
  }

  final behind = drifts.where((d) => d.isNegative).toList();
  final ahead = drifts.where((d) => !d.isNegative).toList();
  return [if (behind.isNotEmpty) range(behind, 'behind'), if (ahead.isNotEmpty) range(ahead, 'ahead')].join(', ');
}

/// What made the app's slow frames slow (0.1.57): "worst 85 ms, mostly drawing". Building is the
/// app working out what to show; drawing is turning that into pixels (the video picture included).
String slowDetail({required int worstMs, required int building, required int drawing}) {
  if (worstMs <= 0) return '';
  final mostly = building > drawing
      ? ', mostly building the screen'
      : drawing > building
          ? ', mostly drawing'
          : '';
  return 'worst $worstMs ms$mostly';
}

/// "HEVC 10-bit" from mpv's `video-format` and `video-params/pixelformat`.
String describeFormat(String format, String pixelFormat) {
  final f = format.trim().isEmpty ? 'unknown format' : format.trim().toUpperCase();
  final bits = RegExp(r'p(9|10|12|16)').firstMatch(pixelFormat)?.group(1);
  return bits == null ? f : '$f $bits-bit';
}

String _num(String s, {int digits = 2}) {
  final v = double.tryParse(s.trim());
  if (v == null) return '?';
  final t = v.toStringAsFixed(digits);
  return t.contains('.') ? t.replaceFirst(RegExp(r'\.?0+$'), '') : t;
}

/// The line logged when a file starts showing.
String startLine(String label, String name, Map<String, String> p) {
  final w = p['video-params/w'] ?? '', h = p['video-params/h'] ?? '';
  final size = (w.isEmpty || h.isEmpty) ? 'size unknown' : '$w×$h';
  final fps = p['container-fps'] ?? '';
  return '$label started: $name · $size · ${describeFormat(p['video-format'] ?? '', p['video-params/pixelformat'] ?? '')}'
      '${fps.isEmpty ? '' : ' · ${_num(fps)} fps'}'
      ' · decoding: ${describeDecoder(p['hwdec-current'] ?? '')}'
      ' · drawing: ${describeDrawing(p['current-vo'] ?? '')}';
}

String _times(int n, String what) => '$what $n time${n == 1 ? '' : 's'}';

/// What went wrong, as parts of a line. 0.1.56: "paused to load" (was "waited for the file":
/// the engine reports any pause while it gets pictures ready, including after a seek), and
/// the music video's jumps back into step counted on their own.
List<String> _problems(
        {required int drops,
        required int jumps,
        required int waits,
        required int slow,
        List<Duration> drifts = const [],
        String slowWhy = ''}) =>
    [
      if (jumps > 0) _times(jumps, 'jumped back into step') + (drifts.isEmpty ? '' : ' (${jumpDetail(drifts)})'),
      if (waits > 0) _times(waits, 'paused to load'),
      if (slow > 0) _times(slow, 'app slow to draw') + (slowWhy.isEmpty ? '' : ' ($slowWhy)'),
    ];

/// The line logged every 30 s when something went wrong; null when all was well.
/// 0.1.57: how far out each jump was ([jumpDrifts]), what made slow frames slow ([slowWhy]),
/// and whether the app was out of sight for part of the time ([leftScreen]: leaving and coming
/// back drops pictures and redraws everything, which isn't the same as stutter while watching).
String? stutterLine(String label,
    {required int decoderDrops,
    required int screenDrops,
    required int waits,
    required int slowAppFrames,
    required String readAhead,
    required Duration over,
    int jumps = 0,
    List<Duration> jumpDrifts = const [],
    String slowWhy = '',
    bool leftScreen = false}) {
  if (decoderDrops + screenDrops + waits + slowAppFrames + jumps == 0) return null;
  final parts = <String>[
    if (decoderDrops + screenDrops > 0)
      '${decoderDrops + screenDrops} picture${decoderDrops + screenDrops == 1 ? '' : 's'} dropped '
          '(decoder $decoderDrops, screen $screenDrops)',
    ..._problems(drops: 0, jumps: jumps, waits: waits, slow: slowAppFrames, drifts: jumpDrifts, slowWhy: slowWhy),
    if (readAhead.isNotEmpty) 'read ahead ${_num(readAhead, digits: 1)} s',
    if (leftScreen) 'the app was out of sight for part of it',
  ];
  return '$label stutter in the last ${over.inSeconds} s: ${parts.join(' · ')}';
}

/// The line logged when a file stops (closed, or the next one starts).
String summaryLine(String label, String name,
    {required Duration played, required int drops, required int waits, required int slowAppFrames, int jumps = 0}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final m = played.inMinutes, s = played.inSeconds % 60;
  final verdict = drops + waits + slowAppFrames + jumps == 0
      ? 'smooth'
      : [
          if (drops > 0) '$drops picture${drops == 1 ? '' : 's'} dropped',
          ..._problems(drops: drops, jumps: jumps, waits: waits, slow: slowAppFrames),
        ].join(', ');
  return '$label finished: $name · played $m:${two(s)} · $verdict';
}

/// Watches one player. Make it with [VideoStats.forPlayer] (null in tests and on players without
/// the native engine), then call [started], [playing], [buffering] and [dispose].
class VideoStats {
  VideoStats(this.label, this.read,
      {this.sampleEvery = const Duration(seconds: 5), this.reportEvery = 6, DateTime Function()? now})
      : now = now ?? DateTime.now;

  /// The clock (tests use a fake one).
  final DateTime Function() now;

  /// "Video" or "Music video".
  final String label;
  final ReadProperty read;
  final Duration sampleEvery;

  /// Samples between stutter reports (6 × 5 s = 30 s).
  final int reportEvery;

  static VideoStats? forPlayer(Player player, String label) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
    final engine = player.platform;
    if (engine is! NativePlayer) return null;
    return VideoStats(label, (name) => engine.getProperty(name, waitForInitialization: false));
  }

  String? _name;
  Timer? _timer, _startTimer;
  DateTime? _playingSince;
  Duration _played = Duration.zero;
  int _lastDecoder = 0, _lastScreen = 0;
  // Since the last report, and since the file started.
  int _decoderDrops = 0, _screenDrops = 0, _waits = 0, _slow = 0, _jumps = 0, _samples = 0;
  int _totalDrops = 0, _totalWaits = 0, _totalSlow = 0, _totalJumps = 0;
  bool _disposed = false;

  /// Pauses before this time are expected (the file opening, or a jump), so they don't count.
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);
  static const _settle = Duration(milliseconds: 2500);

  // 0.1.57: how far out each jump since the last report was (video minus song), what the slow
  // frames' worst was and whether building or drawing made them slow, and whether the app left
  // the screen.
  final List<Duration> _drifts = [];
  int _worstMs = 0, _slowBuilding = 0, _slowDrawing = 0;
  bool _leftScreen = false;
  AppLifecycleListener? _lifecycle;

  /// The music video was jumped back into step with its song (0.1.56). The pause that follows
  /// is expected and isn't counted as "paused to load". [drift] is how far out it was (video
  /// minus song: negative when the video was behind).
  void jumped([Duration? drift]) {
    if (_disposed || _name == null) return;
    if (drift != null) _drifts.add(drift);
    _jumps++;
    _totalJumps++;
    _quietUntil = now().add(_settle);
  }

  /// A new file is opening: sums up the last one, then logs this one's details once it's
  /// showing (a few seconds in, when the engine knows them).
  void started(String name) {
    _finish();
    _name = name;
    _lastDecoder = 0;
    _lastScreen = 0;
    _quietUntil = now().add(_settle); // opening the file pauses too
    _startTimer?.cancel();
    _startTimer = Timer(const Duration(seconds: 3), _logStart);
    _logDeviceOnce();
  }

  static bool _deviceLogged = false;
  static void _logDeviceOnce() {
    if (_deviceLogged) return;
    _deviceLogged = true;
    PlaybackLog.add('Device: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}, '
        '${Platform.numberOfProcessors} processor cores');
  }

  Future<void> _logStart() async {
    final name = _name;
    if (name == null || _disposed) return;
    final p = <String, String>{};
    for (final k in const [
      'video-params/w',
      'video-params/h',
      'video-format',
      'video-params/pixelformat',
      'container-fps',
      'hwdec-current',
      'current-vo',
    ]) {
      p[k] = await _get(k);
    }
    if (_disposed || name != _name) return;
    PlaybackLog.add(startLine(label, name, p));
    // Start counting drops from here.
    _lastDecoder = int.tryParse(await _get('decoder-frame-drop-count')) ?? 0;
    _lastScreen = int.tryParse(await _get('frame-drop-count')) ?? 0;
  }

  Future<String> _get(String name) async {
    try {
      return await read(name);
    } catch (_) {
      return '';
    }
  }

  /// Playing or paused: only playing time is sampled.
  void playing(bool on) {
    if (_disposed) return;
    if (on && _timer == null) {
      _playingSince = now();
      _timer = Timer.periodic(sampleEvery, (_) => _sample());
      _watchFrames(true);
      _lifecycle ??= AppLifecycleListener(onStateChange: (s) {
        if (s == AppLifecycleState.hidden || s == AppLifecycleState.paused) _leftScreen = true;
      });
    } else if (!on && _timer != null) {
      _timer?.cancel();
      _timer = null;
      _addPlayed();
      _watchFrames(false);
    }
  }

  void _addPlayed() {
    final since = _playingSince;
    if (since != null) _played += now().difference(since);
    _playingSince = null;
  }

  /// The engine paused (true) to get pictures ready, or carried on. Includes the pause after any
  /// seek; the ones after opening a file or a [jumped] aren't counted.
  void buffering(bool on) {
    if (on && _name != null && _timer != null && !now().isBefore(_quietUntil)) {
      _waits++;
      _totalWaits++;
    }
  }

  Future<void> _sample() async {
    if (_disposed) return;
    final decoder = int.tryParse(await _get('decoder-frame-drop-count')) ?? _lastDecoder;
    final screen = int.tryParse(await _get('frame-drop-count')) ?? _lastScreen;
    if (_disposed) return;
    // A new file resets the engine's counts: a smaller number just starts again from there.
    final dDec = decoder >= _lastDecoder ? decoder - _lastDecoder : decoder;
    final dScr = screen >= _lastScreen ? screen - _lastScreen : screen;
    _lastDecoder = decoder;
    _lastScreen = screen;
    _decoderDrops += dDec;
    _screenDrops += dScr;
    _totalDrops += dDec + dScr;
    _samples++;
    if (_samples >= reportEvery) await _report();
  }

  Future<void> _report() async {
    final readAhead =
        (_decoderDrops + _screenDrops + _waits + _slow + _jumps) > 0 ? await _get('demuxer-cache-duration') : '';
    final line = stutterLine(label,
        decoderDrops: _decoderDrops,
        screenDrops: _screenDrops,
        waits: _waits,
        slowAppFrames: _slow,
        jumps: _jumps,
        jumpDrifts: _drifts,
        slowWhy: slowDetail(worstMs: _worstMs, building: _slowBuilding, drawing: _slowDrawing),
        leftScreen: _leftScreen,
        readAhead: readAhead,
        over: sampleEvery * _samples);
    if (line != null) PlaybackLog.add(line);
    _resetPeriod();
  }

  void _resetPeriod() {
    _decoderDrops = _screenDrops = _waits = _slow = _jumps = _samples = 0;
    _worstMs = _slowBuilding = _slowDrawing = 0;
    _drifts.clear();
    _leftScreen = false;
  }

  void _finish() {
    final name = _name;
    if (name == null) return;
    _addPlayed();
    if (_timer != null) _playingSince = now();
    if (_played > const Duration(seconds: 2)) {
      PlaybackLog.add(summaryLine(label, name,
          played: _played,
          drops: _totalDrops,
          waits: _totalWaits,
          slowAppFrames: _totalSlow,
          jumps: _totalJumps));
    }
    _name = null;
    _played = Duration.zero;
    _resetPeriod();
    _totalDrops = _totalWaits = _totalSlow = _totalJumps = 0;
  }

  /// The player is closing.
  void dispose() {
    if (_disposed) return;
    _finish();
    _disposed = true;
    _timer?.cancel();
    _startTimer?.cancel();
    _watchFrames(false);
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  // ---- the app's own drawing ----

  // One callback for all watchers: Flutter reports frame timings in batches.
  static final Set<VideoStats> _framesFor = {};
  static bool _hooked = false;

  /// A frame that took longer than this to build and draw counts as "slow" (two 60 Hz frames).
  static const slowFrame = Duration(milliseconds: 34);

  void _watchFrames(bool on) {
    on ? _framesFor.add(this) : _framesFor.remove(this);
    if (_framesFor.isNotEmpty && !_hooked) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
      _hooked = true;
    } else if (_framesFor.isEmpty && _hooked) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _hooked = false;
    }
  }

  static void _onTimings(List<FrameTiming> timings) {
    final slow = timings.where((t) => t.totalSpan > slowFrame).toList();
    if (slow.isEmpty) return;
    for (final s in _framesFor) {
      s._slow += slow.length;
      s._totalSlow += slow.length;
      for (final t in slow) {
        s._worstMs = math.max(s._worstMs, t.totalSpan.inMilliseconds);
        t.buildDuration > t.rasterDuration ? s._slowBuilding++ : s._slowDrawing++;
      }
    }
  }
}
