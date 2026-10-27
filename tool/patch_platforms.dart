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
  _windows();
  _macos();
  _ios();
  // `flutter create` adds a counter-app test that doesn't apply here.
  final t = File('test/widget_test.dart');
  if (t.existsSync() && t.readAsStringSync().contains('MyApp')) t.deleteSync();
  stdout.writeln('Platform files patched.');
}

/// Android: adds permissions, the audio_service background-playback service, the TV launcher
/// entry and banner, HomeTunes' app icon, the MainActivity changes, the compileSdk level and a
/// "keep these icons" rule to the generated project.
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
    // Downloads (0.2.3, background_downloader): long downloads run as a "data sync" foreground
    // job with a notification, so Android doesn't stop them after 9 minutes; Wi-Fi only needs to
    // see the network state.
    '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>',
    '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
    '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>',
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
  // The name under the app's icon (0.2.0): "HomeTunes", not flutter create's lowercase project name.
  s = s.replaceFirst('android:label="hometunes"', 'android:label="HomeTunes"');
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
  // Downloads (0.2.3): WorkManager's foreground service, as a data-sync one (background_downloader's
  // "run in foreground" needs it declared by the app on Android 14+).
  if (!s.contains('androidx.work.impl.foreground.SystemForegroundService')) {
    s = s.replaceFirst('</application>', '''    <service android:name="androidx.work.impl.foreground.SystemForegroundService"
            android:foregroundServiceType="dataSync"
            tools:node="merge" />
    </application>''');
  }
  // Android TV / Google TV (0.2.0): the TV only lists apps that don't require a touchscreen and
  // that have a TV launcher entry, and shows a 320x180 banner for them on its home screen.
  // `required="false"` keeps the same APK installable on phones.
  const features = [
    '<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>',
    '<uses-feature android:name="android.software.leanback" android:required="false"/>',
  ];
  for (final feat in features) {
    final name = RegExp(r'android:name="([^"]+)"').firstMatch(feat)!.group(1)!;
    if (!s.contains('"$name"')) {
      s = s.replaceFirst('<application', '$feat\n    <application');
    }
  }
  if (!s.contains('android.intent.category.LEANBACK_LAUNCHER')) {
    s = s.replaceFirst('<category android:name="android.intent.category.LAUNCHER"/>',
        '<category android:name="android.intent.category.LAUNCHER"/>\n'
        '                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>');
  }
  if (!s.contains('android:banner')) {
    s = s.replaceFirst('<application', '<application\n        android:banner="@drawable/tv_banner"');
  }
  // HomeTunes' own pictures (0.2.0): the app icon in every size (plus the adaptive and themed
  // icon for newer Android) and the TV banner. They're kept in tool/assets/android/res, so a
  // regenerated android/ folder gets them back instead of Flutter's default icon.
  _copyAssets('tool/assets/android/res', 'android/app/src/main/res', 'android');
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
  if (old.contains('AudioServiceActivity') && old.contains('storageVolumes')) return;
  // Keep the file's own package line; the rest of the file is replaced wholesale below.
  final pkg = RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(old)?.group(1);
  if (pkg == null) return;
  f.writeAsStringSync('''package $pkg

import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
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
                    // Settings > About > Check for updates: open the release page (https only).
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url == null || !url.startsWith("https://")) {
                            result.error("bad_url", "Only https links can be opened", null)
                        } else {
                            try {
                                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                                result.success(null)
                            } catch (e: ActivityNotFoundException) {
                                result.error("no_browser", "No app can open links", null)
                            }
                        }
                    }
                    // Android TV / Google TV (0.2.0): remote-friendly navigation and layout.
                    "isTv" -> {
                        val ui = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                        result.success(
                            ui.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
                                packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                        )
                    }
                    // HomeTunes' own folder browser (0.2.0) starts from these: the device's own
                    // storage and any USB drive or SD card plugged in. Google TV has no system
                    // folder picker, so "Add folder" there uses the app's own.
                    "storageVolumes" -> result.success(storageVolumes())
                    else -> result.notImplemented()
                }
            }
    }

    /** Mounted storage volumes as {path, name, removable}; just the device's own before Android 7. */
    @Suppress("DEPRECATION")
    private fun storageVolumes(): List<Map<String, Any>> {
        val own = Environment.getExternalStorageDirectory().path
        if (Build.VERSION.SDK_INT < 24) return listOf(mapOf("path" to own, "name" to "Internal storage", "removable" to false))
        val sm = getSystemService(Context.STORAGE_SERVICE) as StorageManager
        val found = mutableListOf<Map<String, Any>>()
        for (v in sm.storageVolumes) {
            val state = v.state
            if (state != Environment.MEDIA_MOUNTED && state != Environment.MEDIA_MOUNTED_READ_ONLY) continue
            val path = try {
                when {
                    Build.VERSION.SDK_INT >= 30 -> v.directory?.path
                    v.isPrimary -> own
                    else -> StorageVolume::class.java.getMethod("getPath").invoke(v) as? String
                }
            } catch (e: Exception) {
                null
            } ?: continue
            found.add(mapOf("path" to path, "name" to v.getDescription(this), "removable" to v.isRemovable))
        }
        if (found.isEmpty()) found.add(mapOf("path" to own, "name" to "Internal storage", "removable" to false))
        return found
    }
}
''');
  stdout.writeln('  android: MainActivity updated');
}

