package com.hometunes.hometunes

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
                    else -> result.notImplemented()
                }
            }
    }
}
