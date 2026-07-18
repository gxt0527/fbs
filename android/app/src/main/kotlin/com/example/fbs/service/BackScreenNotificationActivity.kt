package com.example.fbs.service

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.graphics.*
import android.os.*
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.Log
import android.view.View
import android.view.WindowManager
import com.example.fbs.hyperisland.FocusForwarder
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
        private const val COVER_THRESHOLD_MS = 300_000L
        private const val MIN_AOD_BRIGHTNESS = 0.02f
        private const val MAX_AOD_BRIGHTNESS = 0.15f
        @Volatile
        var instance: BackScreenNotificationActivity? = null
    }

    private var renderView: NotificationRenderView? = null
    private var wakeLock: android.os.PowerManager.WakeLock? = null
    private var isInAodMode = false
    private var dismissHandler = Handler(Looper.getMainLooper())
    private var displayDurationMs = 10000L
    private var notificationIdToCancel: Int = -1
    private var sensorManager: android.hardware.SensorManager? = null
    private var lastLux = -1f
    private var darkSinceMs = 0L
    private var isUserFar = false
    private var farSinceMs = 0L
    private var coverSinceMs = 0L
    private var isMinBrightness = false
    private val sensorListener = object : android.hardware.SensorEventListener {
        override fun onSensorChanged(event: android.hardware.SensorEvent) {
            when (event.sensor.type) {
                android.hardware.Sensor.TYPE_LIGHT -> onLightChanged(event.values[0])
                android.hardware.Sensor.TYPE_PROXIMITY -> onProximityChanged(event.values[0])
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
            val category = intent.getStringExtra("category") ?: "general"

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
            val horizontalOffset = intent.getStringExtra("horizontalOffset")?.toFloatOrNull() ?: 85f
            displayDurationMs = intent.getStringExtra("displayDurationMs")?.toLongOrNull() ?: 10000L
            val useOfficialBg = intent.getStringExtra("useOfficialBackground")?.toBooleanStrictOrNull() ?: false

            // 关联的通知 ID（精确清除用，不触发其他通知）
            notificationIdToCancel = intent.getIntExtra("notifId", -1)

            // 摄像头避开：使用样式页设置的偏移量（dp 单位，自动 ×density 转 px）
            val cameraOffsetPx = if (cameraAvoidance) {
                try { horizontalOffset * resources.displayMetrics.density } catch (_: Exception) { 280f }
            } else 0f
            val contentOffset = cameraOffsetPx

            Log.d(TAG, "Parsed: title=$title, subtitle=$subtitle, content=${content.take(30)}, "
                + "w=$titleFontSize, h=$subtitleFontSize, c=$contentFontSize, "
                + "bg=#$backgroundColor, dur=$displayDurationMs")
            
            // 调试日志：检测内容中的特殊字符
            val contentLen = content.length
            val hasControlChars = content.any { it.code in 0x00..0x1F && it !in "\n\t\r" }
            val hasHighControl = content.any { it.code in 0x7F..0x9F }
            val hasBidiOrZW = content.any { it.code in 0x200B..0x200F || it.code in 0x202A..0x202E || it.code == 0xFEFF }
            if (hasControlChars || hasHighControl || hasBidiOrZW) {
                Log.w(TAG, "CONTENT HAS SPECIAL CHARS: control=$hasControlChars highCtrl=$hasHighControl bidi=$hasBidiOrZW, len=$contentLen")
            } else {
                Log.d(TAG, "Content clean: len=$contentLen, no special chars detected")
            }

            // ── 检查 dismiss 指令（通知被清除时同步关闭背屏） ──
            if (intent.getStringExtra("dismiss")?.toBooleanStrictOrNull() == true) {
                Log.d(TAG, "Dismiss signal received, finishing")
                finish()
                return
            }

            // ── 创建渲染 View ──
            renderView = NotificationRenderView(
                context = this,
                config = RenderConfig(
                    title = if (title.isNotEmpty()) title else appName,
                    subtitle = subtitle,
                    content = content,
                    category = category,
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
                    useOfficialBackground = useOfficialBg,
                )
            )
            renderView?.setBackgroundColor(if (useOfficialBg) Color.TRANSPARENT else backgroundColor)

            setContentView(renderView)
            Log.d(TAG, "setContentView done")

            // 不拦截触摸 — 让双击等手势全部穿透到系统
            // - 双击 → TouchInteractionService（系统背屏切换）
            // - 边缘返回滑动 → SubScreenGestureBack（系统背屏手势处理器）
            renderView?.isClickable = false
            renderView?.isFocusable = false

            // ── 注册光线传感器（官方算法: lux 阈值控制 AOD/息屏） ──
            registerLightSensor()

            instance = this
            Log.d(TAG, "onCreate complete")

        } catch (e: Exception) {
            Log.e(TAG, "onCreate failed", e)
            finish()
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "onNewIntent")
        if (intent.getStringExtra("dismiss")?.toBooleanStrictOrNull() == true) {
            Log.d(TAG, "onNewIntent: dismiss signal, finishing")
            finish()
        }
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        Log.d(TAG, "onConfigChanged: w=${newConfig.screenWidthDp}dp h=${newConfig.screenHeightDp}dp d=${newConfig.densityDpi} display=${display?.displayId}")
        // 移屏后 density 变化，更新 Paint 字体大小
        renderView?.refreshDensity()
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
        Log.d(TAG, "Enter AOD (lux=$lastLux far=$isUserFar)")
        recalcAodBrightness()
    }
    private fun exitAodMode() {
        if (!isInAodMode) return; isInAodMode = false; isMinBrightness = false
        Log.d(TAG, "Exit AOD (lux=$lastLux)")
        try { window.attributes = window.attributes.apply { screenBrightness = -1.0f } }
        catch (e: Exception) { Log.w(TAG, "AOD exit failed: ${e.message}") }
    }

    private fun onLightChanged(lux: Float) {
        lastLux = lux
        if (lux < LUX_THRESHOLD) {
            if (darkSinceMs == 0L) darkSinceMs = System.currentTimeMillis()
            val dur = System.currentTimeMillis() - darkSinceMs
            if (dur >= AOD_DELAY_MS && !isInAodMode) enterAodMode()
            else if (isInAodMode) recalcAodBrightness()
        } else {
            if (isInAodMode) recalcAodBrightness()
            darkSinceMs = 0L
        }
    }
    private fun onProximityChanged(value: Float) {
        val maxRng = sensorManager?.getDefaultSensor(android.hardware.Sensor.TYPE_PROXIMITY)?.maximumRange ?: 5f
        val nowFar = value >= maxRng
        if (nowFar != isUserFar) {
            isUserFar = nowFar; farSinceMs = if (nowFar) System.currentTimeMillis() else 0L
            Log.d(TAG, "Proximity: ${if (nowFar) "FAR" else "NEAR"} v=$value")
            if (!nowFar) { coverSinceMs = System.currentTimeMillis(); isMinBrightness = false }
            if (isInAodMode) recalcAodBrightness()
        }
    }
    private fun recalcAodBrightness() {
        if (!isInAodMode) return
        val coveredMs = if (coverSinceMs > 0L) System.currentTimeMillis() - coverSinceMs else 0L
        val forceMin = !isUserFar && coveredMs >= COVER_THRESHOLD_MS
        if (forceMin) {
            if (!isMinBrightness) { isMinBrightness = true
                Log.d(TAG, "Min AOD (covered ${coveredMs/1000}s)") }
            setAodBrightness(MIN_AOD_BRIGHTNESS)
        } else if (!isUserFar) {
            val ratio = (lastLux / LUX_THRESHOLD).coerceIn(0f, 1f)
            setAodBrightness(MIN_AOD_BRIGHTNESS + ratio * (MAX_AOD_BRIGHTNESS - MIN_AOD_BRIGHTNESS))
        } else {
            isMinBrightness = false
            setAodBrightness(MIN_AOD_BRIGHTNESS)
        }
    }
    private fun setAodBrightness(b: Float) {
        try { window.attributes = window.attributes.apply { screenBrightness = b } }
        catch (e: Exception) { Log.w(TAG, "AOD brightness set failed: ${e.message}") }
    }
    private fun registerLightSensor() {
        try {
            sensorManager = getSystemService(android.content.Context.SENSOR_SERVICE) as android.hardware.SensorManager
            val ls = sensorManager?.getDefaultSensor(android.hardware.Sensor.TYPE_LIGHT)
            if (ls != null) sensorManager?.registerListener(sensorListener, ls, android.hardware.SensorManager.SENSOR_DELAY_NORMAL)
            else { Log.w(TAG, "No light sensor"); dismissHandler.postDelayed({ if (!isInAodMode) enterAodMode() }, 8000) }
            val ps = sensorManager?.getDefaultSensor(android.hardware.Sensor.TYPE_PROXIMITY)
            if (ps != null) sensorManager?.registerListener(sensorListener, ps, android.hardware.SensorManager.SENSOR_DELAY_NORMAL)
            Log.d(TAG, "Sensors: light=${ls!=null} prox=${ps!=null}")
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
        if (instance === this) instance = null
        dismissHandler.removeCallbacksAndMessages(null)
        try {
            sensorManager?.unregisterListener(sensorListener)
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {}
        // 背屏销毁时只取消关联的那条通知（不触及其他通知）
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(SuperIslandHelper.NOTIFICATION_ID)
            if (notificationIdToCancel >= 0) {
                nm.cancel(notificationIdToCancel)
                com.example.fbs.hyperisland.FocusForwarder.removeActiveId(notificationIdToCancel)
                Log.d(TAG, "Cancelled notification id=$notificationIdToCancel on back screen dismiss")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to cancel notification on dismiss", e)
        }
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
        val category: String = "general",
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
        val useOfficialBackground: Boolean = false,
    )

    // ═══════════════════════════════════════════
    // 自定义渲染 View
    // ═══════════════════════════════════════════

    class NotificationRenderView(
        context: android.content.Context,
        private val config: RenderConfig,
    ) : View(context) {

        private var curDensity = context.resources.displayMetrics.density

        // CJK 字体（从系统路径加载 NotoSansCJK，背屏可能不继承主屏字体配置）
        private val cjkTypeface: Typeface = try {
            Typeface.createFromFile("/system/fonts/NotoSansCJK-Regular.ttc")
        } catch (_: Exception) {
            Typeface.create("sans-serif", Typeface.NORMAL)
        }
        private val cjkTypefaceBold: Typeface = try {
            Typeface.createFromFile("/system/fonts/NotoSansCJK-Regular.ttc")
        } catch (_: Exception) {
            Typeface.create("sans-serif", Typeface.BOLD)
        }

        /** 每次绘制前强制刷新 density，确保移屏后与预览一致 */
        fun refreshDensity() {
            val d = resources.displayMetrics.density
            curDensity = d
            titlePaint.textSize = config.titleFontSize * d
            subtitlePaint.textSize = config.subtitleFontSize * d
            contentPaint.textSize = config.contentFontSize * d
            timestampPaint.textSize = config.contentFontSize * 0.65f * d
        }

        private val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = config.titleColor
            textSize = config.titleFontSize * curDensity
            typeface = cjkTypefaceBold
        }
        private val subtitlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = config.subtitleColor
            textSize = config.subtitleFontSize * curDensity
            typeface = cjkTypeface
        }
        private val contentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = config.contentColor
            textSize = config.contentFontSize * curDensity
            typeface = cjkTypeface
        }
        private val timestampPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = (config.contentColor and 0x00FFFFFF) or 0x80000000.toInt()
            textSize = config.contentFontSize * 0.65f * curDensity
            typeface = cjkTypeface
        }
        private val bgPaint = Paint().apply {
            color = config.backgroundColor
            style = Paint.Style.FILL
        }

        // ── 场景图标绘制 ──
        // 从 Android VectorDrawable (res/drawable/ic_scene_*.xml) 加载场景图标
        private val sceneColor: Int get() = when (config.category) {
            "foodDelivery", "food" -> Color.parseColor("#FF375F")
            "express" -> Color.parseColor("#FF9500")
            "verification" -> Color.parseColor("#FF9500")
            "payment" -> Color.parseColor("#34C759")
            "order" -> Color.parseColor("#5AC8FA")
            "meeting" -> Color.parseColor("#0088FF")
            "travel" -> Color.parseColor("#AF52DE")
            "bill" -> Color.parseColor("#D4A24C")
            else -> Color.parseColor("#8E8E93")
        }

        private fun drawSceneIcon(canvas: Canvas, left: Float, top: Float, size: Float) {
            val resId = sceneDrawableRes(config.category) ?: return
            val drawable = context.resources.getDrawable(resId, context.theme) ?: return
            drawable.setBounds(left.toInt(), top.toInt(), (left + size).toInt(), (top + size).toInt())
            drawable.setTint(sceneColor)
            drawable.draw(canvas)
        }

        private fun sceneDrawableRes(category: String): Int? = when (category) {
            "foodDelivery", "food" -> com.example.fbs.R.drawable.ic_scene_food
            "express" -> com.example.fbs.R.drawable.ic_scene_express
            "payment" -> com.example.fbs.R.drawable.ic_scene_pay
            "bill" -> com.example.fbs.R.drawable.ic_scene_bill
            "verification" -> com.example.fbs.R.drawable.ic_scene_verify
            "meeting" -> com.example.fbs.R.drawable.ic_scene_meeting
            "travel" -> com.example.fbs.R.drawable.ic_scene_travel
            "order" -> com.example.fbs.R.drawable.ic_scene_order
            "system", "general", "scan" -> com.example.fbs.R.drawable.ic_scene_system
            else -> null
        }

        private val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)

            // 每次绘制时读取最新 density（移屏到 display 1 后可能变化）
            refreshDensity()
            val d = curDensity

            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0 || h <= 0) return
            val ox = config.contentOffset  // 摄像头避开偏移

            val p = config.padding * d
            val s = config.spacing * d

            // ── 背景 ──
            if (config.useOfficialBackground) {
                // 官方背屏渐变: 底部橙色 → 顶部黑色（与 Flutter 预览一致）
                val gradientShader = android.graphics.LinearGradient(
                    0f, h,                  // x0=0, y0=bottom
                    0f, 0f,                  // x1=0, y1=top
                    intArrayOf(
                        Color.parseColor("#C87018"),
                        Color.parseColor("#8A300F"),
                        Color.parseColor("#7B2007"),
                        Color.parseColor("#571504"),
                        Color.parseColor("#210401"),
                        Color.parseColor("#000000"),
                    ),
                    floatArrayOf(0.0f, 0.30f, 0.42f, 0.55f, 0.75f, 1.0f),
                    android.graphics.Shader.TileMode.CLAMP
                )
                val gradPaint = Paint().apply {
                    shader = gradientShader
                    style = Paint.Style.FILL
                }
                canvas.drawRect(0f, 0f, w, h, gradPaint)
            } else {
                canvas.drawRect(0f, 0f, w, h, bgPaint)
            }

            var y = p

            // ── 标题行（智能场景图标模式） — 图标与标题垂直居中 ──
            if (config.showAppIcon && config.category != "general") {
                // 图标容器 = titleFontSize + 8dp（与 preview Container 一致）
                val iconSize = (config.titleFontSize + 8f) * d
                val iconLeft = p + ox
                // 内边距 = 16%（与 preview padding 一致）
                val iconPad = iconSize * 0.16f

                // 标题 baseline 先按原 0.85f 计算，再求文字视觉中心
                val titleBaseline = y + config.titleFontSize * d * 0.85f
                val fm = titlePaint.fontMetrics
                val textCenterY = titleBaseline + (fm.ascent + fm.descent) / 2f
                // 图标容器中心与文字视觉中心对齐
                val iconTop = textCenterY - iconSize / 2f
                try { drawSceneIcon(canvas, iconLeft + iconPad, iconTop + iconPad, iconSize - iconPad * 2) }
                catch (e: Exception) { Log.w(TAG, "SceneIcon draw failed: ${e.message}") }

                // 标题与图标间距 = spacing * 0.7（与 preview SizedBox 一致）
                val titleX = iconLeft + iconSize + s * 0.7f
                try { canvas.drawText(config.title, titleX, titleBaseline, titlePaint) }
                catch (e: Exception) { Log.w(TAG, "Title draw failed: ${e.message}") }
                y += iconSize + s
            } else {
                try { canvas.drawText(config.title, p + ox, y + config.titleFontSize * d, titlePaint) }
                catch (e: Exception) { Log.w(TAG, "Title draw failed: ${e.message}") }
                y += config.titleFontSize * d + s
            }

            // ── 副标题 ──
            if (config.subtitle.isNotEmpty()) {
                try { canvas.drawText(config.subtitle, p + ox, y + config.subtitleFontSize * d, subtitlePaint) }
                catch (e: Exception) { Log.w(TAG, "Subtitle draw failed: ${e.message}") }
                y += config.subtitleFontSize * d + s
            }

            // ── 正文（自动换行） ──
            val contentWidth = w - p * 2 - ox
            if (config.content.isNotEmpty() && contentWidth > 0) {
                try {
                    val tp = TextPaint(contentPaint)
                    val layout = if (android.os.Build.VERSION.SDK_INT >= 23) {
                        StaticLayout.Builder.obtain(config.content, 0, config.content.length, tp, contentWidth.toInt())
                            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                            .setLineSpacing(0f, 1.2f)
                            .setIncludePad(false)
                            .setMaxLines(((h - y - p) / (config.contentFontSize * d * 1.3f)).toInt().coerceAtLeast(1))
                            .build()
                    } else {
                        @Suppress("DEPRECATION")
                        StaticLayout(config.content, tp, contentWidth.toInt(), Layout.Alignment.ALIGN_NORMAL, 1.2f, 0f, false)
                    }
                    canvas.save()
                    canvas.translate(p + ox, y)
                    layout.draw(canvas)
                    canvas.restore()
                } catch (e: Exception) {
                    Log.w(TAG, "Content layout/draw failed: ${e.message}, contentLen=${config.content.length}")
                    // 降级：只绘制首行文本（保证背屏有内容可看）
                    try {
                        val safeLen = config.content.length.coerceAtMost(200)
                        val fallbackText = if (config.content.length > safeLen)
                            config.content.substring(0, safeLen) else config.content
                        canvas.drawText(fallbackText, p + ox, y + config.contentFontSize * d, contentPaint)
                    } catch (_: Exception) {
                        Log.w(TAG, "Content fallback draw also failed")
                    }
                }
            }

            // ── 时间戳 ──
            if (config.showTimestamp) {
                try {
                    val now = timeFormat.format(Date())
                    val timeTextWidth = timestampPaint.measureText(now)
                    canvas.drawText(now, w - p - timeTextWidth, h - p, timestampPaint)
                } catch (e: Exception) { Log.w(TAG, "Timestamp draw failed: ${e.message}") }
            }
        }
    }
}
