// Two small helpers that keep playback honest, kept apart from the player so they can be tested
// without the audio engine.
//
// * [SystemPlayingState]: what to tell the phone's media controls. Android only keeps an app
//   running in the background (screen locked) while its media session says "playing". If the app
//   says "paused" even for a moment, the background permission is dropped, and a locked phone
//   won't let the app take it back when playback carries on. Android then puts the app to sleep,
//   the sound stops, and the screen still says playing. Opening each song makes the engine pause
//   for an instant, so a pause that the listener didn't ask for is only passed on after a few
//   seconds; a real pause (the button, the sleep timer, the end of the queue) is passed on at once.
// * [StallDetector]: notices when the player says it's playing but the position hasn't moved for
//   a while (not buffering or opening), so the player can restart the song where it was, or stop
//   pretending and show paused.

/// Decides whether the system media controls should show "playing".
class SystemPlayingState {
  /// How long a pause nobody asked for is hidden from the system.
  static const grace = Duration(seconds: 5);

  DateTime? _unexpectedSince;

  /// When the grace period ends, if one is running (so the caller can check again then).
  DateTime? get graceEndsAt => _unexpectedSince?.add(grace);

  /// [playing]: the engine is playing. [pausedOnPurpose]: the listener (or the sleep timer, or
  /// the end of the queue) paused it.
  bool report({required bool playing, required bool pausedOnPurpose, required DateTime now}) {
    if (playing || pausedOnPurpose) {
      _unexpectedSince = null;
      return playing;
    }
    _unexpectedSince ??= now;
    return now.difference(_unexpectedSince!) < grace;
  }
}

/// Spots playback that has quietly stopped.
class StallDetector {
  /// No movement for this long while "playing" counts as stuck.
  static const limit = Duration(seconds: 10);

  Duration? _lastPosition;
  DateTime? _lastMoved;

  /// Call every few seconds. [busy]: buffering or opening a file (no movement expected).
  /// Returns true once when playback is stuck (then starts counting again).
  bool check({required bool playing, required bool busy, required Duration position, required DateTime now}) {
    if (!playing || busy || position != _lastPosition || _lastMoved == null) {
      _lastPosition = position;
      _lastMoved = now;
      return false;
    }
    if (now.difference(_lastMoved!) < limit) return false;
    _lastMoved = now;
    return true;
  }

  /// Starts counting again (e.g. after a restart).
  void reset() {
    _lastPosition = null;
    _lastMoved = null;
  }
}
