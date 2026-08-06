package dev.raymond.voxwrite

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View
import kotlin.math.max

class VoiceWaveformView(context: Context) : View(context) {
    private val levels = FloatArray(28) { 0.08f }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF625AA8.toInt()
        style = Paint.Style.FILL
    }

    fun pushAmplitude(amplitudeDb: Double) {
        for (index in 0 until levels.lastIndex) {
            levels[index] = levels[index + 1]
        }
        levels[levels.lastIndex] = ((amplitudeDb + 55.0) / 45.0)
            .toFloat()
            .coerceIn(0.08f, 1f)
        invalidate()
    }

    fun reset() {
        levels.fill(0.08f)
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val gap = dp(4f)
        val barWidth = dp(4f)
        val totalWidth = levels.size * barWidth + (levels.size - 1) * gap
        var left = (width - totalWidth) / 2f
        val centerY = height / 2f
        val maximumHeight = height * 0.88f
        val minimumHeight = dp(3f)
        for (level in levels) {
            val barHeight = max(minimumHeight, maximumHeight * level)
            val radius = barWidth / 2f
            canvas.drawRoundRect(
                left,
                centerY - barHeight / 2f,
                left + barWidth,
                centerY + barHeight / 2f,
                radius,
                radius,
                paint
            )
            left += barWidth + gap
        }
    }

    private fun dp(value: Float): Float = value * resources.displayMetrics.density
}
