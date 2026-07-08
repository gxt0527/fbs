package com.example.fbs.service

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.util.Log
import android.view.Display
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * 背屏控制器 — 管理背屏 display 1 上的通知显示。
 */
class BackScreenController(private val context: Context) {

    companion object {
        private const val TAG = "BackScreenController"
        private const val SUBSCREEN_PACKAGE = "com.xiaomi.subscreencenter"
        private const val REQUEST_CODE_SHIZUKU = 1001
        const val ACTION_MIRROR_REFRESH = "com.example.fbs.MIRROR_REFRESH"
        const val ACTION_MIRROR_DISMISS = "com.example.fbs.MIRROR_DISMISS"

        @Volatile
        var instance: BackScreenController? = null

        /** 背屏 Activity 是否活跃（供 ListenerService 判断 launch vs broadcast） */
        @Volatile
        var backScreenActivityAlive = false

        fun isShizukuReady(): Boolean {
            return try { Shizuku.pingBinder() } catch (_: Exception) { false }
        }
        fun hasShizukuPermission(): Boolean {
            return try { isShizukuReady() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED } catch (_: Exception) { false }
        }

        /** 通过 Shizuku 执行 shell 命令（供 BackScreenNotificationActivity 等调用） */
        fun execShell(command: String): String {
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
                output.toString().trim()
            } catch (e: Exception) {
                "ERROR: ${e.message}"
            }
        }

        /** 构建镜像模式的 am start 命令，携带通知 JSON 和样式参数 */
        fun buildMirrorLaunchCommand(context: Context, json: String, styleExtras: Map<String, String>, needsWake: Boolean): String {
            val sb = StringBuilder("am start")
            sb.append(" -n ${context.packageName}/.service.BackScreenNotificationActivity")
            val flags = 0x10200000 or 0x20000000
            sb.append(" -f $flags")
            sb.append(" --user 0")
            appendExtraStatic(sb, "notificationsJson", json)
            appendExtraStatic(sb, "mirrorMode", "true")
            appendExtraStatic(sb, "isSticky", "true")
            appendExtraStatic(sb, "needsWake", needsWake.toString())
            appendExtraStatic(sb, "isDozing", (!needsWake).toString())
            appendExtraStatic(sb, "stayAwake", "true")
            for ((k, v) in styleExtras) {
                appendExtraStatic(sb, k, v)
            }
            return sb.toString()
        }

