package dev.raymond.voxwrite

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1001)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.raymond.voxwrite/android_platform"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openTrimeSettings" -> {
                    val intent = packageManager.getLaunchIntentForPackage("com.osfans.trime")
                        ?: Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("https://github.com/osfans/trime")
                        )
                    startActivity(intent)
                    result.success(null)
                }
                "openInputMethodSettings" -> {
                    startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
                    result.success(null)
                }
                "showInputMethodPicker" -> {
                    val manager = getSystemService(Context.INPUT_METHOD_SERVICE)
                        as InputMethodManager
                    manager.showInputMethodPicker()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        val audioPlayback = AudioPlaybackController(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.raymond.voxwrite/audio_playback"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "beginCapture" -> {
                    audioPlayback.beginCapture()
                    result.success(null)
                }
                "endCapture" -> {
                    audioPlayback.endCapture()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
