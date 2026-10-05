// Volume boost: play louder than 100 %, like VLC's volume going up to 500 %.
//
// 0.1.61 had the Settings slider set a fixed boost. 0.1.62 (the user's choice): with the boost on,
// the Settings slider only sets how far the volume sliders go (100–500 %, off = 100 %), and
// every volume slider (the player bar, Now Playing, the phone's pop-up, the video bar and the
// video player's own) runs from 0 to that. Up to 100 % is the normal volume as before; above it
// the sound is amplified, so 500 % is 5 times as loud (+14 dB). Very high boosts can distort,
// as in VLC: loud parts clip.
//
// The engine is mpv 0.36. Its volume is cubic (the sound level is (volume / 100)³) and stops at
// 130 unless "volume-max" is raised, so a slider value above 100 is sent as 100 × ∛(value / 100)
// ([engineVolume]) with volume-max at [engineVolumeMax]; at or below 100 it's sent as it is, so
// nothing changes for normal listening. [sliderVolume] turns the engine's number back (the
// video player's volume lives in the engine, so its sliders read it from there).
import 'dart:math' as math;

/// The Settings slider's range in percent, and its steps.
const volumeBoostMin = 100;
const volumeBoostMax = 500;
const volumeBoostStep = 25;

/// mpv's highest volume while boosting: 100 × ∛5 ≈ 171, so 200 leaves room.
const engineVolumeMax = 200;

/// The top of the volume sliders: the boost's percentage when it's on, else 100.
double maxVolumeFor({required bool on, required int percent}) =>
    on ? percent.clamp(volumeBoostMin, volumeBoostMax).toDouble() : 100.0;

/// The engine's volume for a slider value (0 up to 500).
double engineVolume(double slider) {
  if (slider <= 100) return slider < 0 ? 0 : slider;
  return 100 * math.pow(slider / 100, 1 / 3).toDouble();
}

/// The slider value for the engine's volume (the reverse of [engineVolume]).
double sliderVolume(double engine) {
  if (engine <= 100) return engine < 0 ? 0 : engine;
  return 100 * math.pow(engine / 100, 3).toDouble();
}

/// The engine's volume after one step of [step] on the slider's scale (the mouse wheel, ↑ ↓),
/// kept between 0 and [max].
double stepEngineVolume(double engine, double step, double max) =>
    engineVolume((sliderVolume(engine) + step).clamp(0.0, max));
