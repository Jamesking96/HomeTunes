// The equaliser's data: the ten bands, a preset's slider positions, the
// presets that come with HomeTunes, and the audio-engine filter text a preset
// turns into.

import 'dart:math' as math;

/// The centre of each of the ten bands, in hertz: deep bass on the left, treble on the right.
const eqBands = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

/// How far each band slider goes up or down, in decibels.
const eqMaxGain = 12.0;

/// How far the overall level can be turned down (it never boosts).
const eqMinLevel = -12.0;

/// A band's label: "31", "1k", "16k".
String eqBandLabel(int hz) => hz >= 1000 ? '${hz ~/ 1000}k' : '$hz';

/// One equaliser setting: a gain for each band plus an overall level.
class EqPreset {
  final String id;
  final String name;

  /// Decibels for each of [eqBands], −12 to +12.
  final List<double> gains;

  /// Overall level in decibels, −12 to 0. Turning it down leaves room for
  /// boosted bands so loud music doesn't distort.
  final double level;

  /// Comes with HomeTunes (can be edited and restored, not deleted or renamed).
  final bool builtIn;

  const EqPreset({
    required this.id,
    required this.name,
    required this.gains,
    this.level = 0,
    this.builtIn = false,
  });

  /// True when it doesn't change the sound at all.
  bool get isFlat => level == 0 && gains.every((g) => g == 0);

  EqPreset copyWith({String? name, List<double>? gains, double? level}) => EqPreset(
        id: id,
        name: name ?? this.name,
        gains: gains ?? this.gains,
        level: level ?? this.level,
        builtIn: builtIn,
      );

  /// Same sound as [other] (names aside).
  bool soundsLike(EqPreset other) =>
      level == other.level && [for (var i = 0; i < eqBands.length; i++) gains[i] == other.gains[i]].every((x) => x);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'gains': gains, 'level': level};

  /// Reads a saved preset, fixing anything out of range or missing.
  static EqPreset fromJson(Map<String, dynamic> j, {bool builtIn = false}) {
    final raw = (j['gains'] as List? ?? const []).map((g) => (g as num?)?.toDouble() ?? 0).toList();
    return EqPreset(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? 'Preset',
      gains: [for (var i = 0; i < eqBands.length; i++) i < raw.length ? clampGain(raw[i]) : 0.0],
      level: clampLevel((j['level'] as num?)?.toDouble() ?? 0),
      builtIn: builtIn,
    );
  }

  static double clampGain(double g) => _round(g.clamp(-eqMaxGain, eqMaxGain).toDouble());
  static double clampLevel(double l) => _round(l.clamp(eqMinLevel, 0).toDouble());
  static double _round(double v) => (v * 2).round() / 2; // half-decibel steps
}

EqPreset _preset(String id, String name, List<double> gains, double level) =>
    EqPreset(id: id, name: name, gains: gains, level: level, builtIn: true);

/// The presets that come with HomeTunes, in the order they're shown. Each one
/// that boosts turns the overall level down by about as much, so it can't distort.
final List<EqPreset> builtInEqPresets = List.unmodifiable([
  _preset('flat', 'Flat', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 0),
  _preset('bass', 'Bass boost', [6, 5, 4, 2, 0, 0, 0, 0, 0, 0], -6),
  _preset('treble', 'Treble boost', [0, 0, 0, 0, 0, 1, 2, 4, 5, 6], -6),
  _preset('vocal', 'Vocal', [-3, -2, -1, 0, 2, 4, 4, 2, 0, -1], -4),
  _preset('rock', 'Rock', [5, 4, 2, -1, -2, -1, 2, 3, 4, 5], -5),
  _preset('pop', 'Pop', [-1, 1, 3, 4, 3, 0, -1, -1, 1, 2], -4),
  _preset('classical', 'Classical', [4, 3, 2, 1, 0, 0, 0, 1, 2, 3], -4),
  _preset('spoken', 'Spoken word', [-6, -4, -2, 0, 2, 3, 3, 2, 0, -2], -3),
  _preset('headphones', 'Headphones', [3, 2, 1, 0, -1, 0, 1, 2, 3, 2], -3),
]);

/// The built-in preset with [id], as it comes (before any edits).
EqPreset? builtInEqPreset(String id) {
  for (final p in builtInEqPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// The audio-engine filter for [p]: one peaking filter an octave wide per band
/// that isn't at 0. Empty when nothing needs changing. The overall level isn't
/// part of it; the player turns its volume down instead (see [eqLevelFactor]).
///
/// A file can only carry sounds up to half its [sampleRate], and the engine
/// rejects the whole equaliser if any band is above that (for example the
/// 16k band on a 22 kHz audiobook). So those bands are left out.
String eqFilter(EqPreset? p, {int? sampleRate}) {
  if (p == null) return '';
  final limit = sampleRate == null || sampleRate <= 0 ? null : sampleRate / 2;
  final parts = [
    for (var i = 0; i < eqBands.length; i++)
      if (p.gains[i] != 0 && (limit == null || eqBands[i] < limit))
        'equalizer=f=${eqBands[i]}:t=o:w=1:g=${p.gains[i].toStringAsFixed(1)}',
  ];
  return parts.isEmpty ? '' : 'lavfi=[${parts.join(',')}]';
}

/// How much to scale the volume for [p]'s overall level (1 = unchanged).
double eqLevelFactor(EqPreset? p) => p == null || p.level == 0 ? 1.0 : math.pow(10, p.level / 20).toDouble();
