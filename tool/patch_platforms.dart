// Adds the permissions HomeTunes needs to the platform folders that
// `flutter create` generates. Safe to run more than once.
//
//   dart run tool/patch_platforms.dart
//
// Run by setup.ps1 / setup.sh straight after `flutter create`. The platform folders (android/,
// macos/, ios/ ...) aren't kept in the repo, so every change HomeTunes needs in them lives here.
// Each step first checks whether its change is already there, which is what makes it safe to
// re-run. Paths are relative, so it must be run from the project root.
import 'dart:io';

/// Patches each platform folder that exists, then removes Flutter's sample test.
void main() {
  _android();
  _macos();
  _ios();
  // `flutter create` adds a counter-app test that doesn't apply here.
  final t = File('test/widget_test.dart');
  if (t.existsSync() && t.readAsStringSync().contains('MyApp')) t.deleteSync();
  stdout.writeln('Platform files patched.');
}

/// Android: adds permissions, the audio_service background-playback service, the MainActivity
/// changes, the compileSdk level and a "keep these icons" rule to the generated project.
void _android() {
  // If the Android folder wasn't generated (e.g. a desktop-only setup), there's nothing to do.
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) return;
  var s = f.readAsStringSync();
  // INTERNET for the Subsonic server and online lookups; READ_MEDIA_AUDIO (Android 13+) and
  // READ_EXTERNAL_STORAGE (Android 12 and older) to read the music folder.
  const perms = [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.READ_MEDIA_AUDIO"/>',
  // READ_MEDIA_VIDEO (0.1.40): the Videos tab and music videos (Android 13+ hides video files
  // from an app that only has READ_MEDIA_AUDIO).
  '<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>',
    '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>',
    // Background playback + media notification (audio_service).
    '<uses-permission android:name="android.permission.WAKE_LOCK"/>',
    '<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>',
    '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>',
  ];
  // Add each permission only if the manifest doesn't already mention it, inserting it just
  // above the <application> tag.
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
  // HomeTunes (0.1.21, security review #5): no Google cloud backup and no copying during
  // new-phone setup. People move their data with a HomeTunes backup (.htbackup) instead.
  if (!s.contains('android:allowBackup')) {
    s = s.replaceFirst('<application',
        '<application\n        android:allowBackup="false"\n        android:fullBackupContent="false"\n        android:dataExtractionRules="@xml/data_extraction_rules"');
  }
  final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml');
  if (!rules.existsSync()) {
    rules.parent.createSync(recursive: true);
    const domains = ['root', 'file', 'database', 'sharedpref', 'external'];
    String block(String tag) =>
        '    <$tag>\n${domains.map((d) => '        <exclude domain="$d" path="." />').join('\n')}\n    </$tag>';
    rules.writeAsStringSync('<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- HomeTunes: nothing goes to cloud backup or device transfer (see patch_platforms.dart). -->\n'
        '<data-extraction-rules>\n${block('cloud-backup')}\n${block('device-transfer')}\n</data-extraction-rules>\n');
    stdout.writeln('  android: data_extraction_rules.xml added');
  }
  // Lets Android 10 read the music folder by file path in the old way.
  if (!s.contains('requestLegacyExternalStorage')) {
    s = s.replaceFirst('<application', '<application\n        android:requestLegacyExternalStorage="true"');
  }
  // audio_service: the media playback service and the headset/media-button receiver.
  // The tools: namespace is needed for the tools:ignore="..." attributes added below.
  if (!s.contains('xmlns:tools=')) {
    s = s.replaceFirst('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ');
  }
  // Declare the service and the button receiver just before </application>.
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
  // "Compile SDK" = which Android version's toolkit the app is built with (not the minimum
  // Android version it runs on).
  final g = File('android/app/build.gradle.kts');
  if (g.existsSync()) {
    final gs = g.readAsStringSync();
    var fixed = gs.replaceFirst(RegExp(r'compileSdk\s*=\s*[^\n]+'), 'compileSdk = 37');
    // HomeTunes (0.1.21, security review #1): sign release builds with the key named in
    // android/key.properties (never committed), never with the debug key.
    if (!fixed.contains('key.properties')) {
      fixed = 'import java.util.Properties\n\n$fixed'
          .replaceFirst('android {', '${_signingSetup}android {')
          .replaceFirst(RegExp(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)'),
              'if (keystorePropertiesFile.exists()) signingConfig = signingConfigs.getByName("release")')
          .replaceFirst('    buildTypes {', '$_signingConfigs    buildTypes {');
      stdout.writeln('  android: release signing set up (needs android/key.properties)');
    }
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

/// Reads android/key.properties (see android/app/build.gradle.kts for its format).
const _signingSetup = '''val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any { it.project == project && it.name.contains("Release") }
    if (wantsRelease && !keystorePropertiesFile.exists()) {
        throw GradleException("android/key.properties is missing, so this release build can't be signed with the HomeTunes release key.")
    }
}

''';

/// The "release" signing config, made from android/key.properties.
const _signingConfigs = '''    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

''';

/// MainActivity must extend AudioServiceActivity (so the media notification and
/// the app share one Flutter engine), and provides the "move to background"
/// hook used by the Back button on the Home screen.
void _mainActivity() {
  final dir = Directory('android/app/src/main/kotlin');
  if (!dir.existsSync()) return;
  // flutter create puts MainActivity.kt in a folder named after the package
  // (com/hometunes/hometunes/...), so search for it rather than guessing the path.
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('MainActivity.kt'))
      .toList();
  if (files.isEmpty) return;
  final f = files.first;
  final old = f.readAsStringSync();
  // Already patched (both parts present), so leave the file alone.
  if (old.contains('AudioServiceActivity') && old.contains('sdkInt')) return;
  // Keep the file's own package line; the rest of the file is replaced wholesale below.
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

/// macOS: the app sandbox needs permission for network access (the server) and for reading
/// folders the user picks (the music folder).
void _macos() {
  for (final name in ['DebugProfile.entitlements', 'Release.entitlements']) {
    final f = File('macos/Runner/$name');
    if (!f.existsSync()) continue;
    var s = f.readAsStringSync();
    const keys = {
      'com.apple.security.network.client': '<true/>',
      'com.apple.security.files.user-selected.read-only': '<true/>',
    };
    // Add each missing key/value pair just before the first </dict>.
    keys.forEach((k, v) {
      if (!s.contains(k)) {
        s = s.replaceFirst('</dict>', '\t<key>$k</key>\n\t$v\n</dict>');
      }
    });
    f.writeAsStringSync(s);
  }
  stdout.writeln('  macos: entitlements checked');
}

/// iOS: allow plain http:// servers and keep playing audio in the background.
void _ios() {
  final f = File('ios/Runner/Info.plist');
  if (!f.existsSync()) return;
  var s = f.readAsStringSync();
  if (!s.contains('NSAppTransportSecurity')) {
    // Allow http:// servers on the home network.
    const ats = '\t<key>NSAppTransportSecurity</key>\n\t<dict>\n\t\t<key>NSAllowsArbitraryLoads</key>\n\t\t<true/>\n\t</dict>\n';
    // Insert before the last </dict>, i.e. at the end of the top-level settings dictionary.
    final i = s.lastIndexOf('</dict>');
    s = s.replaceRange(i, i, ats);
  }
  // "audio" background mode keeps playback going when the app isn't on screen.
  if (!s.contains('UIBackgroundModes')) {
    const bg = '\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>audio</string>\n\t</array>\n';
    final i = s.lastIndexOf('</dict>');
    s = s.replaceRange(i, i, bg);
  }
  f.writeAsStringSync(s);
  stdout.writeln('  ios: Info.plist checked');
}
