package com.example.fbs.service

import android.animation.ValueAnimator
import android.animation.AnimatorListenerAdapter
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.*
import android.os.*
import android.util.Log
import android.view.*
import android.view.animation.DecelerateInterpolator
import java.text.SimpleDateFormat
import java.util.*
import org.json.JSONArray

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
        /** 移屏延迟 — 等待 Shizuku 将 Activity 从 display 0 移到 display 1 */
        private const val DISPLAY_MOVE_DELAY_MS = 500L

        /** 构建关闭背屏的 Intent 字符串，供 Shizuku 的 am start 使用 */
        fun buildDismissIntent(context: android.content.Context): String {
            return "am start -n ${context.packageName}/.service.BackScreenNotificationActivity" +
                " -f 0x20000000 --es dismiss \"true\" --user 0"
        }
    }

    private var renderView: NotificationRenderView? = null
    private var dismissHandler = Handler(Looper.getMainLooper())
    private var isSticky = false
    private var isMirror = false
    private var currentConfig: RenderConfig? = null
    private var iconLoadThread: Thread? = null
    private var isActivated = false
    private var needsWake = true
    private var isDozing = false
    private var wasInAod = false  // 记录启动时是否处于 AOD，关闭时据此决定是否恢复 subscreencenter

    // multi-notification navigation
    private var notificationsList = mutableListOf<RenderConfig>()
    private var currentIndex = 0
    private var lastNotifCount = 0

    private val aodTransitionRunnable = Runnable { enterAodMode() }

    // mirror mode broadcast receiver
    private val mirrorReceiver = MirrorReceiver()

    // 镜像模式: 定期唤醒 display 1 防止 DOZE 休眠 (15s 间隔)
    private val dozePreventionHandler = Handler(Looper.getMainLooper())
    private val dozePreventionRunnable = object : Runnable {
        override fun run() {
            if (!isMirror) return
            Thread {
                try {
                    BackScreenController.execShell("input -d 1 keyevent KEYCODE_WAKEUP")
                } catch (_: Exception) {}
            }.apply { isDaemon = true; start() }
            dozePreventionHandler.postDelayed(this, 15000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            val displayId = display?.displayId ?: 0
            Log.d(TAG, "onCreate display=$displayId")

            // 检查 dismiss 指令（防止 auto-dismiss 后重建）
            if (intent.getStringExtra("dismiss")?.toBooleanStrictOrNull() == true) {
                Log.d(TAG, "Dismiss on create, finishing immediately")
                finishAndRestore()
                return
            }

            setupWindowFlags()
            needsWake = intent.getStringExtra("needsWake")?.toBooleanStrictOrNull() ?: true
            isDozing = intent.getStringExtra("isDozing")?.toBooleanStrictOrNull() ?: false
            wasInAod = isDozing  // 记录启动时的 AOD 状态，关闭时据此决定是否恢复 subscreencenter
            isMirror = intent.getStringExtra("mirrorMode")?.toBooleanStrictOrNull() ?: false
            Log.d(TAG, "needsWake=$needsWake isDozing=$isDozing wasInAod=$wasInAod isMirror=$isMirror")

            // Register broadcast receiver for mirror updates
            val filter = IntentFilter().apply {
                addAction(BackScreenController.ACTION_MIRROR_REFRESH)
                addAction(BackScreenController.ACTION_MIRROR_DISMISS)
            }
            registerReceiver(mirrorReceiver, filter, Context.RECEIVER_NOT_EXPORTED)

            // Parse notification list from JSON
            val jsonStr = intent.getStringExtra("notificationsJson") ?: ""
            notificationsList = parseNotificationsJson(jsonStr)
            if (notificationsList.isEmpty()) {
                // fallback: parse single notification from intent extras
                currentConfig = parseIntent(intent)
                notificationsList.add(currentConfig!!)
            }
            currentIndex = intent.getStringExtra("notificationKey")?.let { key ->
                notificationsList.indexOfFirst { it.notificationKey == key }
                    .coerceAtLeast(0)
            } ?: 0
            currentConfig = notificationsList[currentIndex]
            lastNotifCount = notificationsList.size
            Log.d(TAG, "notificationsList: ${notificationsList.size} items, currentIndex=$currentIndex")

            renderView = NotificationRenderView(this, notificationsList, currentIndex)
            setContentView(renderView)
            renderView?.isClickable = false
            renderView?.isFocusable = false
            renderView?.onNavigateCallback = { newIndex -> onNavigateTo(newIndex) }

            // 在 display 0 上 view 完全不可见，移到 display 1 后才显示
            if (displayId != 1) {
                renderView?.visibility = View.GONE
            }

            // Load app icon for current notification
            loadAppIconAsync(currentConfig!!)

            // 不设自动消失 — 背屏通知随系统通知生命周期
            // 系统清除通知时 onNotificationRemoved → dismissBackScreen() → 关闭本 Activity

            // 根据当前 display 决定是否激活渲染
            if (displayId == 1) {
                activateOnDisplay1()
            } else {
                // display 0 — 透明等待，不渲染内容，不接收触摸
                Log.d(TAG, "Launched on display 0, waiting to move to display 1")
                holdOnDisplay0()
            }

            // 5 秒后降低亮度到 AOD 水平，保持通知内容但模拟 AOD 状态
            scheduleAodTransition()

            Log.d(TAG, "onCreate done, sticky=$isSticky key=${currentConfig?.notificationKey}")
        } catch (e: Exception) {
            Log.e(TAG, "onCreate failed", e)
            finish()
        }
    }

    /**
     * display 0 阶段: 禁用触摸输入，等待 500ms 后检查是否已移到 display 1
     * 此期间 Activity 透明 + 无触摸 = 不会影响正面屏幕
     */
    private fun holdOnDisplay0() {
        // 禁止所有触摸事件传递到此 Activity
        window.setFlags(
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        )
        // 延迟后检查是否已移到 display 1
        dismissHandler.postDelayed({
            checkAndActivate()
        }, DISPLAY_MOVE_DELAY_MS)
    }

    /** 检测 display ID，若已在 display 1 则激活渲染和触摸 */
    private fun checkAndActivate() {
        val displayId = display?.displayId ?: 0
        if (displayId == 1) {
            activateOnDisplay1()
        } else {
            // 仍在 display 0，再等一轮（可能移屏较慢）
            Log.w(TAG, "Still on display 0 after ${DISPLAY_MOVE_DELAY_MS}ms, retrying")
            dismissHandler.postDelayed({ checkAndActivate() }, DISPLAY_MOVE_DELAY_MS)
        }
    }

    /** 激活: 设置不透明背景 + 启用触摸输入 + 显示渲染内容 */
    private fun activateOnDisplay1() {
        if (isActivated) return
        isActivated = true
        BackScreenController.backScreenActivityAlive = true
        Log.d(TAG, "Activated on display 1")

        // 镜像模式: 定期唤醒防止 display 1 DOZE
        if (isMirror) {
            dozePreventionHandler.postDelayed(dozePreventionRunnable, 15000)
            Log.d(TAG, "Doze prevention started (15s interval)")
        }

        // 恢复窗口为不透明
        window.setBackgroundDrawableResource(android.R.color.black)
        // 启用触摸
        window.clearFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
        // 显示渲染内容（之前 GONE）
        renderView?.visibility = View.VISIBLE
        // 刷新渲染
        renderView?.invalidate()
    }

    /**
     * 支持通知更新: 当 Activity 已在前台时，通过 onNewIntent 更新内容
     * BackScreenController 先 am start 再 force-stop subscreencenter，
     * Activity 如果还在 display 1 就会收到 onNewIntent
     */
    @Suppress("DEPRECATION")
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val displayId = display?.displayId ?: 0
        Log.d(TAG, "onNewIntent display=$displayId")

        // 更新 mirrorMode 标志
        isMirror = intent.getStringExtra("mirrorMode")?.toBooleanStrictOrNull() ?: isMirror

        // 检查 dismiss 指令
        if (intent.getStringExtra("dismiss")?.toBooleanStrictOrNull() == true) {
            Log.d(TAG, "Dismiss signal received, closing back screen")
            finishAndRestore()
            return
        }

        try {
            // Update screen state
            needsWake = intent.getStringExtra("needsWake")?.toBooleanStrictOrNull() ?: needsWake
            isDozing = intent.getStringExtra("isDozing")?.toBooleanStrictOrNull() ?: isDozing
            // wasInAod 不更新 — 只在 onCreate 设置一次，保持初始 AOD 状态
            // 后续 update/dismiss 都应使用最初的状态来决定是否需要 KEYCODE_SLEEP

            // Parse updated notifications list
            val jsonStr = intent.getStringExtra("notificationsJson") ?: ""
            val newList = parseNotificationsJson(jsonStr)
            if (isMirror && newList.isEmpty()) {
                Log.d(TAG, "onNewIntent mirror: empty list, finishing")
                finishAndRestore()
                return
            }
            if (newList.isNotEmpty()) {
                notificationsList = newList
            }
            lastNotifCount = notificationsList.size

            // If still on display 0, skip render update
            if (displayId != 1) {
                Log.d(TAG, "onNewIntent on display $displayId, skipping render update")
                return
            }

            // On display 1: update to show the latest notification (index 0)
            currentIndex = 0
            currentConfig = notificationsList[currentIndex]
            renderView?.updateList(notificationsList, currentIndex)
            loadAppIconAsync(currentConfig!!)

            // 通知更新后重新计时：再亮屏 5 秒，然后进入 AOD 亮度
            scheduleAodTransition()
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

    /**
     * MIUI 在背屏 (display 1) 上的输入系统会拦截 BACK 键事件，
     * 导致 onBackPressed 不被调用（日志: "Back key is intercepted by the app"）。
     * 在 dispatchKeyEvent 层面拦截，绕过 MIUI 的拦截链。
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_DOWN) {
            if (isMirror) {
                // 镜像模式: 返回手势清除当前通知 (前端)
                cancelCurrentMirrorNotification()
                return true
            }
            Log.d(TAG, "Back key intercepted by dispatchKeyEvent, restoring subscreen")
            finishAndRestore()
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            // 每次获得焦点时重新隐藏系统栏（防止系统弹回）
            setupImmersiveMode()
        }
    }

    override fun onDestroy() {
        try { unregisterReceiver(mirrorReceiver) } catch (_: Exception) {}
        BackScreenController.backScreenActivityAlive = false
        dozePreventionHandler.removeCallbacks(dozePreventionRunnable)
        dismissHandler.removeCallbacksAndMessages(null)
        iconLoadThread?.interrupt()
        Log.d(TAG, "onDestroy, key=${currentConfig?.notificationKey}")
        super.onDestroy()
    }

    // ═══════════════════════════════════════════
    // 背屏关闭 & 恢复
    // ═══════════════════════════════════════════

    /** 关闭本 Activity。系统会自动恢复 SECONDARY_HOME (subscreencenter)。 */
    private fun finishAndRestore() {
        BackScreenController.backScreenActivityAlive = false
        dozePreventionHandler.removeCallbacks(dozePreventionRunnable)
        dismissHandler.removeCallbacksAndMessages(null)
        finish()
        if (wasInAod) {
            // AOD 模式: finish 后等 subscreencenter 恢复前景，再 sleep 回到 AOD
            Thread {
                try {
                    Thread.sleep(800)
                    BackScreenController.instance?.putBackScreenToSleep()
                } catch (e: Exception) {
                    Log.e(TAG, "AOD sleep failed", e)
                }
            }.apply { isDaemon = true }.start()
            Log.d(TAG, "AOD mode: Activity finished, subscreencenter will auto-resume + KEYCODE_SLEEP")
            return
        }
        Log.d(TAG, "Activity finished, system will auto-restore SECONDARY_HOME on display 1")
    }

    // ═══════════════════════════════════════════
    //  镜像模式方法
    // ═══════════════════════════════════════════

    /** 接收镜像刷新/消除广播 */
    private inner class MirrorReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return
            when (intent.action) {
                BackScreenController.ACTION_MIRROR_REFRESH -> {
                    val json = intent.getStringExtra("notificationsJson") ?: ""
                    val displayId = display?.displayId ?: 0
                    Log.d(TAG, "Mirror refresh: jsonLen=${json.length} display=$displayId")
                    applyMirrorUpdate(json, intent.extras)
                    if (displayId == 1 && isActivated) {
                        wakeToShow()
                    }
                }
                BackScreenController.ACTION_MIRROR_DISMISS -> {
                    Log.d(TAG, "Mirror dismiss received")
                    finishAndRestore()
                }
            }
        }
    }

    /** 应用镜像广播中的通知列表更新 */
    private fun applyMirrorUpdate(json: String, extras: Bundle?) {
        val newList = parseNotificationsJson(json)
        if (newList.isEmpty()) {
            // 所有通知已消除 → 关闭背屏
            Log.d(TAG, "Mirror update: empty list, finishing")
            finishAndRestore()
            return
        }
        // 应用广播中的样式参数
        val styled = applyStyleFromBundle(extras, newList)
        notificationsList = styled
        lastNotifCount = styled.size
        currentIndex = 0
        currentConfig = notificationsList[currentIndex]
        renderView?.updateList(notificationsList, currentIndex)
        loadAppIconAsync(currentConfig!!)
        Log.d(TAG, "Mirror update: ${notificationsList.size} items, currentIndex=0")
    }

    /** 镜像模式: 返回手势清除当前在前端显示的这条通知 */
    private fun cancelCurrentMirrorNotification() {
        val key = currentConfig?.notificationKey
        if (key.isNullOrEmpty()) {
            Log.w(TAG, "Mirror back-gesture: no notificationKey, falling back to finish")
            finishAndRestore()
            return
        }
        Log.d(TAG, "Mirror back-gesture: cancelling notification key=$key")
        FBSNotificationListenerService.instance?.cancelNotification(key)
        // cancelNotification 触发 onNotificationRemoved → remove from mirroredItems → refreshOrDismissMirror
        // 如果只有一条，mirroredItems 清空 → dismiss broadcast → finishAndRestore
        // 如果多条，mirroredItems 仍有数据 → refresh broadcast → applyMirrorUpdate 重新渲染
    }

    /** 从广播 extras 应用样式 (mirror refresh 使用) */
    private fun applyStyleFromBundle(bundle: Bundle?, configs: MutableList<RenderConfig>): MutableList<RenderConfig> {
        if (bundle == null) return configs
        return configs.map { c ->
            c.copy(
                titleFontSize = bundle.getString("titleFontSize")?.toFloatOrNull() ?: c.titleFontSize,
                subtitleFontSize = bundle.getString("subtitleFontSize")?.toFloatOrNull() ?: c.subtitleFontSize,
                contentFontSize = bundle.getString("contentFontSize")?.toFloatOrNull() ?: c.contentFontSize,
                titleColor = parseBundleColor(bundle, "titleColor", c.titleColor),
                subtitleColor = parseBundleColor(bundle, "subtitleColor", c.subtitleColor),
                contentColor = parseBundleColor(bundle, "contentColor", c.contentColor),
                backgroundColor = parseBundleColor(bundle, "backgroundColor", c.backgroundColor),
                showAppIcon = bundle.getString("showAppIcon")?.toBooleanStrictOrNull() ?: c.showAppIcon,
                showTimestamp = bundle.getString("showTimestamp")?.toBooleanStrictOrNull() ?: c.showTimestamp,
                cameraAvoidanceEnabled = bundle.getString("cameraAvoidanceEnabled")?.toBooleanStrictOrNull() ?: c.cameraAvoidanceEnabled,
                horizontalOffset = if (bundle.getString("cameraAvoidanceEnabled")?.toBooleanStrictOrNull() == true) {
                    bundle.getString("horizontalOffset")?.toFloatOrNull() ?: 85f
                } else 0f,
                padding = bundle.getString("padding")?.toFloatOrNull() ?: c.padding,
                spacing = bundle.getString("spacing")?.toFloatOrNull() ?: c.spacing,
            )
        }.toMutableList()
    }

    private fun parseBundleColor(bundle: Bundle, key: String, default: Int): Int {
        val hex = bundle.getString(key) ?: return default
        return try {
            val clean = hex.replace("#", "")
            if (clean.length == 6 || clean.length == 8) Color.parseColor("#$clean") else default
        } catch (_: Exception) { default }
    }

    /** 从 AOD 暗屏唤醒显示: 恢复亮度和触摸 */
    private fun wakeToShow() {
        try {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            val lp = window.attributes
            lp.screenBrightness = -1.0f // 跟随系统亮度
            window.attributes = lp
            // 重新计时: 5s 后再次暗屏
            scheduleAodTransition()
            Log.d(TAG, "Wake to show: brightness restored, AOD transition rescheduled")
        } catch (e: Exception) {
            Log.e(TAG, "wakeToShow failed", e)
        }
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
            var flags = WindowManager.LayoutParams.FLAG_FULLSCREEN or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
            // 来通知后先保持亮屏 5 秒，方便用户看清内容
            // 之后 enterAodMode() 会清除 KEEP_SCREEN_ON 并降低亮度到 AOD 水平
            flags = flags or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            window.addFlags(flags)
            val lp = window.attributes
            lp.screenBrightness = -1.0f // 跟随系统亮度
            window.attributes = lp

            // 沉浸模式 — 彻底隐藏状态栏和导航栏
            setupImmersiveMode()
        } catch (e: Exception) {
            Log.w(TAG, "Window flags error: ${e.message}")
        }
    }

    private fun scheduleAodTransition() {
        dismissHandler.removeCallbacks(aodTransitionRunnable)
        dismissHandler.postDelayed(aodTransitionRunnable, 5000)
        Log.d(TAG, "Scheduled AOD transition in 5000ms")
    }

    private fun enterAodMode() {
        try {
            // 降低亮度到 AOD 水平，保持通知内容可见
            // 关键: 不清除 FLAG_KEEP_SCREEN_ON，防止 display 1 睡眠后 subscreencenter 接管
            val lp = window.attributes
            lp.screenBrightness = 0.05f
            window.attributes = lp
            Log.d(TAG, "Entered AOD brightness mode (KEEP_SCREEN_ON retained)")
        } catch (e: Exception) {
            Log.e(TAG, "enterAodMode failed", e)
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
            intent.getStringExtra("horizontalOffset")?.toFloatOrNull() ?: 85f
        } else {
            0f
        }
        val padding = intent.getStringExtra("padding")?.toFloatOrNull() ?: 24f
        val spacing = intent.getStringExtra("spacing")?.toFloatOrNull() ?: 12f

        Log.d(TAG, "Parsed: key=$notificationKey sticky=$isSticky focus=$isFocus "
            + "count=$notificationCount title=[$title] content=[${content.take(30)}]")
        // [临时调试] 验证摄像头避让参数是否到达 Activity
        Log.d(TAG, "Camera: enabled=$cameraAvoidanceEnabled ho=$horizontalOffset "
            + "raw='${intent.getStringExtra("cameraAvoidanceEnabled")}' "
            + "rawHo='${intent.getStringExtra("horizontalOffset")}'")

        // 加载应用桌面图标 — 异步加载，避免阻塞主线程
        // 先用 null 占位，异步加载完成后 invalidate
        val appIcon: Bitmap? = null

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
            appIcon = appIcon,
        )
    }

    private fun loadAppIconAsync(config: RenderConfig) {
        iconLoadThread?.interrupt()
        if (config.packageName.isEmpty()) return

        iconLoadThread = Thread {
            try {
                val density = resources.displayMetrics.density
                val iconSize = (config.titleFontSize + 8f) * density
                val pxSize = iconSize.toInt()
                val iconDrawable = try {
                    val launchIntent = packageManager.getLaunchIntentForPackage(config.packageName)
                    if (launchIntent != null) packageManager.getActivityIcon(launchIntent)
                    else packageManager.getApplicationIcon(config.packageName)
                } catch (_: Exception) {
                    try { packageManager.getApplicationIcon(config.packageName) } catch (_: Exception) { null }
                }
                if (iconDrawable == null || Thread.currentThread().isInterrupted) return@Thread
                val bmp = Bitmap.createBitmap(pxSize, pxSize, Bitmap.Config.ARGB_8888)
                val canvas = android.graphics.Canvas(bmp)
                iconDrawable.setBounds(0, 0, pxSize, pxSize)
                iconDrawable.draw(canvas)
                if (Thread.currentThread().isInterrupted) return@Thread
                runOnUiThread {
                    // Update the config in the list with loaded icon
                    if (currentIndex < notificationsList.size) {
                        val updated = notificationsList[currentIndex].copy(appIcon = bmp)
                        notificationsList[currentIndex] = updated
                        currentConfig = updated
                        renderView?.updateConfig(updated)
                        renderView?.invalidate()
                    }
                }
            } catch (_: Exception) {}
        }.apply { isDaemon = true; start() }
    }

    /**
     * Parse notifications JSON array into a list of RenderConfig.
     * Uses shared style from the first item or from current intent extras.
     */
    private fun parseNotificationsJson(json: String): MutableList<RenderConfig> {
        if (json.isBlank()) return mutableListOf()
        return try {
            val arr = JSONArray(json)
            val result = mutableListOf<RenderConfig>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val config = RenderConfig(
                    title = obj.optString("title", ""),
                    subtitle = obj.optString("subText", ""),
                    content = obj.optString("content", ""),
                    appName = obj.optString("appName", ""),
                    packageName = obj.optString("packageName", ""),
                    category = obj.optString("category", ""),
                    notificationKey = obj.optString("key", ""),
                    isSticky = obj.optBoolean("isSticky", false),
                    isFocus = obj.optBoolean("isFocus", false),
                    notificationCount = arr.length(),
                    titleFontSize = 28f,
                    subtitleFontSize = 20f,
                    contentFontSize = 16f,
                    countFontSize = 14f,
                    titleColor = Color.WHITE,
                    subtitleColor = Color.parseColor("#B0B0B0"),
                    contentColor = Color.parseColor("#E0E0E0"),
                    countColor = Color.parseColor("#888888"),
                    backgroundColor = Color.parseColor("#1A1A2E"),
                    showAppIcon = true,
                    showTimestamp = true,
                    showFoldCount = arr.length() > 1,
                    cameraAvoidanceEnabled = false,
                    horizontalOffset = 0f,
                    padding = 24f,
                    spacing = 12f,
                    appIcon = null,
                )
                result.add(config)
            }
            // Apply style from current intent to all items
            if (result.isNotEmpty()) {
                val styled = applyStyleFromIntent(result)
                styled
            } else {
                result
            }
        } catch (e: Exception) {
            Log.e(TAG, "parseNotificationsJson failed: ${e.message}")
            mutableListOf()
        }
    }

    /** Apply style extras (colors, sizes, etc.) from current intent to all notification configs */
    private fun applyStyleFromIntent(configs: MutableList<RenderConfig>): MutableList<RenderConfig> {
        return configs.map { c ->
            c.copy(
                titleFontSize = intent.getStringExtra("titleFontSize")?.toFloatOrNull() ?: c.titleFontSize,
                subtitleFontSize = intent.getStringExtra("subtitleFontSize")?.toFloatOrNull() ?: c.subtitleFontSize,
                contentFontSize = intent.getStringExtra("contentFontSize")?.toFloatOrNull() ?: c.contentFontSize,
                titleColor = parseColorExtra("titleColor", c.titleColor),
                subtitleColor = parseColorExtra("subtitleColor", c.subtitleColor),
                contentColor = parseColorExtra("contentColor", c.contentColor),
                backgroundColor = parseColorExtra("backgroundColor", c.backgroundColor),
                showAppIcon = intent.getStringExtra("showAppIcon")?.toBooleanStrictOrNull() ?: c.showAppIcon,
                showTimestamp = intent.getStringExtra("showTimestamp")?.toBooleanStrictOrNull() ?: c.showTimestamp,
                cameraAvoidanceEnabled = intent.getStringExtra("cameraAvoidanceEnabled")?.toBooleanStrictOrNull() ?: c.cameraAvoidanceEnabled,
                horizontalOffset = if (intent.getStringExtra("cameraAvoidanceEnabled")?.toBooleanStrictOrNull() == true) {
                    intent.getStringExtra("horizontalOffset")?.toFloatOrNull() ?: 85f
                } else 0f,
                padding = intent.getStringExtra("padding")?.toFloatOrNull() ?: c.padding,
                spacing = intent.getStringExtra("spacing")?.toFloatOrNull() ?: c.spacing,
            )
        }.toMutableList()
    }

    /** Called by RenderView when user swipes to navigate between notifications */
    private fun onNavigateTo(newIndex: Int) {
        if (newIndex < 0 || newIndex >= notificationsList.size) return
        currentIndex = newIndex
        currentConfig = notificationsList[currentIndex]
        Log.d(TAG, "Navigate to index=$currentIndex key=${currentConfig?.notificationKey}")
        loadAppIconAsync(currentConfig!!)
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
        val appIcon: Bitmap? = null,
    )

    // ═══════════════════════════════════════════
    // Custom RenderView — multi-notification navigation with swipe + arrows
    // ═══════════════════════════════════════════

    class NotificationRenderView(
        context: android.content.Context,
        private val notifications: MutableList<RenderConfig>,
        private var currentIndex: Int,
    ) : View(context) {

        var onNavigateCallback: ((Int) -> Unit)? = null

        private val density: Float
        private var config: RenderConfig = notifications[currentIndex]

        // Paint objects
        private val titlePaint: Paint
        private val subtitlePaint: Paint
        private val contentPaint: Paint
        private val timestampPaint: Paint
        private val foldCountPaint: Paint
        private val bgPaint: Paint
        private val iconBgPaint: Paint
        private val iconTextPaint: Paint
        private val arrowPaint: Paint
        private val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

        // Transition animation
        private var transitionAlpha = 1f
        private var isTransitioning = false
        private val transitionDuration = 250L

        // Swipe gesture detection
        private val gestureDetector: GestureDetector
        private val swipeThreshold = 80f
        private val swipeVelocityThreshold = 200f

        init {
            density = context.resources.displayMetrics.density
            Log.d(TAG, "RenderView init, density=$density, listSize=${notifications.size}, index=$currentIndex")

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
            arrowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#60FFFFFF")
                style = Paint.Style.FILL
            }

            gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
                override fun onFling(
                    e1: MotionEvent?, e2: MotionEvent,
                    velocityX: Float, velocityY: Float
                ): Boolean {
                    if (isTransitioning) return false
                    val diffY = (e1?.y ?: 0f) - e2.y
                    // Swipe up -> next notification (newer)
                    if (diffY > swipeThreshold && Math.abs(velocityY) > swipeVelocityThreshold) {
                        navigateTo(currentIndex - 1)
                        return true
                    }
                    // Swipe down -> previous notification (older)
                    if (-diffY > swipeThreshold && Math.abs(velocityY) > swipeVelocityThreshold) {
                        navigateTo(currentIndex + 1)
                        return true
                    }
                    return false
                }
            })
        }

        fun updateList(newList: MutableList<RenderConfig>, newIndex: Int) {
            notifications.clear()
            notifications.addAll(newList)
            currentIndex = newIndex.coerceIn(0, (notifications.size - 1).coerceAtLeast(0))
            config = notifications[currentIndex]
            updatePaintsFromConfig()
            startTransition()
        }

        fun updateConfig(newConfig: RenderConfig) {
            this.config = newConfig
            if (currentIndex < notifications.size) {
                notifications[currentIndex] = newConfig
            }
            updatePaintsFromConfig()
            invalidate()
        }

        private fun updatePaintsFromConfig() {
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
        }

        private fun navigateTo(newIndex: Int) {
            if (newIndex < 0 || newIndex >= notifications.size) return
            if (newIndex == currentIndex) return
            currentIndex = newIndex
            config = notifications[currentIndex]
            updatePaintsFromConfig()
            startTransition()
            onNavigateCallback?.invoke(currentIndex)
        }

        private fun startTransition() {
            transitionAlpha = 0f
            isTransitioning = true
            val animator = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
                duration = transitionDuration
                interpolator = DecelerateInterpolator()
                addUpdateListener { anim ->
                    transitionAlpha = anim.animatedValue as Float
                    invalidate()
                }
                addListener(object : android.animation.AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: android.animation.Animator) {
                        isTransitioning = false
                        transitionAlpha = 1f
                    }
                })
            }
            animator.start()
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            gestureDetector.onTouchEvent(event)
            return true
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0 || h <= 0) return

            canvas.saveLayerAlpha(0f, 0f, w, h, (transitionAlpha * 255).toInt())

            val p = config.padding * density
            val s = config.spacing * density
            val ho = config.horizontalOffset * density
            val leftPad = p + ho

            // Background
            canvas.drawRect(0f, 0f, w, h, bgPaint)

            // Center content vertically
            val contentHeight = measureContentHeight(w, p, s, leftPad)
            val topOffset = maxOf(p, (h - contentHeight) / 2f)
            var y = topOffset

            // App icon row
            if (config.showAppIcon) {
                val iconSize = config.titleFontSize * density + 8f * density
                val iconRadius = iconSize * 0.2f
                val iconRect = RectF(leftPad, y, leftPad + iconSize, y + iconSize)

                if (config.appIcon != null) {
                    canvas.save()
                    val path = Path().apply {
                        addRoundRect(iconRect, iconRadius, iconRadius, Path.Direction.CW)
                    }
                    canvas.clipPath(path)
                    canvas.drawBitmap(config.appIcon!!, null, iconRect, null)
                    canvas.restore()
                } else {
                    iconBgPaint.color = (config.titleColor and 0x00FFFFFF) or 0x33000000.toInt()
                    canvas.drawRoundRect(iconRect, iconRadius, iconRadius, iconBgPaint)
                    val firstChar = if (config.appName.isNotEmpty()) config.appName.first().toString() else "?"
                    iconTextPaint.textSize = iconSize * 0.45f
                    canvas.drawText(firstChar, iconRect.centerX(), iconRect.centerY() + iconSize * 0.18f, iconTextPaint)
                }

                val appNameX = leftPad + iconSize + s * 0.6f
                val appNameBaseline = y + iconSize / 2f + config.titleFontSize * density / 2.8f
                canvas.drawText(config.appName, appNameX, appNameBaseline, titlePaint)
                y += iconSize + s
            } else {
                canvas.drawText(config.appName, leftPad, y + config.titleFontSize * density, titlePaint)
                y += config.titleFontSize * density + s
            }

            // Notification title
            if (config.title.isNotEmpty()) {
                canvas.drawText(config.title, leftPad, y + config.subtitleFontSize * density, subtitlePaint)
                y += config.subtitleFontSize * density + s
            }

            // Body text — auto-wrap + truncate
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

            // Bottom: timestamp
            val bottomY = h - p
            if (config.showTimestamp) {
                val now = timeFormat.format(Date())
                val tw = timestampPaint.measureText(now)
                canvas.drawText(now, w - p - tw, bottomY, timestampPaint)
            }

            canvas.restore()

            // Draw navigation arrows (outside the alpha transition)
            drawArrows(canvas, w, h)
        }

        private fun drawArrows(canvas: Canvas, w: Float, h: Float) {
            if (notifications.size <= 1) return

            val arrowSize = 12f * density
            val arrowMargin = 16f * density
            val centerX = w / 2f

            // Bottom arrow (more notifications below) — show when not at last item
            if (currentIndex < notifications.size - 1) {
                val path = Path().apply {
                    moveTo(centerX, h - arrowMargin)
                    lineTo(centerX - arrowSize / 2, h - arrowMargin - arrowSize)
                    lineTo(centerX + arrowSize / 2, h - arrowMargin - arrowSize)
                    close()
                }
                canvas.drawPath(path, arrowPaint)
            }

            // Top arrow (notifications above) — show when not at first item
            if (currentIndex > 0) {
                val path = Path().apply {
                    moveTo(centerX, arrowMargin)
                    lineTo(centerX - arrowSize / 2, arrowMargin + arrowSize)
                    lineTo(centerX + arrowSize / 2, arrowMargin + arrowSize)
                    close()
                }
                canvas.drawPath(path, arrowPaint)
            }
        }

        private fun measureContentHeight(w: Float, p: Float, s: Float, leftPad: Float): Float {
            var h = p

            if (config.showAppIcon) {
                h += config.titleFontSize * density + 8f * density + s
            } else {
                h += config.titleFontSize * density + s
            }

            if (config.title.isNotEmpty()) {
                h += config.subtitleFontSize * density + s
            }

            if (config.content.isNotEmpty()) {
                val maxWidth = w - leftPad - p
                val estLines = if (contentPaint.measureText(config.content) > maxWidth) {
                    minOf(3, (contentPaint.measureText(config.content) / maxWidth).toInt() + 1)
                } else {
                    1
                }
                h += estLines * contentPaint.textSize * 1.45f + s * 0.5f
            }

            h += if (config.showTimestamp) {
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
                    val lastLine = lines.removeAt(lines.lastIndex)
                    lines.add(lastLine.trimEnd().dropLast(1) + "\u2026")
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
