package dev.raymond.voxwrite

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputConnection
import android.widget.Button
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
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
import java.util.concurrent.Executors

class VoxWriteInputMethodService : InputMethodService() {
    private enum class KeyboardMode {
        VOICE,
        PINYIN,
        ENGLISH
    }

    private val ink = Color.rgb(25, 25, 31)
    private val muted = Color.rgb(103, 103, 116)
    private val panel = Color.rgb(247, 247, 250)
    private val keyFill = Color.rgb(236, 236, 242)
    private val keyPressed = Color.rgb(225, 222, 242)
    private val accent = Color.rgb(98, 90, 168)
    private val accentSoft = Color.rgb(225, 222, 242)

    private val mainHandler = Handler(Looper.getMainLooper())
    private val lexiconExecutor = Executors.newSingleThreadExecutor()
    private val preferences by lazy {
        getSharedPreferences("voxwrite_ime_preferences", MODE_PRIVATE)
    }
    private val pinyinLearning by lazy {
        PinyinCandidateLearning.fromEncoded(
            preferences.getStringSet(PINYIN_LEARNING_PREFERENCE, emptySet()).orEmpty()
        )
    }
    private var flutterEngine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var inputRoot: LinearLayout? = null
    private var statusView: TextView? = null
    private var elapsedView: TextView? = null
    private var waveformView: VoiceWaveformView? = null
    private var recordButton: Button? = null
    private var candidateStrip: LinearLayout? = null
    private val voiceModeButtons = mutableMapOf<String, Button>()
    private val keyboardModeButtons = mutableMapOf<KeyboardMode, Button>()

    private var recording = false
    private var processing = false
    private var selectedMode = "dictation"
    private var keyboardMode = KeyboardMode.VOICE
    private var symbolLayout = false
    private var englishShift = true
    private var englishCapsLock = false
    private var lastShiftTapAt = 0L
    private val pinyinComposition = StringBuilder()
    private var currentCandidates: List<String> = emptyList()
    @Volatile private var pinyinLexicon: PinyinLexicon? = null
    @Volatile private var lexiconLoading = false
    @Volatile private var lexiconLoadFailed = false

