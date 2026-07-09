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
 * 由 BackScreenController 通过 am start --display 1 启动，
 * 使用 Canvas 自定义绘制通知内容。
 * 所有样式参数通过 Intent extras 传递。
 */
class BackScreenNotificationActivity : Activity() {

    companion object {
        private const val TAG = "BackScreenNotif"
        private const val LUX_THRESHOLD = 5.0f
        private const val AOD_DELAY_MS = 8000L
        private const val SLEEP_TIMEOUT_MS = 300_000L
    }

    private var renderView: NotificationRenderView? = null
    private var wakeLock: android.os.PowerManager.WakeLock? = null
    private var isInAodMode = false
    private var dismissHandler = Handler(Looper.getMainLooper())
    private var displayDurationMs = 10000L
    private var sensorManager: android.hardware.SensorManager? = null
    private var lastLux = -1f
    private var darkSinceMs = 0L
    private val sensorListener = object : android.hardware.SensorEventListener {
        override fun onSensorChanged(event: android.hardware.SensorEvent) {
            val lux = event.values[0]; lastLux = lux
            if (lux < LUX_THRESHOLD) {
                if (darkSinceMs == 0L) darkSinceMs = System.currentTimeMillis()
                val dur = System.currentTimeMillis() - darkSinceMs
                if (dur >= SLEEP_TIMEOUT_MS && !isFinishing) { finish()
                } else if (dur >= AOD_DELAY_MS && !isInAodMode) { enterAodMode() }
            } else {
                if (isInAodMode) exitAodMode(); darkSinceMs = 0L
            }
        }
        override fun onAccuracyChanged(s: android.hardware.Sensor?, a: Int) {}
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            Log.d(TAG, "onCreate start, display=${display?.displayId}")

            // ── 全屏设置：跟随系统亮度，不要强制唤醒（避免亮屏闪烁） ──
            try {
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                    or WindowManager.LayoutParams.FLAG_FULLSCREEN
                    or WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                )
                // -1 = 跟随系统亮度（AOD 模式自适性）
                val lp = window.attributes
                lp.screenBrightness = -1.0f
                window.attributes = lp
            } catch (e: Exception) {
                Log.w(TAG, "Window flags error: ${e.message}")
            }

            // ── 解析 Intent extras ──
            val title = intent.getStringExtra("title") ?: ""
            val subtitle = intent.getStringExtra("subtitle") ?: ""
            val content = intent.getStringExtra("content") ?: ""
            val appName = intent.getStringExtra("appName") ?: ""

            val titleFontSize = intent.getStringExtra("titleFontSize")?.toFloatOrNull() ?: 28f
            val subtitleFontSize = intent.getStringExtra("subtitleFontSize")?.toFloatOrNull() ?: 20f
            val contentFontSize = intent.getStringExtra("contentFontSize")?.toFloatOrNull() ?: 16f

            val titleColor = parseColorExtra("titleColor", Color.WHITE)
            val subtitleColor = parseColorExtra("subtitleColor", Color.parseColor("#B0B0B0"))
            val contentColor = parseColorExtra("contentColor", Color.parseColor("#E0E0E0"))
            val backgroundColor = parseColorExtra("backgroundColor", Color.parseColor("#1A1A2E"))

            val showAppIcon = intent.getStringExtra("showAppIcon")?.toBooleanStrictOrNull() ?: true
            val showTimestamp = intent.getStringExtra("showTimestamp")?.toBooleanStrictOrNull() ?: true
            val cameraAvoidance = intent.getStringExtra("cameraAvoidanceEnabled")?.toBooleanStrictOrNull() ?: false
            val padding = intent.getStringExtra("padding")?.toFloatOrNull() ?: 24f
            val spacing = intent.getStringExtra("spacing")?.toFloatOrNull() ?: 12f
            val horizontalOffset = intent.getStringExtra("horizontalOffset")?.toFloatOrNull() ?: 0f
            displayDurationMs = intent.getStringExtra("displayDurationMs")?.toLongOrNull() ?: 10000L

            // 摄像头避开：背屏摄像头在左侧 ~296px cutout
            val cameraOffsetPx = if (cameraAvoidance) {
                try { display?.cutout?.safeInsetLeft?.toFloat() ?: 296f } catch (_: Exception) { 296f }
            } else 0f
            val contentOffset = horizontalOffset + cameraOffsetPx

            Log.d(TAG, "Parsed: title=$title, subtitle=$subtitle, content=${content.take(30)}, "
                + "w=$titleFontSize, h=$subtitleFontSize, c=$contentFontSize, "
                + "bg=#$backgroundColor, dur=$displayDurationMs")

