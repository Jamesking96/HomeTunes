// Android's "may this app read your music?" permission, in one place.
// LibraryModel uses check() at start-up and when the app comes back to the front; the banner
// (ui/widgets/music_access_banner.dart) and Settings -> Library call request() / openSettings().
// Which permission to ask for depends on the Android version, which is read from the app's
// own `hometunes/app` MethodChannel (MainActivity.kt). On Windows everything is "allowed".
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

/// Whether HomeTunes may read the music (and audiobook) files on this device.
enum MusicAccess {
  allowed,  // files can be read

  /// Not granted (yet); asking again can show the system prompt.
  denied,

  /// Turned off in a way only the phone's Settings can change.
  blocked,
}

/// Android needs a permission to read audio files: "Music and audio"
/// (READ_MEDIA_AUDIO) on Android 13 and later, storage before that. Other
/// platforms don't.
class MusicPermission {
  static const _channel = MethodChannel('hometunes/app');
  // The Android version number (API level), asked for once and then remembered.
  static int? _sdk;

  static Future<int> _sdkInt() async {
    if (_sdk != null) return _sdk!;
    try {
      _sdk = await _channel.invokeMethod<int>('sdkInt') ?? 33;
    } catch (_) {
      _sdk = 33; // older app shell: assume a recent Android
    }
    return _sdk!;
  }

  /// The one permission that matters on this Android version. (Asking for the
  /// old storage permission on new Android comes back looking "fine" without
  /// actually allowing anything, which is how scanning silently broke.)
  static Future<Permission> _permission() async =>
      (await _sdkInt()) >= 33 ? Permission.audio : Permission.storage;

  /// Turns the plugin's many statuses into our three. "Limited" still lets us read files.
  static MusicAccess _from(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return MusicAccess.allowed;
    if (s.isPermanentlyDenied || s.isRestricted) return MusicAccess.blocked;
    return MusicAccess.denied;
  }

  /// Looks at the current state without showing any prompt.
  static Future<MusicAccess> check() async {
    if (!Platform.isAndroid) return MusicAccess.allowed;
    try {
      final p = await _permission();
      return _from(await PermissionHandlerPlatform.instance.checkPermissionStatus(p));
    } catch (_) {
      return MusicAccess.allowed; // can't tell: don't block the app
    }
  }

  /// Shows the system prompt if Android still allows it.
  static Future<MusicAccess> request() async {
    if (!Platform.isAndroid) return MusicAccess.allowed;
    try {
      final p = await _permission();
      final result = await PermissionHandlerPlatform.instance.requestPermissions([p]);
      return _from(result[p] ?? PermissionStatus.denied);
    } catch (_) {
      return MusicAccess.denied;
    }
  }

  /// Opens HomeTunes' page in the phone's Settings.
  static Future<bool> openSettings() => PermissionHandlerPlatform.instance.openAppSettings();
}