    override fun onCreate() {
        super.onCreate()
        removeLegacyClipboardHistory()
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val engine = FlutterEngine(applicationContext)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "imeMain")
        )
        val methodChannel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            "dev.raymond.voxwrite/android_ime"
        )
        methodChannel.setMethodCallHandler(::handleDartCall)
        flutterEngine = engine
        channel = methodChannel
    }

    override fun onCreateInputView(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(8), dp(10), dp(8))
            setBackgroundColor(panel)
        }
        inputRoot = root
        applySystemBottomInset(root)
        renderKeyboard()
        return root
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        pinyinComposition.clear()
        currentCandidates = emptyList()
        keyboardMode = KeyboardMode.VOICE
        symbolLayout = false
        updateEnglishShiftFromEditor()
        if (inputRoot != null) renderKeyboard()
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        if (keyboardMode != KeyboardMode.VOICE) {
            commitRawPinyinIfNeeded()
            keyboardMode = KeyboardMode.VOICE
            symbolLayout = false
            renderKeyboard()
        }
    }

    override fun onEvaluateFullscreenMode(): Boolean = false

    private fun renderKeyboard() {
        val root = inputRoot ?: return
        root.removeAllViews()
        voiceModeButtons.clear()
        keyboardModeButtons.clear()
        statusView = null
        elapsedView = null
        waveformView = null
        recordButton = null
        candidateStrip = null

        root.addView(createHeader())
        when (keyboardMode) {
            KeyboardMode.VOICE -> addVoiceKeyboard(root)
            KeyboardMode.PINYIN -> {
                ensurePinyinLexiconLoaded()
                addTextKeyboard(root, pinyin = true)
            }
            KeyboardMode.ENGLISH -> addTextKeyboard(root, pinyin = false)
        }
        updateKeyboardModeButtons()
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

    private fun createHeader(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        row.addView(
            TextView(this).apply {
                text = "◉  VoxWrite"
                textSize = 18f
                setTextColor(ink)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER_VERTICAL
                contentDescription = "打开 VoxWrite"
                setOnClickListener { openMainApp() }
            },
            LinearLayout.LayoutParams(0, dp(46), 1f)
        )

        val switcher = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            background = rounded(Color.WHITE, 22)
            setPadding(dp(3), dp(3), dp(3), dp(3))
        }
        listOf(
            Triple("语音", KeyboardMode.VOICE, "切换到语音输入"),
            Triple("拼音", KeyboardMode.PINYIN, "切换到拼音键盘"),
            Triple("EN", KeyboardMode.ENGLISH, "切换到英语键盘")
        ).forEach { (label, mode, description) ->
            val button = compactButton(label).apply {
                textSize = 13f
                contentDescription = description
                setOnClickListener { switchKeyboardMode(mode) }
            }
            keyboardModeButtons[mode] = button
            switcher.addView(button, LinearLayout.LayoutParams(0, dp(38), 1f))
        }
        row.addView(switcher, LinearLayout.LayoutParams(dp(198), dp(44)))
        return row
    }

    private fun switchKeyboardMode(mode: KeyboardMode) {
        if (mode == keyboardMode || recording || processing) return
        commitRawPinyinIfNeeded()
        keyboardMode = mode
        symbolLayout = false
        if (mode == KeyboardMode.ENGLISH) updateEnglishShiftFromEditor()
        inputRoot?.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        renderKeyboard()
    }

    private fun updateKeyboardModeButtons() {
        keyboardModeButtons.forEach { (mode, button) ->
            val selected = mode == keyboardMode
            button.setTextColor(if (selected) Color.WHITE else muted)
            button.background = rounded(
                if (selected) accent else Color.TRANSPARENT,
                19
            )
            button.isEnabled = !recording && !processing
            button.contentDescription = if (selected) {
                "${button.contentDescription}，已选择"
            } else {
                button.contentDescription
            }
        }
    }

    private fun addVoiceKeyboard(root: LinearLayout) {
        root.addView(
            createVoiceModeRow(),
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(42)
            ).apply {
                topMargin = dp(4)
                marginStart = dp(34)
                marginEnd = dp(34)
            }
        )

        val statusRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        statusView = TextView(this).apply {
            text = "点击说话"
            textSize = 16f
            setTextColor(ink)
            gravity = Gravity.CENTER
        }
        elapsedView = TextView(this).apply {
            text = "00:00"
            textSize = 13f
            setTextColor(muted)
            gravity = Gravity.CENTER
        }
        statusRow.addView(Space(this), LinearLayout.LayoutParams(dp(58), 1))
        statusRow.addView(statusView, LinearLayout.LayoutParams(0, dp(40), 1f))
        statusRow.addView(elapsedView, LinearLayout.LayoutParams(dp(58), dp(40)))
        root.addView(statusRow)

        waveformView = VoiceWaveformView(this).apply { alpha = 0.18f }
        root.addView(
            waveformView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(30)
            )
        )
        // Text modes use four 50dp rows plus 4dp spacing. Give Voice mode
        // the same total content height by expanding the microphone section;
        // the button stays centered while switching modes no longer resizes
        // the input method window.
        root.addView(
            createMicrophoneRow(),
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(91)
            )
        )
        root.addView(createEditingRow())

        if (processing) {
            setProcessingState()
        } else {
            setRecordingState(recording, if (recording) "正在聆听；说完后会自动停止" else "点击说话")
        }
    }

    private fun createVoiceModeRow(): View {
        val modes = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            background = rounded(Color.WHITE, 21)
            setPadding(dp(3), dp(3), dp(3), dp(3))
        }
        listOf(
            "口述" to "dictation",
            "翻译" to "translation",
            "改写" to "ask"
        ).forEach { (label, mode) ->
            val button = compactButton(label).apply {
                textSize = 14f
                setOnClickListener {
                    selectedMode = mode
                    updateVoiceModeButtons()
                    statusView?.text = "已选择$label，点击说话"
                }
            }
            voiceModeButtons[mode] = button
            modes.addView(button, LinearLayout.LayoutParams(0, dp(36), 1f))
        }
        updateVoiceModeButtons()
        return modes
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

    private fun createMicrophoneRow(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        row.addView(Space(this), LinearLayout.LayoutParams(0, 1, 1f))
        recordButton = Button(this).apply {
            text = ""
            textSize = 30f
            isAllCaps = false
            minHeight = 0
            minimumHeight = 0
            contentDescription = "开始口述"
            setOnClickListener { toggleRecording() }
        }
        row.addView(recordButton, LinearLayout.LayoutParams(0, dp(64), 2.2f))
        row.addView(Space(this), LinearLayout.LayoutParams(0, 1, 1f))
        return row
    }

    private fun createEditingRow(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(6), dp(10), dp(6), 0)
        }
        row.addView(
            actionButton("换行") { sendEnter() },
            LinearLayout.LayoutParams(0, dp(48), 2f).apply { marginEnd = dp(8) }
        )
        row.addView(
            createVoiceDeleteButton(),
            LinearLayout.LayoutParams(0, dp(48), 1f).apply { marginEnd = dp(8) }
        )
        row.addView(
            actionButton("@") { currentInputConnection?.commitText("@", 1) },
            LinearLayout.LayoutParams(0, dp(48), 1f)
        )
        return row
    }

    private fun actionButton(label: String, action: () -> Unit): Button =
        compactButton(label).apply {
            textSize = if (label == "换行") 17f else 24f
            setTextColor(ink)
            background = keyBackground(22)
            setOnClickListener { action() }
        }

    private fun keyBackground(radiusDp: Int = 10): StateListDrawable =
        StateListDrawable().apply {
            addState(
                intArrayOf(android.R.attr.state_pressed),
                rounded(keyPressed, radiusDp)
            )
            addState(intArrayOf(), rounded(keyFill, radiusDp))
        }

    private fun createVoiceDeleteButton(): Button {
        val button = actionButton("⌫", ::deleteOneCharacter).apply {
            contentDescription = "删除；长按上滑清空全部内容"
        }
        val clearDistance = dp(48).toFloat()
        var downRawY = 0f
        var longPressActive = false
        var cleared = false
        val activateLongPress = Runnable {
            if (button.isPressed) {
                longPressActive = true
                button.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                statusView?.text = "继续上滑以清空全部内容"
            }
        }
        button.setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawY = event.rawY
                    longPressActive = false
                    cleared = false
                    view.isPressed = true
                    view.postDelayed(
                        activateLongPress,
                        ViewConfiguration.getLongPressTimeout().toLong()
                    )
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (
                        longPressActive &&
                        !cleared &&
                        downRawY - event.rawY >= clearDistance
                    ) {
                        cleared = clearAllText()
                        view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                        statusView?.text = if (cleared) {
                            "已清空全部内容"
                        } else {
                            "当前没有可清空内容"
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    view.removeCallbacks(activateLongPress)
                    view.isPressed = false
                    if (!longPressActive) {
                        view.performClick()
                    } else if (!cleared) {
                        statusView?.text = "已取消清空"
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    view.removeCallbacks(activateLongPress)
                    view.isPressed = false
                    if (longPressActive && !cleared) statusView?.text = "已取消清空"
                    true
                }
                else -> true
            }
        }
        return button
    }

    private fun addTextKeyboard(root: LinearLayout, pinyin: Boolean) {
        root.addView(
            createCandidateBar(pinyin),
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(46)
            ).apply { topMargin = dp(3) }
        )
        if (symbolLayout) {
            addSymbolRows(root, pinyin)
        } else {
            addLetterRows(root, pinyin)
        }
        if (pinyin) refreshPinyinCandidates()
    }

    private fun createCandidateBar(pinyin: Boolean): View {
        val scroller = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            background = rounded(Color.WHITE, 12)
            setPadding(dp(4), 0, dp(4), 0)
        }
        candidateStrip = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        scroller.addView(
            candidateStrip,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        if (!pinyin) {
            candidateStrip?.addView(candidateLabel("English · 本地键盘", muted, 14f))
        }
        return scroller
    }

    private fun addLetterRows(root: LinearLayout, pinyin: Boolean) {
        addCharacterRow(root, "qwertyuiop", pinyin)
        val second = keyboardRow().apply {
            addView(Space(this@VoxWriteInputMethodService), keyParams(0.45f))
            "asdfghjkl".forEach { addView(createCharacterKey(it, pinyin), keyParams()) }
            addView(Space(this@VoxWriteInputMethodService), keyParams(0.45f))
        }
        root.addView(second, rowParams())

        val third = keyboardRow()
        if (pinyin) {
            third.addView(
                createKeyboardKey("#+=") {
                    symbolLayout = true
                    renderKeyboard()
                }.apply { textSize = 16f },
                keyParams(1.35f)
            )
        } else {
            third.addView(createShiftKey(), keyParams(1.35f))
        }
        "zxcvbnm".forEach { third.addView(createCharacterKey(it, pinyin), keyParams()) }
        third.addView(createRepeatingDeleteKey(), keyParams(1.35f))
        root.addView(third, rowParams())
        root.addView(createBottomRow(pinyin), rowParams())
    }

    private fun addCharacterRow(root: LinearLayout, characters: String, pinyin: Boolean) {
        val row = keyboardRow()
        characters.forEach { row.addView(createCharacterKey(it, pinyin), keyParams()) }
        root.addView(row, rowParams())
    }

    private fun addSymbolRows(root: LinearLayout, pinyin: Boolean) {
        addSymbolRow(root, listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"))
        addSymbolRow(
            root,
            if (pinyin) {
                listOf("@", "#", "￥", "%", "&", "*", "（", "）", "—")
            } else {
                listOf("@", "#", "$", "%", "&", "*", "(", ")", "-")
            },
            sidePadding = true
        )
        val row = keyboardRow()
        val leadingSymbol = if (pinyin) "…" else "="
        row.addView(
            createKeyboardKey(leadingSymbol) { commitSymbol(leadingSymbol) },
            keyParams(1.35f)
        )
        val symbols = if (pinyin) {
            listOf("！", "？", "：", "；", "、", "《", "》")
        } else {
            listOf("!", "?", ":", ";", "'", "\"", "/")
        }
        symbols.forEach { symbol ->
            row.addView(createKeyboardKey(symbol) { commitSymbol(symbol) }, keyParams())
        }
        row.addView(createRepeatingDeleteKey(), keyParams(1.35f))
        root.addView(row, rowParams())
        root.addView(createBottomRow(pinyin), rowParams())
    }

    private fun addSymbolRow(
        root: LinearLayout,
        symbols: List<String>,
        sidePadding: Boolean = false
    ) {
        val row = keyboardRow()
        if (sidePadding) row.addView(Space(this), keyParams(0.45f))
        symbols.forEach { symbol ->
            row.addView(createKeyboardKey(symbol) { commitSymbol(symbol) }, keyParams())
        }
        if (sidePadding) row.addView(Space(this), keyParams(0.45f))
        root.addView(row, rowParams())
    }

    private fun createBottomRow(pinyin: Boolean): View = keyboardRow().apply {
        addView(
            createKeyboardKey(if (symbolLayout) "ABC" else "?123") {
                symbolLayout = !symbolLayout
                renderKeyboard()
            }.apply { textSize = 16f },
            keyParams(1.45f)
        )
        val comma = if (pinyin) "，" else ","
        val period = if (pinyin) "。" else "."
        addView(createKeyboardKey(comma) { commitSymbol(comma) }, keyParams())
        addView(
            createKeyboardKey(if (pinyin) "空格" else "space") { handleSpace() }.apply {
                textSize = 15f
                contentDescription = if (pinyin) "空格或选择首个候选词" else "空格"
            },
            keyParams(4.1f)
        )
        addView(createKeyboardKey(period) { commitSymbol(period) }, keyParams())
        addView(
            createKeyboardKey(editorActionLabel()) { sendEnter() }.apply {
                textSize = 15f
                contentDescription = "回车"
            },
            keyParams(1.45f)
        )
    }

    private fun keyboardRow(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
    }

    private fun rowParams(): LinearLayout.LayoutParams = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        dp(50)
    ).apply { topMargin = dp(4) }

    private fun keyParams(weight: Float = 1f): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, weight).apply {
            marginStart = dp(2)
            marginEnd = dp(2)
        }

    private fun createKeyboardKey(label: String, action: () -> Unit): Button =
        compactButton(label).apply {
            textSize = 20f
            setTextColor(ink)
            background = keyBackground()
            setOnClickListener {
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                action()
            }
        }

    private fun createCharacterKey(character: Char, pinyin: Boolean): Button {
        val label = if (!pinyin && (englishShift || englishCapsLock)) {
            character.uppercaseChar().toString()
        } else {
            character.toString()
        }
        return createKeyboardKey(label) { handleCharacter(character, pinyin) }.apply {
            contentDescription = label
        }
    }

    private fun createShiftKey(): Button {
        val active = englishShift || englishCapsLock
        return createKeyboardKey(if (englishCapsLock) "⇪" else "⇧") {
            val now = System.currentTimeMillis()
            if (englishCapsLock) {
                englishCapsLock = false
                englishShift = false
            } else if (englishShift && now - lastShiftTapAt < 450) {
                englishCapsLock = true
                englishShift = true
            } else {
                englishShift = !englishShift
            }
            lastShiftTapAt = now
            renderKeyboard()
        }.apply {
            background = if (active) rounded(accentSoft, 10) else keyBackground()
            contentDescription = when {
                englishCapsLock -> "大写锁定"
                englishShift -> "大写"
                else -> "切换大写"
            }
        }
    }

    private fun createRepeatingDeleteKey(): Button {
        val button = createKeyboardKey("⌫", ::handleKeyboardDelete).apply {
            contentDescription = "删除"
        }
        lateinit var repeat: Runnable
        repeat = Runnable {
            if (button.isPressed) {
                handleKeyboardDelete()
                mainHandler.postDelayed(repeat, 65)
            }
        }
        button.setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    view.isPressed = true
                    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    handleKeyboardDelete()
                    mainHandler.postDelayed(repeat, 420)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    mainHandler.removeCallbacks(repeat)
                    view.isPressed = false
                    true
                }
                else -> true
            }
        }
        return button
    }

    private fun handleCharacter(character: Char, pinyin: Boolean) {
        val connection = currentInputConnection ?: return
        if (pinyin) {
            if (pinyinComposition.length >= 48) return
            pinyinComposition.append(character.lowercaseChar())
            connection.setComposingText(pinyinComposition.toString(), 1)
            refreshPinyinCandidates()
            return
        }
        val output = if (englishShift || englishCapsLock) {
            character.uppercaseChar().toString()
        } else {
            character.toString()
        }
        connection.commitText(output, 1)
        if (englishShift && !englishCapsLock) {
            englishShift = false
            renderKeyboard()
        }
    }

    private fun handleKeyboardDelete() {
        val connection = currentInputConnection ?: return
        if (keyboardMode == KeyboardMode.PINYIN && pinyinComposition.isNotEmpty()) {
            pinyinComposition.deleteCharAt(pinyinComposition.lastIndex)
            if (pinyinComposition.isEmpty()) {
                connection.setComposingText("", 1)
                connection.finishComposingText()
            } else {
                connection.setComposingText(pinyinComposition.toString(), 1)
            }
            refreshPinyinCandidates()
        } else {
            deleteOneCharacter()
        }
    }

    private fun handleSpace() {
        if (keyboardMode == KeyboardMode.PINYIN && pinyinComposition.isNotEmpty()) {
            val first = currentCandidates.firstOrNull()
            if (first != null) {
                selectPinyinCandidate(first)
            } else {
                currentInputConnection?.commitText(pinyinComposition.toString(), 1)
                clearPinyinState()
            }
            return
        }
        currentInputConnection?.commitText(" ", 1)
        if (keyboardMode == KeyboardMode.ENGLISH) {
            englishShift = shouldCapitalizeEnglish()
            if (englishShift) renderKeyboard()
        }
    }

    private fun commitSymbol(symbol: String) {
        if (keyboardMode == KeyboardMode.PINYIN && pinyinComposition.isNotEmpty()) {
            commitBestPinyinCandidateOrRaw()
        }
        currentInputConnection?.commitText(symbol, 1)
        if (keyboardMode == KeyboardMode.ENGLISH && symbol in listOf(".", "!", "?")) {
            englishShift = true
            renderKeyboard()
        }
    }

    private fun sendEnter() {
        if (keyboardMode == KeyboardMode.PINYIN && pinyinComposition.isNotEmpty()) {
            commitRawPinyinIfNeeded()
            return
        }
        val connection = currentInputConnection ?: return
        val action = currentInputEditorInfo?.imeOptions?.and(EditorInfo.IME_MASK_ACTION)
            ?: EditorInfo.IME_ACTION_NONE
        if (action != EditorInfo.IME_ACTION_NONE &&
            action != EditorInfo.IME_ACTION_UNSPECIFIED) {
            connection.performEditorAction(action)
        } else {
            connection.commitText("\n", 1)
        }
        if (keyboardMode == KeyboardMode.ENGLISH) {
            englishShift = true
            if (!englishCapsLock) renderKeyboard()
        }
    }

    private fun editorActionLabel(): String {
        val action = currentInputEditorInfo?.imeOptions?.and(EditorInfo.IME_MASK_ACTION)
            ?: EditorInfo.IME_ACTION_NONE
        return when (action) {
            EditorInfo.IME_ACTION_GO -> "前往"
            EditorInfo.IME_ACTION_SEARCH -> "搜索"
            EditorInfo.IME_ACTION_SEND -> "发送"
            EditorInfo.IME_ACTION_NEXT -> "下一项"
            EditorInfo.IME_ACTION_DONE -> "完成"
            else -> "换行"
        }
    }

    private fun ensurePinyinLexiconLoaded() {
        if (pinyinLexicon != null || lexiconLoading) return
        lexiconLoading = true
        lexiconLoadFailed = false
        lexiconExecutor.execute {
            val loaded = runCatching { PinyinLexicon.load(assets) }.getOrNull()
            pinyinLexicon = loaded
            lexiconLoadFailed = loaded == null
            lexiconLoading = false
            mainHandler.post {
                if (keyboardMode == KeyboardMode.PINYIN) refreshPinyinCandidates()
            }
        }
    }

    private fun refreshPinyinCandidates() {
        val strip = candidateStrip ?: return
        strip.removeAllViews()
        val composition = pinyinComposition.toString()
        if (composition.isEmpty()) {
            currentCandidates = emptyList()
            strip.addView(candidateLabel("输入拼音，空格选择首词", muted, 14f))
            return
        }

        strip.addView(candidateLabel(composition, accent, 16f).apply {
            setTypeface(typeface, Typeface.BOLD)
        })
        val lexicon = pinyinLexicon
        if (lexicon == null) {
            currentCandidates = emptyList()
            strip.addView(
                candidateLabel(
                    if (lexiconLoadFailed) "离线词库不可用" else "词库加载中…",
                    muted,
                    14f
                )
            )
            return
        }
        currentCandidates = pinyinLearning
            .rerank(composition, lexicon.candidates(composition))
            .take(18)
        if (currentCandidates.isEmpty()) {
            strip.addView(candidateLabel("回车保留原拼音", muted, 14f))
            return
        }
        currentCandidates.forEachIndexed { index, candidate ->
            strip.addView(
                compactButton(candidate).apply {
                    textSize = 19f
                    setTextColor(ink)
                    background = keyBackground(10)
                    contentDescription = "候选词${index + 1}，$candidate"
                    setOnClickListener { selectPinyinCandidate(candidate) }
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    dp(38)
                ).apply {
                    marginStart = dp(3)
                    marginEnd = dp(3)
                }
            )
        }
    }

    private fun candidateLabel(text: String, color: Int, size: Float): TextView =
        TextView(this).apply {
            this.text = text
            textSize = size
            setTextColor(color)
            gravity = Gravity.CENTER
            setPadding(dp(12), 0, dp(12), 0)
        }

    private fun selectPinyinCandidate(candidate: String) {
        val connection = currentInputConnection ?: return
        val composition = pinyinComposition.toString()
        if (pinyinLearning.recordSelection(composition, candidate)) {
            preferences.edit()
                .putStringSet(
                    PINYIN_LEARNING_PREFERENCE,
                    pinyinLearning.encodedEntries()
                )
                .apply()
        }
        connection.commitText(candidate, 1)
        clearPinyinState()
    }

    private fun commitBestPinyinCandidateOrRaw() {
        if (pinyinComposition.isEmpty()) return
        val output = currentCandidates.firstOrNull() ?: pinyinComposition.toString()
        currentInputConnection?.commitText(output, 1)
        clearPinyinState()
    }

    private fun commitRawPinyinIfNeeded() {
        if (pinyinComposition.isEmpty()) return
        currentInputConnection?.commitText(pinyinComposition.toString(), 1)
        clearPinyinState()
    }

    private fun clearPinyinState() {
        pinyinComposition.clear()
        currentCandidates = emptyList()
        currentInputConnection?.finishComposingText()
        if (keyboardMode == KeyboardMode.PINYIN) refreshPinyinCandidates()
    }

    private fun updateEnglishShiftFromEditor() {
        englishCapsLock = false
        englishShift = shouldCapitalizeEnglish()
    }

    private fun shouldCapitalizeEnglish(): Boolean {
        val info = currentInputEditorInfo ?: return true
        if (info.inputType and InputType.TYPE_MASK_CLASS != InputType.TYPE_CLASS_TEXT) {
            return false
        }
        val before = currentInputConnection?.getTextBeforeCursor(2, 0)?.toString().orEmpty()
        return before.isBlank() || before.lastOrNull() in listOf('.', '!', '?', '\n')
    }

    private fun deleteOneCharacter() {
        val connection = currentInputConnection ?: return
        if (!connection.getSelectedText(0).isNullOrEmpty()) {
            if (!connection.commitText("", 1)) sendDeleteKeyEvents(connection)
            return
        }

        // Some OEM editors do not implement deleteSurroundingTextInCodePoints,
        // even though they expose it through InputConnection. Prefer the older,
        // widely supported UTF-16 API and preserve supplementary characters by
        // deleting both code units when the previous character is an emoji.
        val beforeCursor = connection.getTextBeforeCursor(2, 0)?.toString()
        val codeUnits = previousCodePointCodeUnitCount(beforeCursor)
        if (connection.deleteSurroundingText(codeUnits, 0)) return
        if (connection.deleteSurroundingTextInCodePoints(1, 0)) return
        sendDeleteKeyEvents(connection)
    }

    private fun sendDeleteKeyEvents(connection: InputConnection) {
        connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
        connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
    }

    private fun clearAllText(): Boolean {
        val connection = currentInputConnection ?: return false
        val extracted = connection.getExtractedText(ExtractedTextRequest(), 0)
        val extractedLength = extracted?.text?.length ?: 0
        val selectedText = connection.getSelectedText(0)
        val before = connection.getTextBeforeCursor(1_000_000, 0)?.length ?: 0
        val after = connection.getTextAfterCursor(1_000_000, 0)?.length ?: 0
        if (
            extractedLength == 0 &&
            selectedText.isNullOrEmpty() &&
            before == 0 &&
            after == 0
        ) {
            return false
        }

        connection.beginBatchEdit()
        return try {
            val selectedAll = connection.performContextMenuAction(android.R.id.selectAll)
            val positionedSelection = if (!selectedAll && extractedLength > 0) {
                connection.setSelection(
                    extracted!!.startOffset,
                    extracted.startOffset + extractedLength
                )
            } else {
                selectedAll
            }
            when {
                positionedSelection -> connection.commitText("", 1)
                !selectedText.isNullOrEmpty() -> connection.commitText("", 1)
                else -> connection.deleteSurroundingText(before, after)
            }
            true
        } finally {
            connection.endBatchEdit()
        }
    }

    private fun updateVoiceModeButtons() {
        voiceModeButtons.forEach { (mode, button) ->
            val selected = mode == selectedMode
            button.setTextColor(if (selected) Color.WHITE else muted)
            button.background = rounded(if (selected) accent else Color.TRANSPARENT, 18)
            button.contentDescription = if (selected) "${button.text}，已选择" else button.text
        }
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

    private fun rounded(color: Int, radiusDp: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            cornerRadius = dp(radiusDp).toFloat()
        }

    override fun onFinishInputView(finishingInput: Boolean) {
        commitRawPinyinIfNeeded()
        cancelActiveVoiceSession()
        super.onFinishInputView(finishingInput)
    }

    override fun onWindowHidden() {
        cancelActiveVoiceSession()
        super.onWindowHidden()
    }

    override fun onFinishInput() {
        commitRawPinyinIfNeeded()
        cancelActiveVoiceSession()
        super.onFinishInput()
    }

    private fun cancelActiveVoiceSession() {
        if (!recording && !processing) return
        channel?.invokeMethod("cancel", null)
        setRecordingState(false, "已取消")
    }

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        lexiconExecutor.shutdownNow()
        channel?.setMethodCallHandler(null)
        flutterEngine?.destroy()
        flutterEngine = null
        channel = null
        super.onDestroy()
    }

    private fun toggleRecording() {
        if (processing) return
        val methodChannel = channel ?: return
        if (!recording) {
            statusView?.text = "正在启动麦克风…"
            recordButton?.isEnabled = false
            val arguments = mapOf(
                "mode" to selectedMode,
                "selectedText" to currentInputConnection
                    ?.getSelectedText(0)
                    ?.toString()
            )
            methodChannel.invokeMethod("start", arguments, resultHandler {
                setRecordingState(true, "正在聆听；说完后会自动停止")
            })
        } else {
            setProcessingState()
            methodChannel.invokeMethod("stop", null, resultHandler { value ->
                val text = value as? String
                if (!text.isNullOrBlank()) commitText(text)
                setRecordingState(false, "已完成")
            })
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
                if (!text.isNullOrBlank()) commitText(text)
                setRecordingState(false, "已完成")
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

    private fun commitText(text: String) {
        val connection: InputConnection = currentInputConnection ?: return
        connection.commitText(text, 1)
    }

    private fun setRecordingState(active: Boolean, status: String) {
        recording = active
        processing = false
        recordButton?.isEnabled = true
        voiceModeButtons.values.forEach { it.isEnabled = !active }
        keyboardModeButtons.values.forEach { it.isEnabled = !active }
        updateRecordButtonStyle(active)
        statusView?.text = status
        waveformView?.alpha = if (active) 1f else 0.18f
        if (!active) {
            elapsedView?.text = "00:00"
            waveformView?.reset()
        }
        updateKeyboardModeButtons()
    }

    private fun setProcessingState() {
        recording = false
        processing = true
        statusView?.text = "正在识别并整理…"
        recordButton?.isEnabled = false
        voiceModeButtons.values.forEach { it.isEnabled = false }
        keyboardModeButtons.values.forEach { it.isEnabled = false }
        waveformView?.alpha = 0.35f
        updateKeyboardModeButtons()
    }

    private fun formatElapsed(elapsedMs: Long): String {
        val totalSeconds = elapsedMs / 1000
        return "%02d:%02d".format(totalSeconds / 60, totalSeconds % 60)
    }

    private fun openMainApp() {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun resultHandler(onSuccess: (Any?) -> Unit): MethodChannel.Result {
        return object : MethodChannel.Result {
            override fun success(result: Any?) = onSuccess(result)
            override fun error(code: String, message: String?, details: Any?) {
                setRecordingState(false, message ?: code)
            }
            override fun notImplemented() {
                setRecordingState(false, "输入法语音服务不可用")
            }
        }
    }

    private fun removeLegacyClipboardHistory() {
        preferences.edit().apply {
            remove("clipboard_history_count_v1")
            repeat(20) { remove("clipboard_history_item_v1_$it") }
        }.apply()
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val PINYIN_LEARNING_PREFERENCE = "pinyin_candidate_learning_v1"
    }
}
