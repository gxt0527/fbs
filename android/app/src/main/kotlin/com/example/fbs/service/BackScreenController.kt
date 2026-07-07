package com.example.fbs.service

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.os.PowerManager
import android.util.Log
import android.view.Display
import org.json.JSONArray
import org.json.JSONObject
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
        private val GLOBAL_COOLDOWN_MS = 1500L

        // MainActivity 创建 controller 时注册这个静态引用，
        // 让 BackScreenNotificationActivity 不依赖 MainActivity 实例即可调用 Shizuku 重启系统背屏。
        @Volatile
        var instance: BackScreenController? = null

        /**
         * 缓存最近一次通过 Flutter 传入的样式参数。
         * 系统 NotificationListener 转发通知时不带 styleExtras，
         * 用此缓存确保摄像头避让等设置不丢失。
         */
        @Volatile
        var latestStyleExtras: Map<String, String> = emptyMap()
    }

    // ── 通知追踪 ──
    // 所有待显示的通知: key → NotifInfo
    private val activeNotifications = ConcurrentHashMap<String, NotifInfo>()
    // 焦点通知的 key 集合（不受超时限制）
    private val focusNotificationKeys = mutableSetOf<String>()
    // 当前显示的 notificationKey
    private var currentDisplayKey: String? = null

    /**
     * 防竟态：记录已被系统移除但 Flutter 异步回调尚未到达的 key。
     * onNotificationRemoved 由系统通知监听直接调用（同步），
     * 而 onNotificationAdded 经过 Flutter EventChannel → Dart → MethodChannel（异步）。
     * 若通知在此异步间隙被移除，Flutter 到达时会错误地将已删除的通知重新添加。
     * 此集合在 remove 时加入，冷却期后自动清除。
     */
    private val recentlyRemovedKeys = ConcurrentHashMap.newKeySet<String>()

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
        // 防竟态: Flutter 异步回调到达时通知可能已被系统移除
        // 发生在: 系统通知快速到达→移除，Flutter EventChannel→MethodChannel 延迟数百 ms
        if (recentlyRemovedKeys.contains(key)) {
            Log.d(TAG, "Rejecting add for recently removed key: $key (Flutter async race)")
            return
        }
        // 缓存 Flutter 传入的样式（含摄像头避让参数），
        // 系统 NotificationListener 路径不传 styleExtras 时使用缓存值
        if (styleExtras.isNotEmpty()) {
            latestStyleExtras = styleExtras
        }

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
            pushToBackScreen(info, styleExtras, isUpdate)
        }
        // pushToBackScreen 方法内部会处理折叠逻辑
    }

    /**
     * 通知被清除 — 同步移除背屏
     */
    fun onNotificationRemoved(key: String) {
        val wasFocus = focusNotificationKeys.remove(key)
        val info = activeNotifications.remove(key)

        // 防竟态: 记录已移除 key，阻止 Flutter 异步回调重新添加
        recentlyRemovedKeys.add(key)
        Thread {
            Thread.sleep(GLOBAL_COOLDOWN_MS + 1000)
            recentlyRemovedKeys.remove(key)
        }.apply { isDaemon = true }.start()

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
            // 延迟再推，但推送前检查通知是否已被清除（防止前屏清除后背屏残留）
            val delayKey = info.key
            Thread {
                Thread.sleep(GLOBAL_COOLDOWN_MS)
                // 竟态保护：如果通知在冷却期间已被移除，跳过推送
                if (!activeNotifications.containsKey(delayKey)) {
                    Log.d(TAG, "Delayed push cancelled: $delayKey already removed")
                    return@Thread
                }
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
            // 检测背屏 display 1 的当前状态：
            val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            val backDisplay = dm.getDisplay(1)
            val backDisplayState = backDisplay?.state ?: Display.STATE_UNKNOWN
            val screenAlreadyOn = backDisplayState == Display.STATE_ON
            // DOZE (3) = 低功耗 AOD 渲染, DOZE_SUSPEND (4) = 更深层挂起
            val isDozing = backDisplayState == Display.STATE_DOZE || backDisplayState == Display.STATE_DOZE_SUSPEND
            // needsWake 传给 Activity，用于决定是否加 FLAG_KEEP_SCREEN_ON
            val needsWake = backDisplayState == Display.STATE_OFF || backDisplayState == Display.STATE_UNKNOWN
            Log.d(TAG, "Back display state=$backDisplayState (ON=$screenAlreadyOn isDozing=$isDozing needsWake=$needsWake)")

            // 构建启动命令
            val launchCmd = buildLaunchCommand(info, styleExtras, needsWake, isDozing)

            // 始终先唤醒背屏（DOZE/OFF → ON），确保 Activity 能在 display 1 渲染
            // 已亮屏时 KEYCODE_WAKEUP 是 no-op；使用 -d 1 指定只操作背屏，避免误触正面屏幕
            val combined = "input -d 1 keyevent KEYCODE_WAKEUP && $launchCmd"
            val launchResult = execShizukuShell(combined)
            Log.d(TAG, "Launch: $launchResult")
            Thread.sleep(300)

            // 移屏到 display 1（不杀 subscreencenter，让它自然退到后台）
            val taskId = getOurTaskId()
            if (taskId > 0) {
                execShizukuShell("service call activity_task 50 i32 $taskId i32 1")
                Log.d(TAG, "Moved task $taskId → display 1")
                // 不再 force-stop subscreencenter — 让它留在后台
                // 我们 Activity 在前台时它被覆盖，finish 后它自然恢复
                // 好处: 不需要 restore 步骤，避免 SECONDARY_HOME 选择对话框
            } else {
                Log.w(TAG, "No taskId found for BackScreenNotificationActivity")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Push failed", e)
        }
    }

    /**
     * 构建 am start 命令
     */
    private fun buildLaunchCommand(info: NotifInfo, styleExtras: Map<String, String>, needsWake: Boolean, isDozing: Boolean): String {
        // 合并缓存样式：系统 NotificationListener 路径不传 styleExtras 时使用缓存值
        val mergedExtras = if (styleExtras.isEmpty() && latestStyleExtras.isNotEmpty()) {
            Log.d(TAG, "Using cached styleExtras (cameraAvoid=${latestStyleExtras["cameraAvoidanceEnabled"]})")
            latestStyleExtras
        } else {
            styleExtras
        }

        val sb = StringBuilder("am start")
        sb.append(" -n ${context.packageName}/.service.BackScreenNotificationActivity")
        // FLAG_ACTIVITY_NEW_TASK(0x10000000) + FLAG_ACTIVITY_NO_ANIMATION(0x00200000)
        // NO_ANIMATION 防止 Activity 在 display 0 短暂显示时的视觉闪烁
        var flags = 0x10200000
        if (activeNotifications.containsKey(info.key)) {
            // 追加 FLAG_ACTIVITY_SINGLE_TOP(0x20000000) → 触发 onNewIntent
            flags = flags or 0x20000000
        }
        sb.append(" -f $flags")
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

        // 自定义样式（使用合并后的缓存）
        appendExtra(sb, "titleFontSize", mergedExtras["titleFontSize"] ?: "28")
        appendExtra(sb, "subtitleFontSize", mergedExtras["subtitleFontSize"] ?: "20")
        appendExtra(sb, "contentFontSize", mergedExtras["contentFontSize"] ?: "16")
        appendExtra(sb, "titleColor", mergedExtras["titleColor"] ?: "#FFFFFF")
        appendExtra(sb, "subtitleColor", mergedExtras["subtitleColor"] ?: "#B0B0B0")
        appendExtra(sb, "contentColor", mergedExtras["contentColor"] ?: "#E0E0E0")
        appendExtra(sb, "backgroundColor", mergedExtras["backgroundColor"] ?: "#1A1A2E")
        appendExtra(sb, "padding", mergedExtras["padding"] ?: "24")
        appendExtra(sb, "spacing", mergedExtras["spacing"] ?: "12")
        appendExtra(sb, "showAppIcon", mergedExtras["showAppIcon"] ?: "true")
        appendExtra(sb, "showTimestamp", mergedExtras["showTimestamp"] ?: "true")
        appendExtra(sb, "cameraAvoidanceEnabled", mergedExtras["cameraAvoidanceEnabled"] ?: "false")
        appendExtra(sb, "horizontalOffset", mergedExtras["horizontalOffset"] ?: "0")

        // 不设置自动消失 — 所有通知保持显示直到被系统清除
        // 由 BackScreenController.onNotificationRemoved 控制消失逻辑

        // 传递屏幕初始状态，Activity 据此决定是否加 FLAG_KEEP_SCREEN_ON
        // needsWake: 背屏完全关闭时 true → 加 FLAG_KEEP_SCREEN_ON
        // isDozing: 背屏 AOD 时 true → 不加 FLAG_KEEP_SCREEN_ON
        appendExtra(sb, "needsWake", needsWake.toString())
        appendExtra(sb, "isDozing", isDozing.toString())

        // 传递全部活跃通知列表（JSON），供 Activity 多通知切换
        val notificationsJson = buildNotificationsJson(info.key)
        appendExtra(sb, "notificationsJson", notificationsJson)

        return sb.toString()
    }

    /**
     * 将全部活跃通知序列化为 JSON 数组，按时间戳倒序排列。
     * Activity 解析后支持上下滑动切换查看。
     */
    private fun buildNotificationsJson(currentKey: String): String {
        val arr = JSONArray()
        val sorted = activeNotifications.values.sortedByDescending { it.timestamp }
        for (n in sorted) {
            val obj = JSONObject().apply {
                put("key", n.key)
                put("title", n.title)
                put("content", n.content)
                put("appName", n.appName)
                put("packageName", n.packageName)
                put("category", n.category)
                put("isFocus", n.isFocus)
                put("isSticky", n.isFocus)
                put("subText", n.subText)
                put("timestamp", n.timestamp)
            }
            arr.put(obj)
        }
        Log.d(TAG, "notificationsJson: ${arr.length()} items, current=$currentKey")
        return arr.toString()
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

            // Step 2: 启动 subscreencenter
            // subscreencenter 是 SECONDARY_HOME，没有 CATEGORY_LAUNCHER，
            // 无法通过 getLaunchIntentForPackage 获取。
            // 使用 am start -a MAIN -c SECONDARY_HOME 启动
            execShizukuShell(
                "am start --user 0 -a android.intent.action.MAIN -c android.intent.category.SECONDARY_HOME"
            )
            Log.d(TAG, "Started subscreencenter on display 0 via SECONDARY_HOME")

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
        currentDisplayKey = null
        try {
            Log.d(TAG, "Dismissing back screen")

            // 方案1: 通过 Shizuku am start 发送 dismiss Intent（SINGLE_TOP → onNewIntent → finish）
            if (isShizukuRunning() && hasPermission()) {
                val dismissCmd = BackScreenNotificationActivity.buildDismissIntent(context)
                execShizukuShell(dismissCmd)
                Log.d(TAG, "Back screen dismissed via Shizuku")
                return
            }

            // 方案2: Shizuku 不可用，直接 startActivity 发送 dismiss Intent
            Log.w(TAG, "Shizuku unavailable, fallback to startActivity dismiss")
            val intent = Intent(context, BackScreenNotificationActivity::class.java)
            intent.putExtra("dismiss", "true")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            context.startActivity(intent)
            Log.d(TAG, "Back screen dismissed via startActivity")
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
        notificationKey: String = "",
    ) {
        val key = notificationKey.ifEmpty { "v2_${System.currentTimeMillis()}" }
        onNotificationAdded(
            key = key,
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

    /**
     * 检查背屏 (display 1) 是否处于 AOD 状态。
     * 在 AOD 期间不推送通知，避免 Activity 把 display 从 DOZE 拉到 ON 破坏 AOD 渲染。
     */
    private fun isDozing(): Boolean {
        return try {
            val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            val backDisplay = dm.getDisplay(1) ?: return false
            backDisplay.state == Display.STATE_DOZE || backDisplay.state == Display.STATE_DOZE_SUSPEND
        } catch (_: Exception) { false }
    }

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

    /**
     * 将背屏 (display 1) 送回 AOD。在背屏 Activity 关闭后调用。
     * 先 power-off 让 display 1 熄灭，再 power-reset 让它回到系统认为"应有"的状态。
     * 如果 AOD 已启用，系统会重新渲染 AOD 时钟；只作用于 display 1，不影响正面屏幕。
     */
    fun putBackScreenToSleep() {
        if (!isShizukuRunning() || !hasPermission()) {
            Log.w(TAG, "Cannot sleep back screen: Shizuku unavailable")
            return
        }
        try {
            // 单条 power-reset 无法让 Activity 唤醒后的 display 1 回到 AOD，
            // 需要先把背屏熄灭，再 reset 才能触发 AOD 重新渲染。
            execShizukuShell("cmd display power-off 1; sleep 0.5; cmd display power-reset 1")
            Log.d(TAG, "Back screen (display 1) power-off then reset to AOD")
        } catch (e: Exception) {
            Log.e(TAG, "putBackScreenToSleep failed", e)
        }
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