            // ── 创建渲染 View ──
            renderView = NotificationRenderView(
                context = this,
                config = RenderConfig(
                    title = if (title.isNotEmpty()) title else appName,
                    subtitle = subtitle,
                    content = content,
                    titleFontSize = titleFontSize,
                    subtitleFontSize = subtitleFontSize,
                    contentFontSize = contentFontSize,
                    titleColor = titleColor,
                    subtitleColor = subtitleColor,
                    contentColor = contentColor,
                    backgroundColor = backgroundColor,
                    showAppIcon = showAppIcon,
                    showTimestamp = showTimestamp,
                    cameraAvoidance = cameraAvoidance,
                    padding = padding,
                    spacing = spacing,
                    contentOffset = contentOffset,
                )
            )
            renderView?.setBackgroundColor(backgroundColor)

            setContentView(renderView)
            Log.d(TAG, "setContentView done")

            // 不拦截触摸 — 让双击等手势全部穿透到系统
            // - 双击 → TouchInteractionService（系统背屏切换）
            // - 边缘返回滑动 → SubScreenGestureBack（系统背屏手势处理器）
            renderView?.isClickable = false
            renderView?.isFocusable = false

            // ── 注册光线传感器（官方算法: lux 阈值控制 AOD/息屏） ──
            registerLightSensor()

