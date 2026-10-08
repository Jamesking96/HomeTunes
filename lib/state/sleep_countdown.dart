// What the two sleep timers share (refactor phase 2, 8 Oct 2026): the music / audiobook timer
// (SleepTimer) and the video one (VideoSleepTimer) both count down four times a second, fade the
// volume out over Settings › Sleep timer's fade, pause, then put the volume back. Before, each
// had its own copy of all of that. Each timer now only says when its time is up (a number of
// minutes, the end of the song, chapter or video) and how to pause what it's watching.
import 'dart:async';

import 'package:flutter/foundation.dart';

/// The ticking, fading and pausing shared by the sleep timers. [M] is the timer's kinds of
/// stopping point (minutes, end of song…).
abstract class SleepCountdown<M extends Enum> extends ChangeNotifier {
  M? _mode;
  Timer? _tick;
  Duration? _remaining;
  // The volume just before the fade began, so it can be put back afterwards.
  double? _volumeBefore;

  bool get active => _mode != null;
  M? get mode => _mode;

  /// Time left before it pauses (null when off).
  Duration? get remaining => _remaining;

  /// The clock, swappable in tests (the timers read it too, so it isn't marked test-only).
  DateTime Function() now = DateTime.now;

  /// What the moon button does: turn the timer on if it's off, or off if it's on.
  void toggle() => active ? cancel() : start();

  /// Starts the timer (each timer works out its stopping point, then calls [run]).
  void start();

  // ---- what each timer supplies ----

  /// Time left until the timer fires; null (or zero) once its end has passed.
  @protected
  Duration? computeRemaining();

  /// Pauses what's playing when the time is up (and saves the book place, for books).
  @protected
  Future<void> stopPlayback();

  /// Whether the thing being faded is playing, and its volume.
  @protected
  bool get targetPlaying;
  @protected
  double get targetVolume;
  @protected
  Future<void> setTargetVolume(double v);

  /// The fade length in seconds (Settings › Sleep timer).
  @protected
  int get fadeSeconds;

  /// Run before each tick; returns true when the tick has been dealt with (the video timer
  /// stops here when its video page has closed).
  @protected
  bool beforeTick() => false;

  /// Whether the volume can be put back now (not when the video page has gone).
  @protected
  bool get canRestoreVolume => true;

  /// Clears the timer's own stopping point when it's turned off.
  @protected
  void clearStop() {}

  // ---- shared ----

  /// Turns the timer on in [mode]: ticks four times a second so the fade is smooth (the button
  /// itself only redraws when the whole seconds shown change, see [tick]).
  @protected
  void run(M mode) {
    _mode = mode;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
    tick();
    notifyListeners();
  }

  /// Turns it off (and puts the volume back if it was fading).
  void cancel() {
    _tick?.cancel();
    _tick = null;
    _restoreVolume();
    _mode = null;
    clearStop();
    _remaining = null;
    notifyListeners();
  }

  /// Checks the time left (four times a second while on).
  @visibleForTesting
  void tick() {
    if (beforeTick()) return;
    final r = computeRemaining();
    if (r == null || r <= Duration.zero) {
      _fire();
      return;
    }
    // Fade the volume down over the last few seconds: remember the starting volume once, then
    // scale it down in proportion to the time left.
    final fade = fadeSeconds;
    if (fade > 0 && targetPlaying && r.inMilliseconds <= fade * 1000) {
      _volumeBefore ??= targetVolume;
      setTargetVolume(_volumeBefore! * r.inMilliseconds / (fade * 1000));
    }
    // Only redraw the button when the whole seconds shown actually change, not every tick.
    final shownChanged = _remaining == null || _remaining!.inSeconds != r.inSeconds;
    _remaining = r;
    if (shownChanged) notifyListeners();
  }

  /// Time's up: stop ticking first (so a tick during the pause can't fire a second time),
  /// pause, then switch off (which also puts the volume back for next time).
  Future<void> _fire() async {
    _tick?.cancel();
    _tick = null;
    await stopPlayback();
    cancel();
  }

  void _restoreVolume() {
    final v = _volumeBefore;
    _volumeBefore = null;
    if (v != null && canRestoreVolume) setTargetVolume(v);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}
