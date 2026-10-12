// Which kind of device HomeTunes is running on, for the places that need to know: on a TV
// (Android TV / Google TV, 0.2.0) the app is driven with the remote's arrow keys and seen from the
// sofa, so later steps of the TV work read [DeviceKind.isTv] to switch on remote-friendly
// navigation and a larger layout.
//
// Asked once at start-up (main.dart) from the app's own `hometunes/app` channel: MainActivity.kt's
// "isTv" says yes when Android reports TV mode or the device has the TV ("leanback") feature.
// Anything else (Windows, Linux, a phone, or an older app shell without "isTv") counts as not a TV.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceKind {
  DeviceKind._();

  static const _channel = MethodChannel('hometunes/app');

  static bool _isTv = false;

  /// True on an Android TV / Google TV. False until [detect] has run, and on every other device.
  static bool get isTv => _isTv;

  /// Tests set this directly to draw screens as they'd look on a TV.
  @visibleForTesting
  static set debugIsTv(bool value) => _isTv = value;

  /// Asks Android whether this is a TV. Safe to call more than once. [android] is for tests
  /// (the test machine isn't Android); leave it out in the app.
  static Future<bool> detect({bool? android}) async {
    if (!(android ?? Platform.isAndroid)) return _isTv = false;
    try {
      _isTv = await _channel.invokeMethod<bool>('isTv') ?? false;
    } catch (_) {
      _isTv = false; // an older app shell that doesn't know "isTv"
    }
    return _isTv;
  }
}