            Log.d(TAG, "onCreate complete")

        } catch (e: Exception) {
            Log.e(TAG, "onCreate failed", e)
            finish()
        }
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        Log.d(TAG, "onConfigChanged: w=${newConfig.screenWidthDp}dp h=${newConfig.screenHeightDp}dp d=${newConfig.densityDpi} display=${display?.displayId}")
        // 移屏后强制让 View 重新布局和绘制
        renderView?.requestLayout()
        renderView?.invalidate()
    }

    override fun onResume() {
        super.onResume()
        // 获取唤醒锁防止背屏进入 AOD/Doze
        try {
            val pm = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
            wakeLock = pm.newWakeLock(
                android.os.PowerManager.SCREEN_BRIGHT_WAKE_LOCK or android.os.PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "FBS:BackScreen"
            )
            wakeLock?.acquire(10 * 60 * 1000L) // 10 分钟
            Log.d(TAG, "WakeLock acquired")
        } catch (e: Exception) {
            Log.w(TAG, "WakeLock failed: ${e.message}")
        }
    }

    private fun enterAodMode() {
        if (isInAodMode) return; isInAodMode = true
        Log.d(TAG, "AOD (lux=$lastLux, dark=${System.currentTimeMillis()-darkSinceMs}ms)")
        try { window.attributes = window.attributes.apply { screenBrightness = 0.05f } }
        catch (e: Exception) { Log.w(TAG, "AOD enter failed: ${e.message}") }
    }
    private fun exitAodMode() {
        if (!isInAodMode) return; isInAodMode = false
        Log.d(TAG, "Exit AOD (lux=$lastLux)")
        try { window.attributes = window.attributes.apply { screenBrightness = -1.0f } }
        catch (e: Exception) { Log.w(TAG, "AOD exit failed: ${e.message}") }
    }
    private fun registerLightSensor() {
        try {
            sensorManager = getSystemService(android.content.Context.SENSOR_SERVICE) as android.hardware.SensorManager
            val ls = sensorManager?.getDefaultSensor(android.hardware.Sensor.TYPE_LIGHT)
            if (ls != null) {
                sensorManager?.registerListener(sensorListener, ls, android.hardware.SensorManager.SENSOR_DELAY_NORMAL)
                Log.d(TAG, "Light sensor registered")
            } else {
                Log.w(TAG, "No light sensor, 8s timer fallback")
                dismissHandler.postDelayed({ if (!isInAodMode) enterAodMode() }, 8000)
            }
        } catch (e: Exception) { Log.w(TAG, "Sensor failed: ${e.message}") }
    }

    /** 捕获系统返回手势 — 背屏右边缘向左滑 = KEYCODE_BACK */
    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        if (event.keyCode == android.view.KeyEvent.KEYCODE_BACK && event.action == android.view.KeyEvent.ACTION_UP) {
            Log.d(TAG, "Back gesture received via KEYCODE_BACK, finishing")
            finish()
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onBackPressed() {
        Log.d(TAG, "onBackPressed called (system back gesture)")
        finish()
    }

    override fun onDestroy() {
        dismissHandler.removeCallbacksAndMessages(null)
        try {
            sensorManager?.unregisterListener(sensorListener)
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {}
        Log.d(TAG, "onDestroy (lastLux=$lastLux)")
        super.onDestroy()
    }

    private fun parseColorExtra(key: String, default: Int): Int {
        val hex = intent.getStringExtra(key) ?: return default
        return try {
            val clean = hex.replace("#", "")
            if (clean.length == 6) Color.parseColor("#$clean")
            else if (clean.length == 8) Color.parseColor("#${clean.substring(2)}")
            else default
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse color $key=$hex: ${e.message}")
            default
        }
    }

    // ═══════════════════════════════════════════
    // 渲染配置
    // ═══════════════════════════════════════════

    data class RenderConfig(
        val title: String,
        val subtitle: String,
        val content: String,
        val titleFontSize: Float,
        val subtitleFontSize: Float,
        val contentFontSize: Float,
        val titleColor: Int,
        val subtitleColor: Int,
        val contentColor: Int,
        val backgroundColor: Int,
        val showAppIcon: Boolean,
        val showTimestamp: Boolean,
        val cameraAvoidance: Boolean = false,
        val padding: Float,
        val spacing: Float,
        val contentOffset: Float = 0f,
    )

    // ═══════════════════════════════════════════
    // 自定义渲染 View
    // ═══════════════════════════════════════════

    class NotificationRenderView(
        context: android.content.Context,
        private val config: RenderConfig,
    ) : View(context) {

        private val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = config.titleColor
            textSize = config.titleFontSize
            typeface = Typeface.DEFAULT_BOLD
        }
        private val subtitlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = config.subtitleColor
            textSize = config.subtitleFontSize
        }
        private val contentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = config.contentColor
            textSize = config.contentFontSize
        }
        private val timestampPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = (config.contentColor and 0x00FFFFFF) or 0x80000000.toInt()
            textSize = config.contentFontSize * 0.65f
        }
        private val bgPaint = Paint().apply {
            color = config.backgroundColor
            style = Paint.Style.FILL
        }
        private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = (config.titleColor and 0x00FFFFFF) or 0x33000000
            style = Paint.Style.FILL
        }
        private val iconBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = (config.titleColor and 0x00FFFFFF) or 0x40000000
            style = Paint.Style.STROKE
            strokeWidth = 1.5f
        }
        private val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)

            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0 || h <= 0) return
            val ox = config.contentOffset  // 摄像头避开偏移

            android.util.Log.d("BackScreenNotif", "onDraw: ${w}x${h}, title=${config.title.take(20)}, titleColor=#${Integer.toHexString(config.titleColor)}, bgColor=#${Integer.toHexString(config.backgroundColor)}")

            val p = config.padding
            val s = config.spacing

            // ── 背景 ──
            canvas.drawRect(0f, 0f, w, h, bgPaint)

            var y = p

            // ── 标题行 ──
            val iconSize = config.titleFontSize + 8f
            val iconRadius = iconSize * 0.22f

            if (config.showAppIcon) {
                val iconLeft = p + ox
                val iconTop = y
                val iconRect = RectF(iconLeft, iconTop, iconLeft + iconSize, iconTop + iconSize)
                canvas.drawRoundRect(iconRect, iconRadius, iconRadius, iconPaint)
                canvas.drawRoundRect(iconRect, iconRadius, iconRadius, iconBorderPaint)

                val titleX = iconLeft + iconSize + s * 0.7f
                val titleBaseline = y + iconSize / 2f + (config.titleFontSize / 2.5f)
                canvas.drawText(config.title, titleX, titleBaseline, titlePaint)
                y += iconSize + s
            } else {
                canvas.drawText(config.title, p + ox, y + config.titleFontSize, titlePaint)
                y += config.titleFontSize + s
            }

            // ── 副标题 ──
            if (config.subtitle.isNotEmpty()) {
                canvas.drawText(config.subtitle, p + ox, y + config.subtitleFontSize, subtitlePaint)
                y += config.subtitleFontSize + s
            }

            // ── 正文 ──
            val maxWidth = w - p * 2
            val contentText = fitText(config.content, contentPaint, maxWidth - ox, h - y - p)
            canvas.drawText(contentText, p + ox, y + config.contentFontSize, contentPaint)

            // ── 时间戳 ──
            if (config.showTimestamp) {
                val now = timeFormat.format(Date())
                val timeTextWidth = timestampPaint.measureText(now)
                canvas.drawText(now, w - p - timeTextWidth, h - p, timestampPaint)
            }
        }

        private fun fitText(text: String, paint: Paint, maxWidth: Float, maxHeight: Float): String {
            if (text.isEmpty()) return text
            if (paint.measureText(text) <= maxWidth) return text

            var truncated = text
            while (truncated.length > 1 && paint.measureText("$truncated…") > maxWidth) {
                truncated = truncated.substring(0, truncated.length - 1)
            }
            return "$truncated…"
        }
    }
}
