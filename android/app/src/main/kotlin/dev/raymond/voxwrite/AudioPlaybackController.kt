package dev.raymond.voxwrite

import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent

class AudioPlaybackController(context: Context) {
    private val appContext = context.applicationContext
    private var wasMusicActive = false

    @Suppress("DEPRECATION")
    fun beginCapture() {
        val audioManager =
            appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        wasMusicActive = audioManager.isMusicActive
    }

    fun endCapture() {
        if (!wasMusicActive) return
        wasMusicActive = false
        Handler(Looper.getMainLooper()).postDelayed(
            { dispatchPlayToPreviousSession() },
            RESTORE_DELAY_MS
        )
    }

    private fun dispatchPlayToPreviousSession() {
        val audioManager =
            appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.dispatchMediaKeyEvent(
            KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY)
        )
        audioManager.dispatchMediaKeyEvent(
            KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY)
        )
    }

    private companion object {
        const val RESTORE_DELAY_MS = 180L
    }
}
