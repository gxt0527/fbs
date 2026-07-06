package com.example.fbs.service

import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
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
 * - 焦点通知 (isSticky=true): 不会自动消失，直到前端通知被清除
 *
 * 所有样式通过 Intent extras 传递，支持热更新 (onNewIntent).
 *
 * 注意: 字号参数以 sp 为单位传入，内部自动乘以 density 转换为 px 渲染。
 */
class BackScreenNotificationActivity : Activity() {

    companion object {
        private const val TAG = "BackScreenNotif"
        private const val SUBSCREEN_PACKAGE = "com.xiaomi.subscreencenter"

        /** 构建关闭背屏的 Intent 字符串，供 Shizuku 的 am start 使用 */
        fun buildDismissIntent(context: android.content.Context): String {
            return "am start -n ${context.packageName}/.service.BackScreenNotificationActivity" +
                " -f 0x20000000 --es dismiss \"true\" --user 0"
        }
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

            // 检查 dismiss 指令（防止 auto-dismiss 后重建）
            if (intent.getStringExtra("dismiss")?.toBooleanStrictOrNull() == true) {
                Log.d(TAG, "Dismiss on create, finishing immediately")
                finishAndRestore()
                return
            }

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
    @Suppress("DEPRECATION")
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "onNewIntent")