        private fun appendExtraStatic(sb: StringBuilder, key: String, value: String) {
            val escaped = value.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\$", "\\\$")
                .replace("'", "\\'")
            sb.append(" --es $key \"$escaped\"")
        }
    }

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
    //  背屏转发 (V3 手动转发)
    // ═══════════════════════════════════════════

    fun displayOnBackScreenV2(
        title: String,
        subtitle: String,
        content: String,
        appName: String,
    ) {
        if (!isShizukuRunning() || !hasPermission()) {
            Log.e(TAG, "Shizuku unavailable, cannot display on back screen")
            return
        }
        try {
            val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            val backDisplay = dm.getDisplay(1)
            val backDisplayState = backDisplay?.state ?: Display.STATE_UNKNOWN
            val needsWake = backDisplayState == Display.STATE_OFF || backDisplayState == Display.STATE_UNKNOWN

            val launchCmd = buildLaunchCommand(title, subtitle, content, appName, needsWake)
            val combined = "input -d 1 keyevent KEYCODE_WAKEUP && $launchCmd"
            val launchResult = execShizukuShell(combined)
            Log.d(TAG, "Launch: $launchResult")
            Thread.sleep(300)

            val taskId = getOurTaskId()
            if (taskId > 0) {
                execShizukuShell("service call activity_task 50 i32 $taskId i32 1")
                Log.d(TAG, "Moved task $taskId → display 1")
            } else {
                Log.w(TAG, "No taskId found for BackScreenNotificationActivity")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Push failed", e)
        }
    }

    private fun buildLaunchCommand(
        title: String, subtitle: String, content: String, appName: String, needsWake: Boolean,
    ): String {
        val sb = StringBuilder("am start")
        sb.append(" -n ${context.packageName}/.service.BackScreenNotificationActivity")
        var flags = 0x10200000
        flags = flags or 0x20000000
        sb.append(" -f $flags")
        sb.append(" --user 0")

        appendExtraStatic(sb, "title", title)
        appendExtraStatic(sb, "subtitle", subtitle)
        appendExtraStatic(sb, "content", content)
        appendExtraStatic(sb, "appName", appName)
        appendExtraStatic(sb, "notificationKey", "manual_${System.currentTimeMillis()}")
        appendExtraStatic(sb, "isSticky", "true")
        appendExtraStatic(sb, "notificationCount", "1")
        appendExtraStatic(sb, "needsWake", needsWake.toString())
        appendExtraStatic(sb, "isDozing", "false")
        appendExtraStatic(sb, "stayAwake", "true")

        return sb.toString()
    }

    // appendExtra 已移至 companion object (appendExtraStatic)

    // ═══════════════════════════════════════════
    //  BackScreenNotificationActivity 需要的方法
    // ═══════════════════════════════════════════

    fun putBackScreenToSleep() {
        if (!isShizukuRunning() || !hasPermission()) return
        try {
            execShizukuShell("cmd display power-off 1; sleep 0.5; cmd display power-reset 1")
            Log.d(TAG, "Back screen sleep")
        } catch (e: Exception) {
            Log.e(TAG, "putBackScreenToSleep failed", e)
        }
    }

    fun restoreSystemBackScreenOnSubscreen() {
        if (!isShizukuRunning() || !hasPermission()) return
        try {
            execShizukuShell("am force-stop $SUBSCREEN_PACKAGE")
            Thread.sleep(200)
            execShizukuShell("am start --user 0 -a android.intent.action.MAIN -c android.intent.category.SECONDARY_HOME")
            Thread.sleep(500)
            val taskId = findTaskIdForPackage(SUBSCREEN_PACKAGE)
            if (taskId > 0) {
                execShizukuShell("service call activity_task 50 i32 $taskId i32 1")
            }
        } catch (e: Exception) {
            Log.e(TAG, "restore failed", e)
        }
    }

    // ═══════════════════════════════════════════
    //  辅助方法
    // ═══════════════════════════════════════════

    fun dismissBackScreen() {
        try {
            // 优先用广播: 直接通知 display 1 上的 Activity 关闭，不触发前屏
            val dismissIntent = Intent(ACTION_MIRROR_DISMISS)
            dismissIntent.setPackage(context.packageName)
            context.sendBroadcast(dismissIntent)
            Log.d(TAG, "Back screen dismiss broadcast sent")
        } catch (e: Exception) {
            Log.e(TAG, "Dismiss failed", e)
        }
    }

    private fun getOurTaskId(): Int {
        try {
            val result = execShizukuShell("am stack list")
            for (line in result.lines()) {
                if (line.contains("BackScreenNotificationActivity") && line.contains("taskId=")) {
                    return Regex("taskId=(\\d+)").find(line)?.groupValues?.get(1)?.toIntOrNull() ?: -1
                }
            }
            return -1
        } catch (e: Exception) { return -1 }
    }

    private fun findTaskIdForPackage(pkg: String): Int {
        return try {
            val result = execShizukuShell("am stack list")
            for (line in result.lines()) {
                if (line.contains(pkg) && line.contains("taskId=")) {
                    return Regex("taskId=(\\d+)").find(line)?.groupValues?.get(1)?.toIntOrNull() ?: -1
                }
            }
            -1
        } catch (_: Exception) { -1 }
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
            output.toString().trim()
        } catch (e: Exception) { "ERROR: ${e.message}" }
    }

    fun destroy() {
        Shizuku.removeBinderReceivedListener(binderReceivedListener)
        Shizuku.removeBinderDeadListener(binderDeadListener)
        Shizuku.removeRequestPermissionResultListener(permissionResultListener)
    }
}
