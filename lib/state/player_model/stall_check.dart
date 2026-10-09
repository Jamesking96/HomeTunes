// Part of PlayerModel (refactor phase 11, 9 Oct 2026: player_model.dart was over 1,000 lines).
// Keeping "playing" honest: a song that says it's playing but doesn't move is restarted where it
// stopped (once a minute at most), and checked again when the app comes back to the front.
part of '../player_model.dart';

extension PlayerStallCheck on PlayerModel {
  /// Called every few seconds: if the screen says playing but the position hasn't moved for a
  /// while (and it isn't buffering or opening), playback has quietly stopped, for example after
  /// the phone put the app to sleep. Restart the song where it was; if that doesn't help within
  /// a minute, pause and say so, rather than pretending to play.
  Future<void> _checkProgress() async {
    final stuck = _stall.check(
      playing: playing,
      busy: buffering || _opening > 0 || queue.current == null,
      position: _player.position,
      now: DateTime.now(),
    );
    if (stuck) await _recoverStall();
  }

  Future<void> _recoverStall() async {
    final at = _player.position;
    final now = DateTime.now();
    final again = _lastRestart != null && now.difference(_lastRestart!) < const Duration(minutes: 1);
    if (again) {
      PlaybackLog.add('Still not moving after restarting: showing paused');
      pausedOnPurpose = true;
      lastError = 'Playback stopped by itself. Press play to carry on.';
      await _player.pause();
      _changed();
      return;
    }
    _lastRestart = now;
    PlaybackLog.add('Playing, but stuck at ${at.inSeconds} s: restarting the song there');
    _stall.reset();
    await _openCurrent(startAt: at);
  }

  /// When the app comes back to the screen: check playback really is moving (it may have been
  /// stopped while the app was asleep).
  Future<void> checkAfterResume() async {
    if (!playing) return;
    final before = _player.position;
    await Future<void>.delayed(const Duration(seconds: 3));
    if (playing && !buffering && _opening == 0 && queue.current != null && _player.position == before) {
      PlaybackLog.add('Back on screen, but playback isn\'t moving');
      await _recoverStall();
    }
  }
}
