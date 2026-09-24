// Adds the permissions HomeTunes needs to the platform folders that
// `flutter create` generates. Safe to run more than once.
//
//   dart run tool/patch_platforms.dart
import 'dart:io';

void main() {
  _android();
  _macos();
  _ios();
  // `flutter create` adds a counter-app test that doesn't apply here.
  final t = File('test/widget_test.dart');
  if (t.existsSync() && t.readAsStringSync().contains('MyApp')) t.deleteSync();
  stdout.writeln('Platform files patched.');
}

void _android() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) return;
  var s = f.readAsStringSync();
  const perms = [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.READ_MEDIA_AUDIO"/>',
    '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>',
    // Background playback + media notification (audio_service).
    '<uses-permission android:name="android.permission.WAKE_LOCK"/>',
    '<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>',
    '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>',
  ];
  for (final p in perms) {
    final name = RegExp(r'android:name="([^"]+)"').firstMatch(p)!.group(1)!;
    if (!s.contains('"$name"')) {
      s = s.replaceFirst('<application', '$p\n    <application');
    }
  }
  // Plain http:// is common for home servers on the local network.
  if (!s.contains('usesCleartextTraffic')) {
    s = s.replaceFirst('<application', '<application\n        android:usesCleartextTraffic="true"');
  }
  if (!s.contains('requestLegacyExternalStorage')) {
    s = s.replaceFirst('<application', '<application\n        android:requestLegacyExternalStorage="true"');
  }
  // audio_service: the media playback service and the headset/media-button receiver.
  if (!s.contains('xmlns:tools=')) {
    s = s.replaceFirst('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ');
  }
  if (!s.contains('com.ryanheise.audioservice.AudioService"')) {
    s = s.replaceFirst('</application>', '''    <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
    </application>''');
  }
  f.writeAsStringSync(s);
  stdout.writeln('  android: manifest updated');

  _mainActivity();

  // permission_handler_android is built against API 37, so the app must be too.
  final g = File('android/app/build.gradle.kts');
  if (g.existsSync()) {
    final gs = g.readAsStringSync();
    final fixed = gs.replaceFirst(RegExp(r'compileSdk\s*=\s*[^\n]+'), 'compileSdk = 37');
    if (fixed != gs) {
      g.writeAsStringSync(fixed);
      stdout.writeln('  android: compileSdk set to 37');
    }
  }

  // Release builds strip images they think are unused; audio_service finds its
  // notification button icons by name, so without this the lock-screen
  // controls break (and Android stops playback when the screen locks).
  final keep = File('android/app/src/main/res/raw/keep.xml');
  if (!keep.existsSync()) {
    keep.parent.createSync(recursive: true);
    keep.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/audio_service_*" />
''');
    stdout.writeln('  android: keep.xml added for media control icons');
  }
}

/// MainActivity must extend AudioServiceActivity (so the media notification and
/// the app share one Flutter engine), and provides the "move to background"
/// hook used by the Back button on the Home screen.
void _mainActivity() {
  final dir = Directory('android/app/src/main/kotlin');
  if (!dir.existsSync()) return;
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('MainActivity.kt'))
      .toList();
  if (files.isEmpty) return;
  final f = files.first;
  final old = f.readAsStringSync();
  if (old.contains('AudioServiceActivity') && old.contains('sdkInt')) return;
  final pkg = RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(old)?.group(1);
  if (pkg == null) return;
  f.writeAsStringSync('''package $pkg

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Back on the Home screen: hide the app instead of closing it, so music keeps playing.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hometunes/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    // Which permission reads music files depends on the Android version.
                    "sdkInt" -> result.success(android.os.Build.VERSION.SDK_INT)
                    else -> result.notImplemented()
                }
            }
    }
}
''');
  stdout.writeln('  android: MainActivity updated');
}

void _macos() {
  for (final name in ['DebugProfile.entitlements', 'Release.entitlements']) {
    final f = File('macos/Runner/$name');
    if (!f.existsSync()) continue;
    var s = f.readAsStringSync();
    const keys = {
      'com.apple.security.network.client': '<true/>',
      'com.apple.security.files.user-selected.read-only': '<true/>',
    };
    keys.forEach((k, v) {
      if (!s.contains(k)) {
        s = s.replaceFirst('</dict>', '\t<key>$k</key>\n\t$v\n</dict>');
      }
    });
    f.writeAsStringSync(s);
  }
  stdout.writeln('  macos: entitlements checked');
}

void _ios() {
  final f = File('ios/Runner/Info.plist');
  if (!f.existsSync()) return;
  var s = f.readAsStringSync();
  if (!s.contains('NSAppTransportSecurity')) {
    // Allow http:// servers on the home network.
    const ats = '\t<key>NSAppTransportSecurity</key>\n\t<dict>\n\t\t<key>NSAllowsArbitraryLoads</key>\n\t\t<true/>\n\t</dict>\n';
    final i = s.lastIndexOf('</dict>');
    s = s.replaceRange(i, i, ats);
  }
  if (!s.contains('UIBackgroundModes')) {
    const bg = '\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>audio</string>\n\t</array>\n';
    final i = s.lastIndexOf('</dict>');
    s = s.replaceRange(i, i, bg);
  }
  f.writeAsStringSync(s);
  stdout.writeln('  ios: Info.plist checked');
}