/// Windows: HomeTunes' own icon (0.2.0) instead of Flutter's, kept in tool/assets/windows.
void _windows() {
  if (!Directory('windows/runner').existsSync()) return;
  _copyAssets('tool/assets/windows', 'windows/runner/resources', 'windows');
  // The name Windows shows (0.2.0): the window title (taskbar, Alt+Tab) and the program's
  // description and product name (Task Manager, the file's Properties). The file itself stays
  // hometunes.exe: the installer and the self-update look for it by that name.
  _replaceIn('windows/runner/main.cpp', 'window.Create(L"hometunes"', 'window.Create(L"HomeTunes"', 'windows');
  _replaceIn('windows/runner/Runner.rc', 'VALUE "FileDescription", "hometunes"', 'VALUE "FileDescription", "HomeTunes"', 'windows');
  _replaceIn('windows/runner/Runner.rc', 'VALUE "ProductName", "hometunes"', 'VALUE "ProductName", "HomeTunes"', 'windows');
  // Visual Studio 2026 (0.2.0): audio_service_win's C++/WinRT needs C++20 (see windows/CMakeLists.txt).
  final cmake = File('windows/CMakeLists.txt');
  if (cmake.existsSync()) {
    final s = cmake.readAsStringSync();
    const anchor = 'include(flutter/generated_plugins.cmake)';
    if (s.contains(anchor) && !s.contains('audio_service_win_plugin PRIVATE cxx_std_20')) {
      final nl = s.contains('\r\n') ? '\r\n' : '\n';
      final block = [
        '',
        '# audio_service_win (the Windows media controls) uses C++/WinRT, which in C++17 falls back to the',
        '# old experimental coroutines. Visual Studio 2026 (MSVC 14.51) no longer accepts those (error',
        '# STL1011), so that plugin is built as C++20, where C++/WinRT uses the standard ones (0.2.0).',
        'if(TARGET audio_service_win_plugin)',
        '  target_compile_features(audio_service_win_plugin PRIVATE cxx_std_20)',
        'endif()',
      ].join(nl);
      cmake.writeAsStringSync(s.replaceFirst(anchor, '$anchor$block'));
      stdout.writeln('  windows: audio_service_win built as C++20');
    }
  }
}

/// Replaces [from] with [to] in [path] if it's there (so it's safe to run again).
void _replaceIn(String path, String from, String to, String label) {
  final f = File(path);
  if (!f.existsSync()) return;
  final s = f.readAsStringSync();
  if (!s.contains(from)) return;
  f.writeAsStringSync(s.replaceFirst(from, to));
  stdout.writeln('  $label: ${path.split('/').last} updated');
}

/// Copies every file under [from] to the same place under [to], replacing the file there when it
/// differs (Flutter's default icon has the same name as HomeTunes' own).
void _copyAssets(String from, String to, String label) {
  final src = Directory(from);
  if (!src.existsSync()) return;
  var copied = 0;
  for (final f in src.listSync(recursive: true).whereType<File>()) {
    final rel = f.path.substring(src.path.length + 1);
    final dest = File('$to/$rel');
    final bytes = f.readAsBytesSync();
    if (dest.existsSync() && _same(dest.readAsBytesSync(), bytes)) continue;
    dest.parent.createSync(recursive: true);
    dest.writeAsBytesSync(bytes);
    copied++;
  }
  if (copied > 0) stdout.writeln('  $label: $copied icon / banner file(s) put in place');
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
