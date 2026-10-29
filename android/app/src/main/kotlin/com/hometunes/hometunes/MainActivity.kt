package com.hometunes.hometunes

import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
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
        // Also tells Dart the Android version.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hometunes/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    // Which permission reads music files depends on the Android version.
                    "sdkInt" -> result.success(android.os.Build.VERSION.SDK_INT)
                    // Settings › About › Check for updates: open the release page in the browser
                    // (0.1.23). Only https links are opened.
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
                    // Android TV / Google TV (0.2.0): Dart switches to remote-friendly navigation and
                    // layout (services/device_kind.dart). TV mode, or the TV ("leanback") feature.
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
                    // TV sounds (0.2.5): the TV's own navigation and click sounds as the remote moves
                    // around HomeTunes and presses things. Settings › Appearance turns them off. The
                    // volume form plays whatever the TV's own "sound effects" setting says (HomeTunes'
                    // switch decides); -1 follows the media volume.
                    "playSound" -> {
                        val effect = when (call.argument<String>("sound")) {
                            "up" -> AudioManager.FX_FOCUS_NAVIGATION_UP
                            "down" -> AudioManager.FX_FOCUS_NAVIGATION_DOWN
                            "left" -> AudioManager.FX_FOCUS_NAVIGATION_LEFT
                            "right" -> AudioManager.FX_FOCUS_NAVIGATION_RIGHT
                            else -> AudioManager.FX_KEY_CLICK
                        }
                        val volume = (call.argument<Double>("volume") ?: -1.0).toFloat()
                        (getSystemService(Context.AUDIO_SERVICE) as AudioManager).playSoundEffect(effect, volume)
                        result.success(null)
                    }
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
