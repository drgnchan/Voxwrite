package dev.raymond.voxwrite

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class VoxWriteInputMethodService : InputMethodService() {
    private val ink = Color.rgb(25, 25, 31)
    private val muted = Color.rgb(103, 103, 116)
    private val panel = Color.rgb(247, 247, 250)
    private val keyFill = Color.rgb(236, 236, 242)
    private val keyPressed = Color.rgb(225, 222, 242)
    private val accent = Color.rgb(98, 90, 168)

    private val mainHandler = Handler(Looper.getMainLooper())
    private var flutterEngine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var audioPlaybackChannel: MethodChannel? = null
    private lateinit var audioPlayback: AudioPlaybackController

    private var inputRoot: LinearLayout? = null
    private var statusView: TextView? = null
    private var elapsedView: TextView? = null
    private var waveformView: VoiceWaveformView? = null
    private var recordButton: Button? = null
    private var cancelButton: Button? = null
    private val modeButtons = mutableMapOf<String, Button>()

    private var starting = false
    private var recording = false
    private var processing = false
    private var selectedMode = MODE_DICTATION
    private var viewGeneration = 0
    private var operationGeneration = 0

    override fun onCreate() {
        super.onCreate()
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val engine = FlutterEngine(applicationContext)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "voiceInputMain")
        )
        val methodChannel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            VOICE_INPUT_CHANNEL
        )
        methodChannel.setMethodCallHandler(::handleDartCall)

        audioPlayback = AudioPlaybackController(this)
        audioPlaybackChannel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            AUDIO_PLAYBACK_CHANNEL
        ).also { playbackChannel ->
            playbackChannel.setMethodCallHandler { call, result ->
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
        flutterEngine = engine
        channel = methodChannel
    }

    override fun onCreateInputView(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(6), dp(10), dp(6))
            setBackgroundColor(panel)
        }
        inputRoot = root
        applySystemBottomInset(root)
        renderVoiceInput()
        return root
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        selectedMode = MODE_DICTATION
        updateModeButtons()
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        val generation = ++viewGeneration
        mainHandler.postDelayed({
            if (
                generation == viewGeneration &&
                isInputViewShown &&
                !starting &&
                !recording &&
                !processing
            ) {
                startRecording()
            }
        }, AUTO_START_DELAY_MS)
    }

    override fun onEvaluateFullscreenMode(): Boolean = false

    private fun renderVoiceInput() {
        val root = inputRoot ?: return
        root.removeAllViews()
        modeButtons.clear()
        statusView = null
        elapsedView = null
        waveformView = null
        recordButton = null
        cancelButton = null

        root.addView(createHeader())
        root.addView(
            createModeSwitcher(),
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(40)
            ).apply {
                topMargin = dp(2)
                marginStart = dp(34)
                marginEnd = dp(34)
            }
        )

        val statusRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        statusView = TextView(this).apply {
            text = "正在准备语音输入…"
            textSize = 16f
            setTextColor(ink)
            gravity = Gravity.CENTER
            isSingleLine = true
        }
        elapsedView = TextView(this).apply {
            text = "00:00"
            textSize = 13f
            setTextColor(muted)
            gravity = Gravity.CENTER
        }
        statusRow.addView(Space(this), LinearLayout.LayoutParams(dp(58), 1))
        statusRow.addView(statusView, LinearLayout.LayoutParams(0, dp(34), 1f))
        statusRow.addView(elapsedView, LinearLayout.LayoutParams(dp(58), dp(34)))
        root.addView(statusRow)

        waveformView = VoiceWaveformView(this).apply { alpha = 0.18f }
        root.addView(
            waveformView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(22)
            )
        )
        root.addView(
            createMicrophoneRow(),
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(84)
            )
        )
        updateModeButtons()
        updateRecordButtonStyle(false)
    }

    private fun createHeader(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        row.addView(
            TextView(this).apply {
                text = "◉  VoxWrite Voice"
                textSize = 18f
                setTextColor(ink)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER_VERTICAL
                contentDescription = "打开 VoxWrite 设置"
                setOnClickListener { openMainApp() }
            },
            LinearLayout.LayoutParams(0, dp(40), 1f)
        )
        row.addView(
            compactButton("返回键盘").apply {
                textSize = 13f
                setTextColor(muted)
                background = keyBackground(16)
                contentDescription = "返回主输入法"
                setOnClickListener { leaveVoiceInput() }
            },
            LinearLayout.LayoutParams(dp(88), dp(34))
        )
        return row
    }

    private fun createModeSwitcher(): View {
        val switcher = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            background = rounded(Color.WHITE, 21)
            setPadding(dp(3), dp(3), dp(3), dp(3))
        }
        listOf("口述" to MODE_DICTATION, "翻译" to MODE_TRANSLATION).forEach { (label, mode) ->
            val button = compactButton(label).apply {
                textSize = 14f
                contentDescription = "$label 模式"
                setOnClickListener { selectMode(mode) }
            }
            modeButtons[mode] = button
            switcher.addView(button, LinearLayout.LayoutParams(0, dp(34), 1f))
        }
        return switcher
    }

    private fun createMicrophoneRow(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4), 0, dp(4), 0)
        }
        val cancelSlot = FrameLayout(this)
        cancelButton = compactButton("取消").apply {
            textSize = 13f
            setTextColor(muted)
            background = keyBackground(14)
            contentDescription = "取消录音并返回键盘"
            visibility = View.GONE
            setOnClickListener { cancelRecordingAndReturn() }
        }
        cancelSlot.addView(
            cancelButton,
            FrameLayout.LayoutParams(dp(60), dp(42), Gravity.CENTER)
        )
        row.addView(cancelSlot, LinearLayout.LayoutParams(dp(78), dp(64)))

        recordButton = Button(this).apply {
            text = ""
            textSize = 30f
            isAllCaps = false
            minHeight = 0
            minimumHeight = 0
            contentDescription = "开始口述"
            setOnClickListener { toggleRecording() }
        }
        row.addView(recordButton, LinearLayout.LayoutParams(0, dp(64), 1f))
        row.addView(Space(this), LinearLayout.LayoutParams(dp(78), 1))
        return row
    }

    private fun selectMode(mode: String) {
        if (processing || mode == selectedMode) return
        selectedMode = mode
        updateModeButtons()
        channel?.invokeMethod("setMode", mapOf("mode" to mode))
        statusView?.text = if (recording) {
            if (mode == MODE_TRANSLATION) "正在聆听 · 输出翻译" else "正在聆听 · 输出口述"
        } else {
            if (mode == MODE_TRANSLATION) "翻译模式 · 点击麦克风" else "口述模式 · 点击麦克风"
        }
    }

    private fun updateModeButtons() {
        modeButtons.forEach { (mode, button) ->
            val selected = mode == selectedMode
            button.setTextColor(if (selected) Color.WHITE else muted)
            button.background = rounded(
                if (selected) accent else Color.TRANSPARENT,
                18
            )
            button.isEnabled = !processing
        }
    }

    private fun startRecording() {
        if (starting || recording || processing) return
        val methodChannel = channel ?: return
        val operation = ++operationGeneration
        starting = true
        statusView?.text = "正在启动麦克风…"
        recordButton?.isEnabled = false
        cancelButton?.visibility = View.VISIBLE
        methodChannel.invokeMethod(
            "start",
            mapOf("mode" to selectedMode),
            resultHandler(operation) {
                setRecordingState(
                    true,
                    if (selectedMode == MODE_TRANSLATION) {
                        "正在聆听 · 输出翻译"
                    } else {
                        "正在聆听 · 自动停止"
                    }
                )
            }
        )
    }

    private fun toggleRecording() {
        if (processing || starting) return
        if (!recording) {
            startRecording()
            return
        }
        val methodChannel = channel ?: return
        val operation = ++operationGeneration
        setProcessingState()
        methodChannel.invokeMethod("stop", null, resultHandler(operation) { value ->
            val text = value as? String
            if (!text.isNullOrBlank()) {
                commitText(text)
                completeAndReturn()
            } else {
                setRecordingState(false, "已取消")
            }
        })
    }

    private fun cancelRecordingAndReturn() {
        val methodChannel = channel
        val operation = ++operationGeneration
        starting = false
        recording = false
        processing = true
        statusView?.text = "正在取消…"
        recordButton?.isEnabled = false
        cancelButton?.isEnabled = false
        if (methodChannel == null) {
            returnToPreviousInputMethod()
            return
        }
        methodChannel.invokeMethod("cancel", null, resultHandler(operation) {
            setRecordingState(false, "已取消")
            returnToPreviousInputMethod()
        })
    }

    private fun leaveVoiceInput() {
        if (starting || recording || processing) {
            cancelRecordingAndReturn()
        } else {
            returnToPreviousInputMethod()
        }
    }

    private fun handleDartCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasMicrophonePermission" -> {
                result.success(
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                )
            }
            "recordingProgress" -> {
                val elapsedMs = call.argument<Number>("elapsedMs")?.toLong() ?: 0L
                val amplitudeDb = call.argument<Number>("amplitudeDb")?.toDouble() ?: -80.0
                elapsedView?.text = formatElapsed(elapsedMs)
                waveformView?.pushAmplitude(amplitudeDb)
                result.success(null)
            }
            "showProcessing" -> {
                setProcessingState()
                result.success(null)
            }
            "commitText" -> {
                val text = call.argument<String>("text")
                if (!text.isNullOrBlank()) {
                    commitText(text)
                    completeAndReturn()
                }
                result.success(null)
            }
            "showError" -> {
                val message = call.argument<String>("message") ?: "语音处理失败"
                setRecordingState(false, message)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun completeAndReturn() {
        setRecordingState(false, "已写入")
        mainHandler.postDelayed(::returnToPreviousInputMethod, RETURN_DELAY_MS)
    }

    private fun commitText(text: String) {
        val connection: InputConnection = currentInputConnection ?: return
        connection.commitText(text, 1)
    }

    private fun setRecordingState(active: Boolean, status: String) {
        starting = false
        recording = active
        processing = false
        recordButton?.isEnabled = true
        cancelButton?.apply {
            isEnabled = true
            visibility = if (active) View.VISIBLE else View.GONE
        }
        updateRecordButtonStyle(active)
        statusView?.text = status
        waveformView?.alpha = if (active) 1f else 0.18f
        if (!active) {
            elapsedView?.text = "00:00"
            waveformView?.reset()
        }
        updateModeButtons()
    }

    private fun setProcessingState() {
        starting = false
        recording = false
        processing = true
        statusView?.text = "正在识别并整理…"
        cancelButton?.visibility = View.GONE
        recordButton?.isEnabled = false
        waveformView?.alpha = 0.35f
        updateModeButtons()
    }

    private fun updateRecordButtonStyle(active: Boolean) {
        recordButton?.apply {
            text = if (active) "■" else ""
            textSize = if (active) 25f else 30f
            if (active) {
                setCompoundDrawablesWithIntrinsicBounds(0, 0, 0, 0)
            } else {
                setCompoundDrawablesWithIntrinsicBounds(
                    0,
                    R.drawable.ic_voxwrite_mic,
                    0,
                    0
                )
            }
            setTextColor(Color.WHITE)
            background = rounded(if (active) accent else ink, 32)
            contentDescription = if (active) "停止并处理" else "开始口述"
        }
    }

    private fun returnToPreviousInputMethod() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if (switchToPreviousInputMethod()) return
            if (switchToNextInputMethod(false)) return
        }
        requestHideSelf(0)
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        viewGeneration++
        cancelActiveVoiceSession()
        super.onFinishInputView(finishingInput)
    }

    override fun onWindowHidden() {
        viewGeneration++
        cancelActiveVoiceSession()
        super.onWindowHidden()
    }

    override fun onFinishInput() {
        viewGeneration++
        cancelActiveVoiceSession()
        super.onFinishInput()
    }

    private fun cancelActiveVoiceSession() {
        if (!starting && !recording && !processing) return
        operationGeneration++
        channel?.invokeMethod("cancel", null)
        setRecordingState(false, "已取消")
    }

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        channel?.setMethodCallHandler(null)
        audioPlaybackChannel?.setMethodCallHandler(null)
        flutterEngine?.destroy()
        flutterEngine = null
        channel = null
        super.onDestroy()
    }

    private fun openMainApp() {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun resultHandler(
        operation: Int,
        onSuccess: (Any?) -> Unit
    ): MethodChannel.Result {
        return object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (operation == operationGeneration) onSuccess(result)
            }

            override fun error(code: String, message: String?, details: Any?) {
                if (operation == operationGeneration) {
                    setRecordingState(false, message ?: code)
                }
            }

            override fun notImplemented() {
                if (operation == operationGeneration) {
                    setRecordingState(false, "VoxWrite 语音服务不可用")
                }
            }
        }
    }

    private fun compactButton(label: String): Button = Button(this).apply {
        text = label
        isAllCaps = false
        isSingleLine = true
        includeFontPadding = false
        minWidth = 0
        minimumWidth = 0
        minHeight = 0
        minimumHeight = 0
        setPadding(dp(4), 0, dp(4), 0)
        elevation = 0f
        stateListAnimator = null
    }

    private fun keyBackground(radiusDp: Int = 10): StateListDrawable =
        StateListDrawable().apply {
            addState(
                intArrayOf(android.R.attr.state_pressed),
                rounded(keyPressed, radiusDp)
            )
            addState(intArrayOf(), rounded(keyFill, radiusDp))
        }

    private fun rounded(color: Int, radiusDp: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            cornerRadius = dp(radiusDp).toFloat()
        }

    private fun applySystemBottomInset(view: View) {
        val initialLeft = view.paddingLeft
        val initialTop = view.paddingTop
        val initialRight = view.paddingRight
        val initialBottom = view.paddingBottom
        ViewCompat.setOnApplyWindowInsetsListener(view) { target, insets ->
            val navigationBottom = insets.getInsets(
                WindowInsetsCompat.Type.navigationBars()
            ).bottom
            val gestureBottom = insets.getInsets(
                WindowInsetsCompat.Type.systemGestures()
            ).bottom
            val tappableBottom = insets.getInsets(
                WindowInsetsCompat.Type.tappableElement()
            ).bottom
            target.setPadding(
                initialLeft,
                initialTop,
                initialRight,
                initialBottom + maxOf(
                    navigationBottom,
                    gestureBottom,
                    tappableBottom
                )
            )
            insets
        }
        ViewCompat.requestApplyInsets(view)
    }

    private fun formatElapsed(elapsedMs: Long): String {
        val totalSeconds = elapsedMs / 1000
        return "%02d:%02d".format(totalSeconds / 60, totalSeconds % 60)
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private companion object {
        const val VOICE_INPUT_CHANNEL = "dev.raymond.voxwrite/android_voice_input"
        const val AUDIO_PLAYBACK_CHANNEL = "dev.raymond.voxwrite/audio_playback"
        const val MODE_DICTATION = "dictation"
        const val MODE_TRANSLATION = "translation"
        const val AUTO_START_DELAY_MS = 180L
        const val RETURN_DELAY_MS = 180L
    }
}
