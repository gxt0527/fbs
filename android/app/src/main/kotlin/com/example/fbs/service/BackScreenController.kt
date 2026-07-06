package com.example.fbs.service

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.ConcurrentHashMap

/**
 * 背屏控制器 — 统一管理通知到背屏的转发。
 *
 * 可用接口（经测试）:
 * 1. am start NotificationActivity + service call activity_task 50 → 自定义 UI 到 display 1
 * 2. PinReceiveActivity (ACTION_SEND) → 文本投屏
 * 3. input keyevent WAKEUP → 唤醒屏幕
 * 4. settings → 屏幕超时控制
 * 5. force-stop subscreencenter → 防止官方背屏抢占
 *
 * 不可用接口:
 * - SUB_SCREEN_ON/OFF 广播（受保护广播）
 * - SubScreenAppProvider（需要系统权限）
 * - statusbar.notification（需要 STATUS_BAR_SERVICE 权限）
 */
class BackScreenController(private val context: Context) {

    companion object {
        private const val TAG = "BackScreenController"
        private const val SUBSCREEN_PACKAGE = "com.xiaomi.subscreencenter"
        private const val REQUEST_CODE_SHIZUKU = 1001

        private var lastForwardTime = 0L
        private val GLOBAL_COOLDOWN_MS = 800L

        // MainActivity 创建 controller 时注册这个静态引用，
        // 让 BackScreenNotificationActivity 不依赖 MainActivity 实例即可调用 Shizuku 重启系统背屏。
        @Volatile
        var instance: BackScreenController? = null
    }

    // ── 通知追踪 ──
    // 所有待显示的通知: key → NotifInfo
    private val activeNotifications = ConcurrentHashMap<String, NotifInfo>()
    // 焦点通知的 key 集合（不受超时限制）
    private val focusNotificationKeys = mutableSetOf<String>()
    // 当前显示的 notificationKey
    private var currentDisplayKey: String? = null

    data class NotifInfo(
        val key: String,
        val title: String,
        val content: String,
        val packageName: String,
        val appName: String,
        val isFocus: Boolean,
        val isOngoing: Boolean,
        val category: String,
        val subText: String,
        val bigText: String,
        val timestamp: Long,
    )

    // ── Shizuku ──

