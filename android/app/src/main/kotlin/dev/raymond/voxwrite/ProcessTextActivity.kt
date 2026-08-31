package dev.raymond.voxwrite

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Handles Android's system-wide "Process text" action without replacing the
 * selected text. A transparent Flutter surface synthesizes and plays it.
 */
class ProcessTextActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "processTextMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSelectedText" -> {
                    val selectedText = intent
                        ?.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
                        ?.toString()
                        .orEmpty()
                    result.success(selectedText)
                }
                "close" -> {
                    setResult(RESULT_CANCELED)
                    finish()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val CHANNEL_NAME = "dev.raymond.voxwrite/process_text"
    }
}
