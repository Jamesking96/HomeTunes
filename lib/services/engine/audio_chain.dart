// The equaliser chain shared by the music player and the video page (refactor phase 4, 9 Oct
// 2026). Both used to carry their own copy of the same steps: work out the band filter for the
// preset (bands at or above half the sample rate left out), send it only when it changed, and
// let a slider being dragged send many changes a second without them piling up (one send at a
// time, then a catch-up with the latest). What differs is kept as settings:
//  * how the preset's overall level reaches the engine: music turns its volume down by a factor
//    ([EqLevel.volumeFactor]); videos use mpv's `replaygain-fallback` so the volume slider stays
//    the listener's ([EqLevel.replayGainFallback]). A volume filter in the lavfi graph stalled
//    playback (tool/bench/frame_picker_engine_test.dart), so neither puts the level in the filter.
//  * whether a refused filter is reported (music tells the Equaliser screen).

import 'package:flutter/foundation.dart';

import '../../models/eq_preset.dart';

/// How a preset's overall level reaches the engine.
enum EqLevel { volumeFactor, replayGainFallback }

class AudioChain {
  AudioChain({
    required this.preset,
    required this.hasOptions,
    required this.setOption,
    required this.level,
    this.onLevelFactor,
    this.onResult,
    this.name = 'audio engine',
    this.logChanges = false,
  });

  /// The preset to use now (read again on every send, so a catch-up uses the latest).
  final EqPreset? Function() preset;

  /// Whether the engine takes options at all (false on the web, or before it's ready).
  final bool Function() hasOptions;

  /// Sets one engine option; throws if the engine refuses it.
  final Future<void> Function(String name, String value) setOption;

  final EqLevel level;

  /// [EqLevel.volumeFactor]: told the new factor (0–1) whenever it changes.
  final Future<void> Function(double factor)? onLevelFactor;

  /// Told after each filter send whether the engine refused it.
  final void Function(bool refused)? onResult;

  /// For the debug log: "the `name` refused the equaliser".
  final String name;

  /// Whether to log each filter sent.
  final bool logChanges;

  int? _sampleRate;
  String? _applied;
  double _factor = 1.0;
  bool _busy = false;
  bool _again = false;
  bool _closed = false;

  /// The factor the volume is multiplied by ([EqLevel.volumeFactor]); 1 otherwise.
  double get levelFactor => _factor;

  int? get sampleRate => _sampleRate;

  /// The engine reported the file's sample rate: re-sends if it's new.
  void sampleRateChanged(int? rate) {
    if (rate == null || rate <= 0 || rate == _sampleRate) return;
    _sampleRate = rate;
    update();
  }

  /// No more sends after this (the page closed, or the player was disposed).
  void close() => _closed = true;

  /// Sends the current preset if anything changed.
  Future<void> update() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _send();
      } while (_again && !_closed);
    } finally {
      _busy = false;
    }
  }

  /// The filter and the level text for [EqLevel.replayGainFallback], for a preset.
  static ({String filter, String level}) settingsFor(EqPreset? preset, {int? sampleRate}) =>
      (filter: eqFilter(preset, sampleRate: sampleRate), level: (preset?.level ?? 0).toStringAsFixed(1));

  Future<void> _send() async {
    if (_closed) return;
    final p = preset();
    final (:filter, level: levelText) = settingsFor(p, sampleRate: _sampleRate);
    if (level == EqLevel.volumeFactor) {
      final factor = eqLevelFactor(p);
      if (factor != _factor) {
        _factor = factor;
        await onLevelFactor?.call(factor);
      }
    }
    final key = level == EqLevel.volumeFactor ? filter : '$filter|$levelText';
    if (key == _applied) return;
    if (!hasOptions()) return;
    _applied = key;
    try {
      await setOption('af', filter);
      if (level == EqLevel.replayGainFallback) await setOption('replaygain-fallback', levelText);
      if (logChanges) debugPrint('HomeTunes: equaliser ${filter.isEmpty ? 'off' : 'on: $filter'}');
      onResult?.call(false);
    } catch (e) {
      // e.g. a device whose audio engine lacks the filter.
      debugPrint('HomeTunes: the $name refused the equaliser: $e');
      onResult?.call(true);
    }
  }
}
