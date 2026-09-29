package com.hometunes.hometunes

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
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
                    else -> result.notImplemented()
                }
            }
    }
}
