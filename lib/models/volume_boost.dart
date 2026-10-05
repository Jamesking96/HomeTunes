// Volume boost (0.1.61): play louder than 100 %, like VLC's volume going up to 500 %.
//
// Settings › Playback › "Volume boost" (off and 100 % by default) makes music, audiobooks and
// videos up to 5 times louder (500 % = 5 × the sound level, +14 dB). Very high boosts can
// distort, as in VLC: the engine amplifies, so loud parts clip.
//
// How each player gets louder (the engine is mpv 0.36, which has no "volume-gain"):
//  - music and audiobooks (PlayerModel): mpv's volume goes above 100. mpv's volume is cubic
//    (the sound level is (volume / 100)³), so the volume is multiplied by the cube root of the
//    boost ([boostVolumeScale]), and the engine's "volume-max" is raised to [engineVolumeMax];
//  - videos (the video page): media_kit's own controls set that player's volume directly, so
//    the boost goes into mpv's "replaygain-fallback" gain in decibels ([boostDb]) with the
//    equaliser's overall level, which the video page already sets there.
import 'dart:math' as math;

/// The boost range in percent, and the slider's steps.
const volumeBoostMin = 100;
const volumeBoostMax = 500;
const volumeBoostStep = 25;

/// mpv's highest volume while boosting: 100 × ∛5 ≈ 171, so 200 leaves room.
const engineVolumeMax = 200;

/// How many times louder (the sound level): 1 when the boost is off.
double boostFactor({required bool on, required int percent}) =>
    on ? percent.clamp(volumeBoostMin, volumeBoostMax) / 100 : 1.0;

/// What mpv's 0–100 volume is multiplied by for [factor] (mpv's volume is cubic).
double boostVolumeScale(double factor) => math.pow(factor, 1 / 3).toDouble();

/// [factor] in decibels (for the video player's gain).
double boostDb(double factor) => factor <= 1 ? 0 : 20 * math.log(factor) / math.ln10;
