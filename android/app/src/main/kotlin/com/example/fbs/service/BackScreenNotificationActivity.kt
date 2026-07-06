package com.example.fbs.service

import android.app.Activity
import android.graphics.*
import android.os.*
import android.util.Log
import android.view.View
import android.view.WindowManager
import java.text.SimpleDateFormat
import java.util.*

/**
 * 背屏通知渲染 Activity — 运行在 display 1
 *
 * 支持两种模式:
 * - 普通通知: auto-dismiss after displayDurationMs
 * - 焦点通知 (isSticky=true): 不会自动消失，直到前端通知被清除/<Paste>
 *
 * 所有样式通过 Intent extras 传递，支持热更新 (onNewIntent).
 */
class BackScreenNotificationActivity : Activity() {

    companion object {
        private const val TAG = "BackScreenNotif"
    }

    private var renderView: NotificationRenderView? = null
    private var dismissHandler = Handler(Looper.getMainLooper())
    private var displayDurationMs = 10000L
    private var isSticky = false
    private var currentConfig: RenderConfig? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            Log.d(TAG, "onCreate display=${display?.displayId}")

            setupWindowFlags()
            currentConfig = parseIntent(intent)
            renderView = NotificationRenderView(this, currentConfig!!)
            renderView?.setBackgroundColor(currentConfig!!.backgroundColor)
            setContentView(renderView)
            renderView?.isClickable = false
            renderView?.isFocusable = false

            if (!isSticky) {
                scheduleAutoDismiss()
            }

