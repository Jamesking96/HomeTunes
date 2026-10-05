// "Always on top" for the PC window (0.1.60).
//
// The user wanted a toggle that's always there and easy to click, to keep HomeTunes above other
// windows (handy for a video in a corner of the screen while working). Only a computer's window
// can do that, so it's Windows only (Linux could follow); on a phone the button isn't shown.
//
// The Windows side is a few lines in windows/runner/flutter_window.cpp: the "hometunes/window"
// channel's setAlwaysOnTop(true / false) calls SetWindowPos with HWND_TOPMOST or
// HWND_NOTOPMOST on the app's own window. (media_kit's full screen moves the window with
// HWND_TOP, which keeps it on top if it was, so full screen and the pin don't fight.)
// The choice is LibraryModel.alwaysOnTop, saved in settings.json and put back at start-up.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WindowPin {
  static const _channel = MethodChannel('hometunes/window');

  /// Tests set this to show the pin button (or hide it); null means "only on Windows".
  @visibleForTesting
  static bool? debugAvailable;

  /// Whether this device can keep the window on top (the PC app), so the button is shown.
  static bool get available =>
      debugAvailable ?? (Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST'));

  /// Keeps the window on top of other windows ([on]) or lets it go behind them again.
  static Future<void> set(bool on) async {
    if (!available || debugAvailable != null) return;
    try {
      await _channel.invokeMethod<bool>('setAlwaysOnTop', on);
    } on PlatformException catch (e) {
      debugPrint('HomeTunes: could not change "always on top": $e');
    } on MissingPluginException {
      // An older Windows build without the channel: nothing to do.
    }
  }
}
