package com.example.fbs.service

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader

class BackScreenController(private val context: Context) {

    companion object {
        private const val TAG = "BackScreenController"
        private const val SUBSCREEN_PACKAGE = "com.xiaomi.subscreencenter"
        private const val REQUEST_CODE_SHIZUKU = 1001

        // 全局去重：同一时间窗口内不重复触发背屏显示
        private var lastForwardTime = 0L
        private val GLOBAL_COOLDOWN_MS = 3000L

        // 官方背屏应用真实的广播/Intent action
        private const val ACTION_SUB_SCREEN_ON = "miui.intent.action.SUB_SCREEN_ON"
        private const val ACTION_SUB_SCREEN_OFF = "miui.intent.action.SUB_SCREEN_OFF"
        private const val NOTIF_WIDGET_PATH =
            "/data/system/theme_magic/users/0/subscreencenter/notification/notification_widget.json"
    }

    private var permissionCallback: ((Boolean) -> Unit)? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        Log.d(TAG, "Shizuku binder received!")
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        Log.d(TAG, "Shizuku binder dead")
    }

    private val permissionResultListener =
        Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            val granted = grantResult == PackageManager.PERMISSION_GRANTED
            Log.d(TAG, "Shizuku permission result: requestCode=$requestCode, granted=$granted")
            permissionCallback?.invoke(granted)
            permissionCallback = null
        }

    fun initialize() {
        Log.d(TAG, "BackScreenController initialized with Shizuku SDK")
        Shizuku.addBinderReceivedListenerSticky(binderReceivedListener)
        Shizuku.addBinderDeadListener(binderDeadListener)
        Shizuku.addRequestPermissionResultListener(permissionResultListener)
    }

    fun isShizukuRunning(): Boolean {
        return try {
            Shizuku.pingBinder()
        } catch (e: Exception) {
            Log.e(TAG, "Error checking Shizuku", e)
            false
        }
    }

    fun hasPermission(): Boolean {
        return try {
            if (!Shizuku.pingBinder()) return false
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            Log.e(TAG, "Error checking permission", e)
            false
        }
    }

    fun requestPermission(callback: (Boolean) -> Unit) {
        permissionCallback = callback
        try {
            if (!Shizuku.pingBinder()) {
                Log.e(TAG, "Shizuku binder not available")
                callback(false)
                permissionCallback = null
                return
            }
            if (Shizuku.isPreV11()) {
                Log.e(TAG, "Shizuku version too old")
                callback(false)
                permissionCallback = null
                return
            }
            if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "Permission already granted")
                callback(true)
                permissionCallback = null
                return
            }
            Shizuku.requestPermission(REQUEST_CODE_SHIZUKU)
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting permission", e)
            callback(false)
            permissionCallback = null
        }
    }

    fun displayOnBackScreen(title: String, content: String) {
        // 全局冷却：3 秒内不重复触发背屏显示
        val now = System.currentTimeMillis()
        if (now - lastForwardTime < GLOBAL_COOLDOWN_MS) {
            Log.d(TAG, "Global cooldown active, skip (${now - lastForwardTime}ms since last)")
            return
        }
        lastForwardTime = now

        // 方法1: PinReceiveActivity (ACTION_SEND) — 不需要 Shizuku
        if (tryPinReceive(title, content)) return

        // 方法2: Shizuku shell 写 notification_widget.json + 唤醒背屏
        if (tryShizukuNotificationWidget(title, content)) return

        Log.e(TAG, "All methods failed to display on back screen")
    }

    private fun tryPinReceive(title: String, content: String): Boolean {
        return try {
            val displayText = if (title.isNotEmpty() && content.isNotEmpty()) {
                "$title\n$content"
            } else if (title.isNotEmpty()) title
            else content

            if (displayText.isEmpty()) {
                Log.d(TAG, "PinReceive: empty text, skipped")
                return false
            }

            val intent = Intent().apply {
                component = ComponentName(
                    SUBSCREEN_PACKAGE,
                    "$SUBSCREEN_PACKAGE.pin.PinReceiveActivity"
                )
                action = Intent.ACTION_SEND
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, displayText)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            Log.d(TAG, "PinReceive sent: $displayText")
            true
        } catch (e: Exception) {
            Log.d(TAG, "PinReceive failed: ${e.message}")
            false
        }
    }

    private fun tryShizukuNotificationWidget(title: String, content: String): Boolean {
        if (!isShizukuRunning() || !hasPermission()) {
            Log.d(TAG, "Shizuku not available, skip widget method")
            return false
        }

        return try {
            val json = buildNotificationWidgetJson(title, content)
            val escapedJson = json.replace("'", "'\\''")
            val writeCmd = "mkdir -p /data/system/theme_magic/users/0/subscreencenter/notification && echo '$escapedJson' > $NOTIF_WIDGET_PATH && chmod 644 $NOTIF_WIDGET_PATH"
            val writeResult = execShizukuShell(writeCmd)
            Log.d(TAG, "Widget write result: $writeResult")

            val broadcastCmd = "am broadcast -a $ACTION_SUB_SCREEN_ON -n $SUBSCREEN_PACKAGE/.SubScreenLauncher --user 0"
            val broadcastResult = execShizukuShell(broadcastCmd)
            Log.d(TAG, "Broadcast result: $broadcastResult")

            wakeUpScreen()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Shizuku widget method failed", e)
            false
        }
    }

    private fun buildNotificationWidgetJson(title: String, content: String): String {
        val timestamp = System.currentTimeMillis()
        val notifId = (timestamp % 100000).toInt()

        return """
[
  {
    "notificationId": $notifId,
    "packageName": "com.example.fbs",
    "appName": "FBS",
    "title": "${escapeJson(title)}",
    "content": "${escapeJson(content)}",
    "timestamp": $timestamp,
    "postTime": $timestamp,
    "isClearable": true,
    "userId": 0
  }
]
        """.trimIndent()
    }

    private fun escapeJson(s: String): String {
        return s.replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }

    fun wakeUpScreen() {
        if (!isShizukuRunning() || !hasPermission()) {
            Log.d(TAG, "Shizuku not available for screen wake")
            return
        }

        try {
            val cmd1 = "input keyevent 26 && input keyevent 26"
            execShizukuShell(cmd1)
            val cmd2 = "dumpsys deviceidle step; dumpsys deviceidle disable"
            execShizukuShell(cmd2)
            Log.d(TAG, "Screen wake commands executed")
        } catch (e: Exception) {
            Log.e(TAG, "Screen wake failed", e)
        }
    }

    fun setScreenTimeout(millis: Int = 90000) {
        if (!isShizukuRunning() || !hasPermission()) return
        try {
            val cmd = "settings put system screen_off_timeout $millis"
            execShizukuShell(cmd)
            Log.d(TAG, "Screen timeout set to ${millis}ms")
        } catch (e: Exception) {
            Log.e(TAG, "Set screen timeout failed", e)
        }
    }

    fun setBackScreenBrightness(brightness: Int = 128) {
        if (!isShizukuRunning() || !hasPermission()) return
        try {
            val cmd = "settings put system screen_brightness $brightness"
            execShizukuShell(cmd)
            Log.d(TAG, "Brightness set to $brightness")
        } catch (e: Exception) {
            Log.e(TAG, "Set brightness failed", e)
        }
    }

    fun sleepBackScreen() {
        if (!isShizukuRunning() || !hasPermission()) return
        try {
            val cmd = "am broadcast -a $ACTION_SUB_SCREEN_OFF --user 0"
            execShizukuShell(cmd)
            Log.d(TAG, "Back screen sleep broadcast sent")
        } catch (e: Exception) {
            Log.e(TAG, "Sleep back screen failed", e)
        }
    }

    fun removePinByNotificationId(notificationId: Int) {
        if (!isShizukuRunning() || !hasPermission()) {
            Log.d(TAG, "Shizuku not available, skip remove")
            return
        }
        try {
            val cmd = "cat $NOTIF_WIDGET_PATH 2>/dev/null"
            val currentJson = execShizukuShell(cmd)

            if (currentJson.startsWith("ERROR") || currentJson.isEmpty()) {
                Log.d(TAG, "No widget file to remove")
                return
            }

            val removeCmd = """$NOTIF_WIDGET_PATH" | python3 -c "
import json,sys
data=json.load(sys.stdin)
data=[x for x in data if x.get('notificationId')!=$notificationId]
print(json.dumps(data))
" > $NOTIF_WIDGET_PATH"""
            execShizukuShell("python3 -c \"\nimport json\nwith open('$NOTIF_WIDGET_PATH') as f:\n  data=json.load(f)\ndata=[x for x in data if x.get('notificationId')!=$notificationId]\nwith open('$NOTIF_WIDGET_PATH','w') as f:\n  json.dump(data,f)\n\"")

            val broadcastCmd = "am broadcast -a $ACTION_SUB_SCREEN_ON -n $SUBSCREEN_PACKAGE/.SubScreenLauncher --user 0"
            execShizukuShell(broadcastCmd)

            // Check if empty
            val remaining = execShizukuShell("cat $NOTIF_WIDGET_PATH 2>/dev/null")
            if (remaining == "[]" || remaining.contains("[]")) {
                execShizukuShell("am broadcast -a $ACTION_SUB_SCREEN_OFF --user 0")
            }
            Log.d(TAG, "Removed pin $notificationId")
        } catch (e: Exception) {
            Log.e(TAG, "Remove pin failed", e)
        }
    }

    fun clearAllPinsAndBackToIdle() {
        if (!isShizukuRunning() || !hasPermission()) return
        try {
            execShizukuShell("echo '[]' > $NOTIF_WIDGET_PATH")
            execShizukuShell("am broadcast -a $ACTION_SUB_SCREEN_OFF --user 0")
            Log.d(TAG, "All pins cleared")
        } catch (e: Exception) {
            Log.e(TAG, "Clear pins failed", e)
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
            BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                reader.lineSequence().forEach { line ->
                    output.appendLine(line)
                }
            }
            BufferedReader(InputStreamReader(process.errorStream)).use { reader ->
                reader.lineSequence().forEach { line ->
                    output.appendLine("[stderr] $line")
                }
            }
            process.waitFor()
            val result = output.toString().trim()
            Log.d(TAG, "Shell[$command] -> ${result.take(200)}")
            result
        } catch (e: Exception) {
            Log.e(TAG, "Shell exec failed: $command", e)
            "ERROR: ${e.message}"
        }
    }

    fun getInstalledAppsViaShizuku(callback: (List<Map<String, String>>) -> Unit) {
        Thread {
            try {
                val newProcess = Shizuku::class.java
                    .getDeclaredMethod("newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java)
                newProcess.isAccessible = true
                val process = newProcess.invoke(null,
                    arrayOf("sh", "-c", "pm list packages --user 0"),
                    null, null
                ) as Process

                val packages = mutableListOf<String>()
                BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                    reader.lineSequence().forEach { line ->
                        if (line.startsWith("package:")) {
                            packages.add(line.removePrefix("package:").trim())
                        }
                    }
                }
                process.waitFor()

                val apps = packages.mapNotNull { pkg ->
                    try {
                        val ai = context.packageManager.getApplicationInfo(pkg, 0)
                        val name = context.packageManager.getApplicationLabel(ai).toString()
                        mapOf("package" to pkg, "name" to name)
                    } catch (_: Exception) { null }
                }.sortedBy { it["name"] }

                Log.d(TAG, "Shizuku got ${apps.size} apps")
                callback(apps)
            } catch (e: Exception) {
                Log.e(TAG, "Shizuku getInstalledApps failed", e)
                callback(emptyList())
            }
        }.apply { isDaemon = true }.start()
    }

    fun destroy() {
        Shizuku.removeBinderReceivedListener(binderReceivedListener)
        Shizuku.removeBinderDeadListener(binderDeadListener)
        Shizuku.removeRequestPermissionResultListener(permissionResultListener)
        wakeLock?.let { if (it.isHeld) it.release() }
        Log.d(TAG, "BackScreenController destroyed")
    }
}
