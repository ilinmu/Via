package com.autowifi.service

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.Icon
import kotlin.math.roundToInt

/**
 * Draws the same status icon as the macOS menu bar item: a Wi-Fi glyph plus
 * the connected role (P/B) while monitoring runs, and a stopped marker when
 * it does not.
 *
 * Android tints notification small icons, so the status bar variant uses a
 * slash for "stopped" instead of the red dot; the colored large icon keeps
 * the macOS look.
 */
object StatusIconRenderer {
    private const val RUNNING_COLOR = 0xFF0A84FF.toInt()
    private const val STOPPED_COLOR = 0xFFFF3B30.toInt()
    private const val MONO_COLOR = 0xFFFFFFFF.toInt()

    fun smallIcon(context: Context, running: Boolean, role: String): Icon {
        val size = dp(context, 24).coerceAtLeast(48)
        return Icon.createWithBitmap(render(size, MONO_COLOR, running, role, monochrome = true))
    }

    fun largeIcon(context: Context, running: Boolean, role: String): Bitmap =
        render(dp(context, 64).coerceAtLeast(96), RUNNING_COLOR, running, role, monochrome = false)

    private fun dp(context: Context, value: Int): Int =
        (value * context.resources.displayMetrics.density).roundToInt()

    private fun render(
        size: Int,
        color: Int,
        running: Boolean,
        role: String,
        monochrome: Boolean,
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawWifi(canvas, size, color)

        if (!running) {
            if (monochrome) {
                drawSlash(canvas, size, color)
            } else {
                val badge = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = STOPPED_COLOR }
                canvas.drawCircle(size * 0.78f, size * 0.78f, size * 0.13f, badge)
            }
        } else {
            val letter = when (role) {
                "priority" -> "P"
                "backup" -> "B"
                else -> null
            }
            if (letter != null) {
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    this.color = color
                    textSize = size * 0.40f
                    typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                    textAlign = Paint.Align.CENTER
                }
                canvas.drawText(letter, size * 0.78f, size * 0.86f, paint)
            }
        }
        return bitmap
    }

    private fun drawWifi(canvas: Canvas, size: Int, color: Int) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.STROKE
            strokeWidth = size * 0.085f
            strokeCap = Paint.Cap.ROUND
        }
        val cx = size * 0.43f
        val cy = size * 0.80f
        for (radius in floatArrayOf(size * 0.30f, size * 0.19f)) {
            canvas.drawArc(
                RectF(cx - radius, cy - radius, cx + radius, cy + radius),
                225f,
                90f,
                false,
                paint,
            )
        }
        val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        canvas.drawCircle(cx, cy, size * 0.055f, dot)
    }

    private fun drawSlash(canvas: Canvas, size: Int, color: Int) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.STROKE
            strokeWidth = size * 0.08f
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawLine(size * 0.14f, size * 0.18f, size * 0.72f, size * 0.88f, paint)
    }
}
