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
  f.writeAsStringSync(s);
  stdout.writeln('  android: permissions added');

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
