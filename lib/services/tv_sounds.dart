// Sounds on the TV (0.2.5, the user, 29 Oct: "add a sound effect to play on the TV when we move
// around and interact with the menu"). The TV's own effects, played by Android (MainActivity.kt's
// "playSound"): a navigation sound in the direction the remote moved, and a click for OK and Back.
// Being the TV's own sounds they match its other menus and follow its volume; HomeTunes' switch
// (Settings › Appearance › Sounds on the TV) decides whether they play.
//
// TvFocus (ui/tv/tv_focus.dart) calls these: an arrow press plays only when something new took
// focus (not at a list's edge, and not while ← → move through a video), OK and Back always.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum TvSound { up, down, left, right, select, back }

class TvSounds {
  TvSounds._();

  static const _channel = MethodChannel('hometunes/app');

  /// Holding an arrow down repeats quickly: at most one sound this often.
  static const gap = Duration(milliseconds: 70);
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Tests see each sound here instead (the test machine isn't Android).
  @visibleForTesting
  static void Function(TvSound sound)? debugPlayed;

  static void play(TvSound sound) {
    final now = DateTime.now();
    if (now.difference(_last) < gap) return;
    _last = now;
    final seen = debugPlayed;
    if (seen != null) {
      seen(sound);
      return;
    }
    if (!Platform.isAndroid) return;
    // A sound that can't play (an older app shell) is simply not heard.
    _channel.invokeMethod<void>('playSound', {'sound': sound.name}).catchError((Object _) {});
  }

  /// Lets the next sound play straight away (tests press keys faster than [gap]).
  @visibleForTesting
  static void debugReset() => _last = DateTime.fromMillisecondsSinceEpoch(0);
}