            Log.d(TAG, "onCreate done, sticky=$isSticky key=${currentConfig?.notificationKey}")
        } catch (e: Exception) {
            Log.e(TAG, "onCreate failed", e)
            finish()
        }
    }

    /**
     * 支持通知更新: 当 Activity 已在前台时，通过 onNewIntent 更新内容
     * BackScreenController 先 am start 再 force-stop subscreencenter，
     * Activity 如果还在 display 1 就会收到 onNewIntent
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "onNewIntent: update notification content")

        try {
            currentConfig = parseIntent(intent)
            renderView?.updateConfig(currentConfig!!)
            renderView?.invalidate()

            // 重置 timer（如果是非粘性模式）
            dismissHandler.removeCallbacksAndMessages(null)
            if (!isSticky) {
                scheduleAutoDismiss()
            }
        } catch (e: Exception) {
            Log.e(TAG, "onNewIntent failed", e)
        }
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        Log.d(TAG, "onConfigChanged: w=${newConfig.screenWidthDp}dp h=${newConfig.screenHeightDp}dp")
        renderView?.requestLayout()
        renderView?.invalidate()
    }

    override fun onDestroy() {
        dismissHandler.removeCallbacksAndMessages(null)
        Log.d(TAG, "onDestroy, key=${currentConfig?.notificationKey}")
        super.onDestroy()
    }

    // ═══════════════════════════════════════════
    // 内部方法
    // ═══════════════════════════════════════════

    private fun setupWindowFlags() {
        try {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                or WindowManager.LayoutParams.FLAG_FULLSCREEN
                or WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
            )
            val lp = window.attributes
            lp.screenBrightness = -1.0f // 跟随系统亮度
            window.attributes = lp
        } catch (e: Exception) {
            Log.w(TAG, "Window flags error: ${e.message}")
        }
    }

    private fun parseIntent(intent: Intent): RenderConfig {
        val title = intent.getStringExtra("title") ?: ""
        val subtitle = intent.getStringExtra("subtitle") ?: ""
        val content = intent.getStringExtra("content") ?: ""
        val appName = intent.getStringExtra("appName") ?: ""
        val packageName = intent.getStringExtra("packageName") ?: ""
        val category = intent.getStringExtra("category") ?: ""
        val notificationKey = intent.getStringExtra("notificationKey") ?: ""

        isSticky = intent.getStringExtra("isSticky")?.toBooleanStrictOrNull() ?: false
        val isFocus = intent.getStringExtra("isFocus")?.toBooleanStrictOrNull() ?: false
        val notificationCount = intent.getStringExtra("notificationCount")?.toIntOrNull() ?: 1

        // 样式参数
        val titleFontSize = intent.getStringExtra("titleFontSize")?.toFloatOrNull() ?: 28f
        val subtitleFontSize = intent.getStringExtra("subtitleFontSize")?.toFloatOrNull() ?: 20f
        val contentFontSize = intent.getStringExtra("contentFontSize")?.toFloatOrNull() ?: 16f
        val countFontSize = intent.getStringExtra("countFontSize")?.toFloatOrNull() ?: 14f

        val titleColor = parseColorExtra("titleColor", Color.WHITE)
        val subtitleColor = parseColorExtra("subtitleColor", Color.parseColor("#B0B0B0"))
        val contentColor = parseColorExtra("contentColor", Color.parseColor("#E0E0E0"))
        val countColor = parseColorExtra("countColor", Color.parseColor("#888888"))
        val backgroundColor = parseColorExtra("backgroundColor", Color.parseColor("#1A1A2E"))

        val showAppIcon = intent.getStringExtra("showAppIcon")?.toBooleanStrictOrNull() ?: true
        val showTimestamp = intent.getStringExtra("showTimestamp")?.toBooleanStrictOrNull() ?: true
        val padding = intent.getStringExtra("padding")?.toFloatOrNull() ?: 24f
        val spacing = intent.getStringExtra("spacing")?.toFloatOrNull() ?: 12f

        displayDurationMs = if (isSticky) {
            Long.MAX_VALUE // 焦点通知不自动消失
        } else {
            intent.getStringExtra("displayDurationMs")?.toLongOrNull() ?: 10000L
        }

        Log.d(TAG, "Parsed: key=$notificationKey sticky=$isSticky focus=$isFocus "
            + "count=$notificationCount title=[$title] content=[${content.take(30)}] "
            + "dur=${if (isSticky) "infinite" else "${displayDurationMs}ms"}")

        return RenderConfig(
            title = if (title.isNotEmpty()) title else appName,
            subtitle = subtitle,
            content = content,
            appName = appName,
            packageName = packageName,
            category = category,
            notificationKey = notificationKey,
            isSticky = isSticky,
            isFocus = isFocus,
            notificationCount = notificationCount,
            titleFontSize = titleFontSize,
            subtitleFontSize = subtitleFontSize,
            contentFontSize = contentFontSize,
            countFontSize = countFontSize,
            titleColor = titleColor,
            subtitleColor = subtitleColor,
            contentColor = contentColor,
            countColor = countColor,
            backgroundColor = backgroundColor,
            showAppIcon = showAppIcon,
            showTimestamp = showTimestamp,
            showFoldCount = notificationCount > 1,
            padding = padding,
            spacing = spacing,
        )
    }

    private fun scheduleAutoDismiss() {
        if (displayDurationMs <= 0 || displayDurationMs == Long.MAX_VALUE) return
        dismissHandler.postDelayed({
            Log.d(TAG, "Auto-dismiss after ${displayDurationMs}ms")
            finish()
        }, displayDurationMs)
    }

    private fun parseColorExtra(key: String, default: Int): Int {
        val hex = intent.getStringExtra(key) ?: return default
        return try {
            val clean = hex.replace("#", "")
            if (clean.length == 6) Color.parseColor("#$clean") else default
        } catch (e: Exception) { default }
    }

    // ═══════════════════════════════════════════
    // 渲染配置
    // ═══════════════════════════════════════════

    data class RenderConfig(
        val title: String,
        val subtitle: String,
        val content: String,
        val appName: String,
        val packageName: String,
        val category: String,
        val notificationKey: String,
        val isSticky: Boolean,
        val isFocus: Boolean,
        val notificationCount: Int,
        val titleFontSize: Float,
        val subtitleFontSize: Float,
        val contentFontSize: Float,
        val countFontSize: Float,
        val titleColor: Int,
        val subtitleColor: Int,
        val contentColor: Int,
        val countColor: Int,
        val backgroundColor: Int,
        val showAppIcon: Boolean,
        val showTimestamp: Boolean,
        val showFoldCount: Boolean,
        val padding: Float,
        val spacing: Float,
    )

    // ═══════════════════════════════════════════
    // 自定义渲染 View — 支持动态更新
    // ═══════════════════════════════════════════

    class NotificationRenderView(
        context: android.content.Context,
        private var config: RenderConfig,
    ) : View(context) {

        private val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = config.titleColor; textSize = config.titleFontSize
            typeface = Typeface.DEFAULT_BOLD
        }
        private val subtitlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = config.subtitleColor; textSize = config.subtitleFontSize
        }
        private val contentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = config.contentColor; textSize = config.contentFontSize
        }
        private val timestampPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = (config.contentColor and 0x00FFFFFF) or 0x80000000.toInt()
            textSize = config.contentFontSize * 0.65f
        }
        private val foldCountPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = config.countColor; textSize = config.countFontSize
        }
        private val bgPaint = Paint().apply {
            color = config.backgroundColor; style = Paint.Style.FILL
        }
        private val stickyIndicatorPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = (config.titleColor and 0x00FFFFFF) or 0x30000000
            style = Paint.Style.FILL
        }
        private val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

        fun updateConfig(newConfig: RenderConfig) {
            this.config = newConfig
            titlePaint.color = config.titleColor
            titlePaint.textSize = config.titleFontSize
            subtitlePaint.color = config.subtitleColor
            subtitlePaint.textSize = config.subtitleFontSize
            contentPaint.color = config.contentColor
            contentPaint.textSize = config.contentFontSize
            foldCountPaint.color = config.countColor
            foldCountPaint.textSize = config.countFontSize
            bgPaint.color = config.backgroundColor
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0 || h <= 0) return

            val p = config.padding
            val s = config.spacing

            // 背景
            canvas.drawRect(0f, 0f, w, h, bgPaint)

            var y = p

            // 焦点通知指示器（顶部细条）
            if (config.isFocus || config.isSticky) {
                canvas.drawRect(p, y, w - p, y + 3f, stickyIndicatorPaint)
                y += s
            }

            // 标题行
            if (config.showAppIcon) {
                val iconSize = config.titleFontSize + 8f
                val iconRadius = iconSize * 0.22f
                val iconRect = RectF(p, y, p + iconSize, y + iconSize)

                // 应用名首字符
                val iconBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = (config.titleColor and 0x00FFFFFF) or 0x33000000
                    style = Paint.Style.FILL
                }
                canvas.drawRoundRect(iconRect, iconRadius, iconRadius, iconBgPaint)

                val firstChar = if (config.appName.isNotEmpty()) config.appName.first().toString() else "?"
                val iconTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = config.titleColor; textSize = iconSize * 0.4f
                    textAlign = Paint.Align.CENTER; typeface = Typeface.DEFAULT_BOLD
                }
                val cx = iconRect.centerX(); val cy = iconRect.centerY()
                canvas.drawText(firstChar, cx, cy + iconSize * 0.15f, iconTextPaint)

                val titleX = p + iconSize + s * 0.7f
                val titleBaseline = y + iconSize / 2f + config.titleFontSize / 2.5f
                canvas.drawText(config.title, titleX, titleBaseline, titlePaint)
                y += iconSize + s
            } else {
                canvas.drawText(config.title, p, y + config.titleFontSize, titlePaint)
                y += config.titleFontSize + s
            }

            // 副标题
            if (config.subtitle.isNotEmpty()) {
                canvas.drawText(config.subtitle, p, y + config.subtitleFontSize, subtitlePaint)
                y += config.subtitleFontSize + s
            }

            // 正文
            val maxWidth = w - p * 2
            val remainingHeight = h - y - p * 2
            if (config.content.isNotEmpty() && remainingHeight > config.contentFontSize) {
                val lines = fitTextLines(config.content, contentPaint, maxWidth, remainingHeight)
                for (line in lines) {
                    if (y + config.contentFontSize > h - p) break
                    canvas.drawText(line, p, y + config.contentFontSize, contentPaint)
                    y += config.contentFontSize + 4f
                }
            }

            // 底部: 折叠计数 / 时间戳
            val bottomY = h - p
            if (config.showFoldCount) {
                // 折叠计数居中
                val countText = "通知消息：${config.notificationCount}条"
                val countWidth = foldCountPaint.measureText(countText)
                val countX = (w - countWidth) / 2f
                canvas.drawText(countText, countX, bottomY, foldCountPaint)

                // 时间戳在右下角
                if (config.showTimestamp) {
                    val now = timeFormat.format(Date())
                    val tw = timestampPaint.measureText(now)
                    canvas.drawText(now, w - p - tw, bottomY, timestampPaint)
                }
            } else if (config.showTimestamp) {
                val now = timeFormat.format(Date())
                val tw = timestampPaint.measureText(now)
                canvas.drawText(now, w - p - tw, bottomY, timestampPaint)
            }
        }

        private fun fitTextLines(text: String, paint: Paint, maxWidth: Float, maxHeight: Float): List<String> {
            if (text.isEmpty()) return emptyList()
            if (paint.measureText(text) <= maxWidth) return listOf(text)

            val lines = mutableListOf<String>()
            var remaining = text
            while (remaining.isNotEmpty()) {
                if (lines.size * (paint.textSize + 4f) > maxHeight) {
                    val lastLine = lines.removeAt(lines.lastIndex)
                    lines.add(lastLine.trimEnd().dropLast(1) + "…")
                    break
                }
                var cut = remaining.length
                while (cut > 0 && paint.measureText(remaining.substring(0, cut)) > maxWidth) cut--
                if (cut == 0) cut = 1
                lines.add(remaining.substring(0, cut))
                remaining = remaining.substring(cut)
            }
            return lines
        }
    }
}