        // 检查 dismiss 指令
        if (intent.getStringExtra("dismiss")?.toBooleanStrictOrNull() == true) {
            Log.d(TAG, "Dismiss signal received, closing back screen")
            finishAndRestore()
            return
        }

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

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        Log.d(TAG, "onConfigChanged: w=${newConfig.screenWidthDp}dp h=${newConfig.screenHeightDp}dp")
        // 重新设置沉浸模式（配置变更后系统 UI 可见性可能会重置）
        setupImmersiveMode()
        renderView?.requestLayout()
        renderView?.invalidate()
    }

    override fun onBackPressed() {
        Log.d(TAG, "Back pressed, restoring subscreen")
        finishAndRestore()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            // 每次获得焦点时重新隐藏系统栏（防止系统弹回）
            setupImmersiveMode()
        }
    }

    override fun onDestroy() {
        dismissHandler.removeCallbacksAndMessages(null)
        Log.d(TAG, "onDestroy, key=${currentConfig?.notificationKey}")
        super.onDestroy()
    }

    // ═══════════════════════════════════════════
    // 背屏关闭 & 恢复
    // ═══════════════════════════════════════════

    /** 关闭本 Activity 并恢复系统背屏 */
    private fun finishAndRestore() {
        dismissHandler.removeCallbacksAndMessages(null)
        finish()
        // 异步触发系统背屏恢复，避免在 Activity 仍在 finalizing 阶段影响结果
        // 通过 BackScreenController 用 Shizuku 在 display 1 上启动 subscreencenter
        // 不指定 display 会落到主屏 (display 0)，所以必须走 Shizuku shell
        restoreSubscreen()
    }

    /** 恢复系统背屏 — 优先 Shizuku 在 display 1 启动，不可用时退化为本地 startActivity */
    private fun restoreSubscreen() {
        val controller = BackScreenController.instance
        if (controller != null) {
            Thread {
                try { controller.restoreSystemBackScreenOnSubscreen() }
                catch (e: Exception) { Log.e(TAG, "Shizuku restore subscreen failed", e) }
            }.apply { isDaemon = true }.start()
            Log.d(TAG, "Restore subscreen dispatched to BackScreenController")
            return
        }
        // controller 不可用（MainActivity 未初始化），退化为本地 startActivity
        try {
            val intent = packageManager.getLaunchIntentForPackage(SUBSCREEN_PACKAGE)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                Log.d(TAG, "Restored subscreen (fallback): $SUBSCREEN_PACKAGE")
            } else {
                Log.w(TAG, "Cannot find subscreen package: $SUBSCREEN_PACKAGE")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Restore subscreen fallback failed", e)
        }
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

            // 沉浸模式 — 彻底隐藏状态栏和导航栏
            setupImmersiveMode()
        } catch (e: Exception) {
            Log.w(TAG, "Window flags error: ${e.message}")
        }
    }

    private fun setupImmersiveMode() {
        try {
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            )
        } catch (e: Exception) {
            Log.w(TAG, "Immersive mode error: ${e.message}")
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

        // 样式参数（以 sp 为单位，渲染时会乘以 density）
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
        val cameraAvoidanceEnabled = intent.getStringExtra("cameraAvoidanceEnabled")?.toBooleanStrictOrNull() ?: false
        // 与 NotificationStyle.cameraAvoidanceOffset 保持一致
        val horizontalOffset = if (cameraAvoidanceEnabled) {
            intent.getStringExtra("horizontalOffset")?.toFloatOrNull() ?: 105f
        } else {
            0f
        }
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
            cameraAvoidanceEnabled = cameraAvoidanceEnabled,
            horizontalOffset = horizontalOffset,
            padding = padding,
            spacing = spacing,
        )
    }

    private fun scheduleAutoDismiss() {
        if (displayDurationMs <= 0 || displayDurationMs == Long.MAX_VALUE) return
        dismissHandler.postDelayed({
            Log.d(TAG, "Auto-dismiss after ${displayDurationMs}ms")
            finishAndRestore()
        }, displayDurationMs)
    }

    private fun parseColorExtra(key: String, default: Int): Int {
        val hex = intent.getStringExtra(key) ?: return default
        return try {
            val clean = hex.replace("#", "")
            // Flutter 的 Color.toARGB32().toRadixString(16) 输出 8 位 ARGB hex
            if (clean.length == 6 || clean.length == 8) Color.parseColor("#$clean") else default
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
        val cameraAvoidanceEnabled: Boolean,
        val horizontalOffset: Float,
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

        /** 屏幕密度因子，用于将 sp 值转换为 px */
        private val density: Float

        // 预创建的 Paint 对象在 updateConfig 中重设颜色/字号
        private val titlePaint: Paint
        private val subtitlePaint: Paint
        private val contentPaint: Paint
        private val timestampPaint: Paint
        private val foldCountPaint: Paint
        private val bgPaint: Paint
        private val iconBgPaint: Paint
        private val iconTextPaint: Paint
        private val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

        init {
            density = context.resources.displayMetrics.density
            Log.d(TAG, "RenderView init, density=$density")

            val tSize = config.titleFontSize * density
            val stSize = config.subtitleFontSize * density
            val cSize = config.contentFontSize * density
            val cntSize = config.countFontSize * density

            titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = config.titleColor; textSize = tSize
                typeface = Typeface.DEFAULT_BOLD
            }
            subtitlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = config.subtitleColor; textSize = stSize
            }
            contentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = config.contentColor; textSize = cSize
            }
            timestampPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#A0A0A0")
                textSize = cSize * 0.7f
            }
            foldCountPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = config.countColor; textSize = cntSize
            }
            bgPaint = Paint().apply {
                color = config.backgroundColor; style = Paint.Style.FILL
            }
            iconBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.FILL
            }
            iconTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = config.titleColor
                textAlign = Paint.Align.CENTER
                typeface = Typeface.DEFAULT_BOLD
            }
        }

        fun updateConfig(newConfig: RenderConfig) {
            this.config = newConfig
            val tSize = config.titleFontSize * density
            val stSize = config.subtitleFontSize * density
            val cSize = config.contentFontSize * density
            val cntSize = config.countFontSize * density

            titlePaint.color = config.titleColor
            titlePaint.textSize = tSize
            subtitlePaint.color = config.subtitleColor
            subtitlePaint.textSize = stSize
            contentPaint.color = config.contentColor
            contentPaint.textSize = cSize
            timestampPaint.textSize = cSize * 0.7f
            foldCountPaint.color = config.countColor
            foldCountPaint.textSize = cntSize
            bgPaint.color = config.backgroundColor
            iconTextPaint.color = config.titleColor
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0 || h <= 0) return

            // 将所有布局参数乘以 density（sp → px）
            val p = config.padding * density
            val s = config.spacing * density
            val ho = config.horizontalOffset * density // 避开摄像头时的水平偏移
            val leftPad = p + ho // 内容实际起始 x

            // 背景 — 始终全屏
            canvas.drawRect(0f, 0f, w, h, bgPaint)

            // 先计算内容总高度，用于垂直居中
            val contentHeight = measureContentHeight(w, p, s, leftPad)
            val topOffset = maxOf(p, (h - contentHeight) / 2f)
            var y = topOffset

            // 标题行（带应用图标圆角矩形）
            if (config.showAppIcon) {
                val iconSize = config.titleFontSize * density + 8f * density
                val iconRadius = iconSize * 0.2f
                val iconRect = RectF(leftPad, y, leftPad + iconSize, y + iconSize)

                // 图标背景
                iconBgPaint.color = (config.titleColor and 0x00FFFFFF) or 0x33000000.toInt()
                canvas.drawRoundRect(iconRect, iconRadius, iconRadius, iconBgPaint)

                // 应用名首字符
                val firstChar = if (config.appName.isNotEmpty()) config.appName.first().toString() else "?"
                iconTextPaint.textSize = iconSize * 0.45f
                val cx = iconRect.centerX()
                val cy = iconRect.centerY()
                canvas.drawText(firstChar, cx, cy + iconSize * 0.18f, iconTextPaint)

                // 标题文字紧随图标右侧
                val titleX = leftPad + iconSize + s * 0.6f
                val titleBaseline = y + iconSize / 2f + config.titleFontSize * density / 2.8f
                canvas.drawText(config.title, titleX, titleBaseline, titlePaint)
                y += iconSize + s
            } else {
                canvas.drawText(config.title, leftPad, y + config.titleFontSize * density, titlePaint)
                y += config.titleFontSize * density + s
            }

            // 副标题
            if (config.subtitle.isNotEmpty()) {
                canvas.drawText(config.subtitle, leftPad, y + config.subtitleFontSize * density, subtitlePaint)
                y += config.subtitleFontSize * density + s
            }

            // 正文 — 自动换行 + 截断
            val maxWidth = w - leftPad - p
            val remainingHeight = h - y - p
            if (config.content.isNotEmpty() && remainingHeight > contentPaint.textSize) {
                val lines = fitTextLines(config.content, contentPaint, maxWidth, remainingHeight)
                val lineHeight = contentPaint.textSize * 1.45f
                for (line in lines) {
                    if (y + contentPaint.textSize > h - p) break
                    canvas.drawText(line, leftPad, y + contentPaint.textSize, contentPaint)
                    y += lineHeight
                }
            }

            // 底部: 折叠计数 / 时间戳
            val bottomY = h - p
            if (config.showFoldCount) {
                val countText = "通知消息：${config.notificationCount}条"
                val countWidth = foldCountPaint.measureText(countText)
                val countX = (w - countWidth) / 2f
                canvas.drawText(countText, countX, bottomY, foldCountPaint)

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

        /**
         * 计算内容块的总高度，用于垂直居中。
         * 排除超出屏幕底部的部分。
         */
        private fun measureContentHeight(w: Float, p: Float, s: Float, leftPad: Float): Float {
            var h = p // 顶部 padding

            // 标题行
            if (config.showAppIcon) {
                h += config.titleFontSize * density + 8f * density + s
            } else {
                h += config.titleFontSize * density + s
            }

            // 副标题
            if (config.subtitle.isNotEmpty()) {
                h += config.subtitleFontSize * density + s
            }

            // 正文（按 3 行估算是典型的最大可见行数）
            if (config.content.isNotEmpty()) {
                val maxWidth = w - leftPad - p
                val estLines = if (contentPaint.measureText(config.content) > maxWidth) {
                    minOf(3, (contentPaint.measureText(config.content) / maxWidth).toInt() + 1)
                } else {
                    1
                }
                h += estLines * contentPaint.textSize * 1.45f + s * 0.5f
            }

            // 底部折叠计数/时间戳行
            h += if (config.showFoldCount || config.showTimestamp) {
                foldCountPaint.textSize + p
            } else {
                p
            }

            return h
        }

        private fun fitTextLines(text: String, paint: Paint, maxWidth: Float, maxHeight: Float): List<String> {
            if (text.isEmpty()) return emptyList()
            if (paint.measureText(text) <= maxWidth) return listOf(text)

            val lineHeight = paint.textSize * 1.45f
            val lines = mutableListOf<String>()
            var remaining = text
            while (remaining.isNotEmpty()) {
                if (lines.size * lineHeight > maxHeight) {
                    // 超出行数，截断最后一行
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