    private var permissionCallback: ((Boolean) -> Unit)? = null

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        Log.d(TAG, "Shizuku binder received!")
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        Log.d(TAG, "Shizuku binder dead")
    }

    private val permissionResultListener =
        Shizuku.OnRequestPermissionResultListener { _, grantResult ->
            val granted = grantResult == PackageManager.PERMISSION_GRANTED
            permissionCallback?.invoke(granted)
            permissionCallback = null
        }

    fun initialize() {
        Shizuku.addBinderReceivedListenerSticky(binderReceivedListener)
        Shizuku.addBinderDeadListener(binderDeadListener)
        Shizuku.addRequestPermissionResultListener(permissionResultListener)
    }

    fun isShizukuRunning() = try { Shizuku.pingBinder() } catch (_: Exception) { false }
    fun hasPermission() = try {
        isShizukuRunning() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (_: Exception) { false }

    fun requestPermission(callback: (Boolean) -> Unit) {
        permissionCallback = callback
        try {
            if (!Shizuku.pingBinder() || Shizuku.isPreV11()) { callback(false); permissionCallback = null; return }
            if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) { callback(true); permissionCallback = null; return }
            Shizuku.requestPermission(REQUEST_CODE_SHIZUKU)
        } catch (e: Exception) { callback(false); permissionCallback = null }
    }

    // ═══════════════════════════════════════════
    //  核心: 通知新增 / 更新
    // ═══════════════════════════════════════════

    /**
     * 通知到达 — 记录并推送到背屏
     * @param styleExtras 自定义样式参数 (颜色/字体/大小等)
     */
    fun onNotificationAdded(
        key: String,
        title: String,
        content: String,
        packageName: String,
        appName: String,
        isFocus: Boolean,
        isOngoing: Boolean,
        category: String,
        subText: String,
        bigText: String,
        styleExtras: Map<String, String> = emptyMap(),
    ) {
        val info = NotifInfo(
            key = key, title = title, content = content,
            packageName = packageName, appName = appName,
            isFocus = isFocus, isOngoing = isOngoing,
            category = category, subText = subText, bigText = bigText,
            timestamp = System.currentTimeMillis(),
        )

        val isUpdate = activeNotifications.containsKey(key)
        activeNotifications[key] = info

        if (isFocus) {
            focusNotificationKeys.add(key)
        }

        Log.d(TAG, "onNotification${if (isUpdate) "Updated" else "Added"}: key=$key focus=$isFocus count=${activeNotifications.size}")

        if (isFocus || activeNotifications.size == 1) {
            // 焦点通知: 始终显示最新
            // 首条通知: 立即显示
            pushToBackScreen(info, styleExtras, isUpdate)
        }
        // 多条普通通知: 只推最新 + 折叠计数，不逐条推送
        // pushToBackScreen 方法内部会处理折叠逻辑
    }

    /**
     * 通知被清除 — 同步移除背屏
     */
    fun onNotificationRemoved(key: String) {
        val wasFocus = focusNotificationKeys.remove(key)
        val info = activeNotifications.remove(key)

        Log.d(TAG, "onNotificationRemoved: key=$key wasFocus=$wasFocus remaining=${activeNotifications.size}")

        if (activeNotifications.isEmpty()) {
            // 全部清除 → 杀背屏 Activity
            dismissBackScreen()
        } else if (wasFocus && currentDisplayKey == key) {
            // 当前显示的焦点通知被清除 → 显示下一条
            val latest = getLatestNotification()
            if (latest != null) {
                pushToBackScreen(latest, emptyMap(), false)
            }
        } else if (activeNotifications.size == 1) {
            // 只剩一条 → 显示那条（可能是焦点）
            val last = activeNotifications.values.first()
            pushToBackScreen(last, emptyMap(), false)
        }
        // 多条普通通知: 折叠计数会自动调整 (notificationCount)
    }

    // ═══════════════════════════════════════════
    //  推送到背屏
    // ═══════════════════════════════════════════

    private fun pushToBackScreen(
        info: NotifInfo,
        styleExtras: Map<String, String>,
        isUpdate: Boolean,
    ) {
        val now = System.currentTimeMillis()
        if (now - lastForwardTime < GLOBAL_COOLDOWN_MS) {
            Log.d(TAG, "Cooldown, delay push for ${info.key}")
            // 延迟再推
            Thread {
                Thread.sleep(GLOBAL_COOLDOWN_MS)
                doPush(info, styleExtras, isUpdate)
            }.apply { isDaemon = true }.start()
            return
        }
        lastForwardTime = now
        doPush(info, styleExtras, isUpdate)
    }

    private fun doPush(info: NotifInfo, styleExtras: Map<String, String>, isUpdate: Boolean) {
        if (!isShizukuRunning() || !hasPermission()) {
            Log.e(TAG, "Shizuku unavailable, skip push")
            return
        }

        currentDisplayKey = info.key

        try {
            // 1. 唤醒
            execShizukuShell("input keyevent KEYCODE_WAKEUP")

            // 2. 构建启动命令（先 display 0，再 move 到 display 1）
            val launchCmd = buildLaunchCommand(info, styleExtras)
            val launchResult = execShizukuShell(launchCmd)
            Log.d(TAG, "Launch: $launchResult")
            Thread.sleep(300)

            // 3. 移屏 + 杀官方背屏
            val taskId = getOurTaskId()
            if (taskId > 0) {
                execShizukuShell("service call activity_task 50 i32 $taskId i32 1; am force-stop $SUBSCREEN_PACKAGE")
                Log.d(TAG, "Moved task $taskId → display 1, killed subscreencenter")
            } else {
                Log.w(TAG, "No taskId found for BackScreenNotificationActivity")
            }

            // 4. 确保亮屏不灭
            execShizukuShell("settings put system screen_off_timeout 90000")

        } catch (e: Exception) {
            Log.e(TAG, "Push failed", e)
        }
    }

    /**
     * 构建 am start 命令
     */
    private fun buildLaunchCommand(info: NotifInfo, styleExtras: Map<String, String>): String {
        val sb = StringBuilder("am start")
        sb.append(" -n ${context.packageName}/.service.BackScreenNotificationActivity")
        sb.append(" -f 0x10000000") // FLAG_ACTIVITY_NEW_TASK
        if (activeNotifications.containsKey(info.key)) {
            sb.append(" -f 0x20000000") // FLAG_ACTIVITY_SINGLE_TOP → 触发 onNewIntent
        }
        sb.append(" --user 0")

        // 通知字段
        appendExtra(sb, "title", info.title)
        appendExtra(sb, "subtitle", info.subText)
        appendExtra(sb, "content", info.content)
        appendExtra(sb, "appName", info.appName)
        appendExtra(sb, "packageName", info.packageName)
        appendExtra(sb, "category", info.category)
        appendExtra(sb, "notificationKey", info.key)
        appendExtra(sb, "isFocus", info.isFocus.toString())
        appendExtra(sb, "isSticky", info.isFocus.toString()) // 焦点通知 = 粘性
        appendExtra(sb, "notificationCount", activeNotifications.size.toString())

        // 计数大于 1 时，内容展示折叠信息
        if (activeNotifications.size > 1 && !info.isFocus) {
            appendExtra(sb, "notificationCount", activeNotifications.size.toString())
        }

        // 自定义样式
        appendExtra(sb, "titleFontSize", styleExtras["titleFontSize"] ?: "28")
        appendExtra(sb, "subtitleFontSize", styleExtras["subtitleFontSize"] ?: "20")
        appendExtra(sb, "contentFontSize", styleExtras["contentFontSize"] ?: "16")
        appendExtra(sb, "titleColor", styleExtras["titleColor"] ?: "#FFFFFF")
        appendExtra(sb, "subtitleColor", styleExtras["subtitleColor"] ?: "#B0B0B0")
        appendExtra(sb, "contentColor", styleExtras["contentColor"] ?: "#E0E0E0")
        appendExtra(sb, "backgroundColor", styleExtras["backgroundColor"] ?: "#1A1A2E")
        appendExtra(sb, "padding", styleExtras["padding"] ?: "24")
        appendExtra(sb, "spacing", styleExtras["spacing"] ?: "12")
        appendExtra(sb, "showAppIcon", styleExtras["showAppIcon"] ?: "true")
        appendExtra(sb, "showTimestamp", styleExtras["showTimestamp"] ?: "true")

        // 非焦点通知超时
        if (!info.isFocus) {
            appendExtra(sb, "displayDurationMs", styleExtras["displayDurationMs"] ?: "8000")
        }

        return sb.toString()
    }

    private fun appendExtra(sb: StringBuilder, key: String, value: String) {
        val escaped = value.replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\$", "\\\$")
            .replace("'", "\\'")
        sb.append(" --es $key \"$escaped\"")
    }

    // ═══════════════════════════════════════════
    //  背屏管理
    // ═══════════════════════════════════════════

    /**
     * 恢复官方背屏 (subscreencenter) 到 display 1。
     *
     * 方案：am start --display 1 在小米设备上会被系统 abort（"show on rear display"），
     * 所以改用已验证可用的组合：
     *   1. am start -n <component>  → 启动到 display 0
     *   2. service call activity_task 50 i32 <taskId> i32 1  → 移到 display 1
     *
     * Shizuku 不可用时退化为普通 startActivity（至少能拉起包）。
     */
    fun restoreSystemBackScreenOnSubscreen() {
        if (!isShizukuRunning() || !hasPermission()) {
            Log.w(TAG, "Shizuku unavailable, restore via startActivity fallback")
            try {
                val intent = context.packageManager.getLaunchIntentForPackage(SUBSCREEN_PACKAGE)
                if (intent != null) {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Restore subscreen fallback failed", e)
            }
            return
        }
        try {
            // Step 1: force-stop 清除旧实例
            execShizukuShell("am force-stop $SUBSCREEN_PACKAGE")
            Thread.sleep(200)

            // Step 2: 启动 subscreencenter（会在 display 0 出现）
            val launchIntent = context.packageManager.getLaunchIntentForPackage(SUBSCREEN_PACKAGE)
            if (launchIntent == null) {
                Log.w(TAG, "Cannot find subscreen launch intent")
                return
            }
            val componentName = launchIntent.component
            if (componentName != null) {
                execShizukuShell(
                    "am start --user 0 -n ${componentName.flattenToShortString()}"
                )
            } else {
                execShizukuShell(
                    "monkey -p $SUBSCREEN_PACKAGE -c android.intent.category.LAUNCHER 1"
                )
            }
            Log.d(TAG, "Started subscreencenter on display 0")

            // Step 3: 等待启动完成后，找到其 taskId 并移到 display 1
            Thread.sleep(500)
            val taskId = findTaskIdForPackage(SUBSCREEN_PACKAGE)
            if (taskId > 0) {
                execShizukuShell(
                    "service call activity_task 50 i32 $taskId i32 1"
                )
                Log.d(TAG, "Moved subscreen task $taskId → display 1")
            } else {
                Log.w(TAG, "Cannot find subscreencenter task to move")
            }
        } catch (e: Exception) {
            Log.e(TAG, "restoreSystemBackScreenOnSubscreen failed", e)
        }
    }

    /** 在 am stack list 输出里查找给 packageName 的 task id */
    private fun findTaskIdForPackage(pkg: String): Int {
        return try {
            val result = execShizukuShell("am stack list")
            for (line in result.lines()) {
                if (line.contains(pkg) && line.contains("taskId=")) {
                    return Regex("taskId=(\\d+)")
                        .find(line)?.groupValues?.get(1)?.toIntOrNull() ?: continue
                }
            }
            -1
        } catch (_: Exception) { -1 }
    }

    fun dismissBackScreen() {
        if (!isShizukuRunning() || !hasPermission()) return
        currentDisplayKey = null
        try {
            Log.d(TAG, "Dismissing back screen via intent")
            // 发送 dismiss 指令给 BackScreenNotificationActivity（SINGLE_TOP → onNewIntent）
            // Activity 收到后会 finish 并自动启动官方背屏
            val dismissCmd = BackScreenNotificationActivity.buildDismissIntent(context)
            execShizukuShell(dismissCmd)
            Log.d(TAG, "Back screen dismissed, subcreen will be restored by Activity")
        } catch (e: Exception) {
            Log.e(TAG, "Dismiss failed", e)
        }
    }

    /**
     * 获取最新通知（优先焦点通知）
     */
    private fun getLatestNotification(): NotifInfo? {
        if (activeNotifications.isEmpty()) return null
        // 优先焦点
        val focus = activeNotifications.values.firstOrNull { it.key in focusNotificationKeys }
        if (focus != null) return focus
        // 最新普通通知
        return activeNotifications.values.maxByOrNull { it.timestamp }
    }

    // ═══════════════════════════════════════════
    //  兼容旧接口
    // ═══════════════════════════════════════════

    fun displayOnBackScreen(title: String, content: String) {
        onNotificationAdded(
            key = "manual_${System.currentTimeMillis()}",
            title = title, content = content,
            packageName = context.packageName, appName = "FBS",
            isFocus = false, isOngoing = false,
            category = "", subText = "", bigText = "",
        )
    }

    fun displayNotificationOnBackScreenV2(
        title: String, subtitle: String, content: String,
        appName: String, packageName: String,
        styleExtras: Map<String, String>,
    ) {
        onNotificationAdded(
            key = "v2_${System.currentTimeMillis()}",
            title = title, content = content,
            packageName = packageName, appName = appName,
            isFocus = true, isOngoing = false,
            category = "", subText = subtitle, bigText = "",
            styleExtras = styleExtras,
        )
    }

    // ═══════════════════════════════════════════
    //  辅助方法
    // ═══════════════════════════════════════════

    private fun getOurTaskId(): Int {
        try {
            val result = execShizukuShell("am stack list")
            var latestId = -1
            for (line in result.lines()) {
                if (line.contains("BackScreenNotificationActivity") && line.contains("taskId=")) {
                    val id = Regex("taskId=(\\d+)").find(line)?.groupValues?.get(1)?.toIntOrNull() ?: continue
                    if (id > latestId) latestId = id
                }
            }
            return latestId
        } catch (e: Exception) {
            Log.e(TAG, "getTaskId error", e)
        }
        return -1
    }

    fun wakeUpScreen() {
        if (!isShizukuRunning() || !hasPermission()) return
        execShizukuShell("input keyevent KEYCODE_WAKEUP; dumpsys deviceidle disable")
    }

    fun setScreenTimeout(millis: Int = 90000) {
        if (!isShizukuRunning() || !hasPermission()) return
        execShizukuShell("settings put system screen_off_timeout $millis")
    }

    fun setBackScreenBrightness(brightness: Int = 128) {
        if (!isShizukuRunning() || !hasPermission()) return
        execShizukuShell("settings put system screen_brightness $brightness")
    }

    private fun execShizukuShell(command: String): String {
        return try {
            val execMethod = Shizuku::class.java.getDeclaredMethod(
                "newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java
            )
            execMethod.isAccessible = true
            val process = execMethod.invoke(null,
                arrayOf("sh", "-c", command), null, null
            ) as Process

            val output = StringBuilder()
            BufferedReader(InputStreamReader(process.inputStream)).use { r ->
                r.lineSequence().forEach { output.appendLine(it) }
            }
            BufferedReader(InputStreamReader(process.errorStream)).use { r ->
                r.lineSequence().forEach { output.appendLine("[e] $it") }
            }
            process.waitFor()
            val result = output.toString().trim()
            if (result.length > 200) Log.d(TAG, "Shell: ${result.take(200)}...")
            else Log.d(TAG, "Shell: $result")
            result
        } catch (e: Exception) {
            Log.e(TAG, "Shell failed: $command — ${e.message}")
            "ERROR: ${e.message}"
        }
    }

    fun getInstalledAppsViaShizuku(callback: (List<Map<String, String>>) -> Unit) {
        Thread {
            try {
                val newProcess = Shizuku::class.java.getDeclaredMethod(
                    "newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java
                )
                newProcess.isAccessible = true
                val process = newProcess.invoke(null,
                    arrayOf("sh", "-c", "pm list packages --user 0"), null, null
                ) as Process
                val packages = mutableListOf<String>()
                BufferedReader(InputStreamReader(process.inputStream)).use { r ->
                    r.lineSequence().filter { it.startsWith("package:") }
                        .forEach { packages.add(it.removePrefix("package:").trim()) }
                }
                process.waitFor()
                var failed = 0
                val apps = packages.mapNotNull { pkg ->
                    try {
                        val ai = context.packageManager.getApplicationInfo(pkg, 0)
                        val name = context.packageManager.getApplicationLabel(ai).toString()
                        mapOf("package" to pkg, "name" to name)
                    } catch (_: Exception) { failed++; null }
                }.sortedBy { it["name"] }
                callback(apps)
            } catch (e: Exception) {
                Log.e(TAG, "getInstalledApps failed", e)
                callback(emptyList())
            }
        }.apply { isDaemon = true }.start()
    }

    fun destroy() {
        Shizuku.removeBinderReceivedListener(binderReceivedListener)
        Shizuku.removeBinderDeadListener(binderDeadListener)
        Shizuku.removeRequestPermissionResultListener(permissionResultListener)
    }
}
