package com.example.fbs.service

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.*
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*
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
        private val GLOBAL_COOLDOWN_MS = 1500L

        // 官方背屏应用真实的广播/Intent action
        private const val ACTION_SUB_SCREEN_ON = "miui.intent.action.SUB_SCREEN_ON"
        private const val ACTION_SUB_SCREEN_OFF = "miui.intent.action.SUB_SCREEN_OFF"
        private const val NOTIF_WIDGET_PATH =
            "/data/system/theme_magic/users/0/subscreencenter/notification/notification_widget.json"

        /** 供 BackScreenNotificationActivity 等外部调用的 Shizuku shell 执行接口 */
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
                java.io.BufferedReader(java.io.InputStreamReader(process.inputStream)).use { r ->
                    r.lineSequence().forEach { output.appendLine(it) }
                }
                java.io.BufferedReader(java.io.InputStreamReader(process.errorStream)).use { r ->
                    r.lineSequence().forEach { output.appendLine("[e] $it") }
                }
                process.waitFor()
                output.toString().trim()
            } catch (e: Exception) {
                "ERROR: ${e.message}"
            }
        }
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

    /**
     * 背屏显示 — 全部走 Shizuku 通道
     * 流程: 写 notification_widget.json → 广播 SUB_SCREEN_ON → 唤醒屏幕 → 设 90s 超时
     * @deprecated 此方法因 SELinux 拦截 + 受保护广播而失效，请使用 displayNotificationOnBackScreenV2
     */
    fun displayOnBackScreen(title: String, content: String) {
        // 全局冷却：3 秒内不重复触发
        val now = System.currentTimeMillis()
        if (now - lastForwardTime < GLOBAL_COOLDOWN_MS) {
            Log.d(TAG, "Global cooldown active, skip (${now - lastForwardTime}ms since last)")
            return
        }
        lastForwardTime = now

        if (!isShizukuRunning() || !hasPermission()) {
            Log.e(TAG, "Shizuku not available, cannot forward to back screen")
            return
        }

        // 转调 V2 方法（MRSS 风格直接投屏）
        displayNotificationOnBackScreenV2(
            title = title,
            subtitle = "",
            content = content,
            appName = "FBS",
            packageName = "com.example.fbs",
            styleExtras = emptyMap()
        )
    }

    /**
     * V2 背屏通知显示 — MRSS 风格：service call activity_task 50 移动任务到 display 1
     *
     * 分两步：
     * 1. 先在 display 0 启动 Activity（MRSS 验证过 am start --display 1 在 HyperOS 上不生效）
     * 2. 获取 taskId 后通过 service call activity_task 50 移动到 display 1
     * 3. 杀 subscreencenter 防止抢占
     */
    fun displayNotificationOnBackScreenV2(
        title: String,
        subtitle: String,
        content: String,
        appName: String,
        packageName: String,
        styleExtras: Map<String, String>,
        category: String = "general",
    ) {
        val now = System.currentTimeMillis()
        if (now - lastForwardTime < GLOBAL_COOLDOWN_MS) {
            Log.d(TAG, "Global cooldown active, skip (${now - lastForwardTime}ms since last)")
            return
        }
        lastForwardTime = now

        if (!isShizukuRunning() || !hasPermission()) {
            Log.e(TAG, "Shizuku not available, cannot forward to back screen")
            return
        }

        try {
            // 0. 唤醒设备（不杀 subscreencenter，避免黑屏间隙）
            execShizukuShell("input keyevent KEYCODE_WAKEUP; input keyevent KEYCODE_WAKEUP")
            execShizukuShell("dumpsys deviceidle disable")

            // 1. 直接 startActivity（同一进程，taskId 正常分配）
            val intent = android.content.Intent(context, Class.forName("com.example.fbs.service.BackScreenNotificationActivity")).apply {
                putExtra("title", title)
                putExtra("subtitle", subtitle)
                putExtra("content", content)
                putExtra("appName", appName)
                putExtra("packageName", packageName)
                putExtra("category", category)
                // 传递全部样式参数
                for ((k, v) in styleExtras) {
                    putExtra(k, v)
                }
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            Thread.sleep(500)

            // 2. 移到 display 1 + 杀 subscreencenter + 防AOD
            val taskId = getOurTaskId()
            if (taskId > 0) {
                val chain = "service call activity_task 50 i32 $taskId i32 1; am force-stop $SUBSCREEN_PACKAGE; input keyevent KEYCODE_WAKEUP"
                execShizukuShell(chain)
                Log.d(TAG, "Done: move ${taskId} → kill → wake")
            } else {
                Log.w(TAG, "No task found")
            }

            // 3. 不延迟再杀，subscreencenter 复活过快则放弃
            Thread {
                try {
                    Thread.sleep(500)
                    execShizukuShell("am force-stop $SUBSCREEN_PACKAGE")
                } catch (_: Exception) {}
            }.start()

        } catch (e: Exception) {
            Log.e(TAG, "displayNotificationOnBackScreenV2 failed", e)
        }
    }

    /**
     * 图片贴背屏 — 走官方 PinReceiveActivity（无需 Shizuku）
     * 流程: 渲染通知 → Bitmap → PNG → FileProvider URI → ACTION_SEND image/png → PinReceiveActivity
     */
    fun renderAndPinImage(title: String, subtitle: String, content: String): String {
        return try {
            val w = 976; val h = 596; val p = 48f; val density = 3.0f
            val titleSize = 28f * density; val bodySize = 16f * density

            val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)

            canvas.drawColor(Color.parseColor("#1A1A1E"))

            val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE; textSize = titleSize; typeface = Typeface.DEFAULT_BOLD
            }
            val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#BBBBBB"); textSize = bodySize
            }

            var y = p
            canvas.drawText(title.take(30), p, y + titleSize, titlePaint)
            y += titleSize + 14f * density

            if (subtitle.isNotEmpty()) {
                canvas.drawText(subtitle.take(40), p, y + bodySize, bodyPaint)
                y += bodySize + 10f * density
            }

            val maxWidth = w - p * 2f
            for (line in wrapText(content, bodyPaint, maxWidth)) {
                canvas.drawText(line, p, y + bodySize, bodyPaint)
                y += bodySize + 4f * density
            }

            val wmPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#555555"); textSize = 11f * density
            }
            canvas.drawText("FBS ${SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())}", p, h - p, wmPaint)

            val file = File(context.cacheDir, "fbs_pin.png")
            FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 90, it) }
            bitmap.recycle()

            val uri = androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
            context.grantUriPermission(SUBSCREEN_PACKAGE, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)

            val intent = Intent().apply {
                setClassName(SUBSCREEN_PACKAGE, "${SUBSCREEN_PACKAGE}.pin.PinReceiveActivity")
                action = Intent.ACTION_SEND
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_TEXT, "$title $content")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)
            Log.d(TAG, "Image pinned to back screen: ${file.length()} bytes")
            "ok"
        } catch (e: Exception) {
            Log.e(TAG, "renderAndPinImage failed", e)
            "failed: ${e.message}"
        }
    }

    /**
     * 将分享过来的图片 URI 转发到背屏（PinReceiveActivity）
     */
    fun forwardSharedImage(imageUri: String): String {
        return try {
            val uri = android.net.Uri.parse(imageUri)
            // 复制到缓存目录以获取稳定的文件路径
            val inputStream = context.contentResolver.openInputStream(uri)
                ?: return "failed: cannot open URI"
            val file = File(context.cacheDir, "fbs_shared_image.png")
            FileOutputStream(file).use { out ->
                inputStream.copyTo(out)
            }
            inputStream.close()

            val fileUri = androidx.core.content.FileProvider.getUriForFile(
                context, "${context.packageName}.fileprovider", file
            )
            context.grantUriPermission(SUBSCREEN_PACKAGE, fileUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)

            val intent = Intent().apply {
                setClassName(SUBSCREEN_PACKAGE, "${SUBSCREEN_PACKAGE}.pin.PinReceiveActivity")
                action = Intent.ACTION_SEND
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, fileUri)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)
            Log.d(TAG, "Shared image forwarded to back screen: ${file.length()} bytes")
            "ok"
        } catch (e: Exception) {
            Log.e(TAG, "forwardSharedImage failed", e)
            "failed: ${e.message}"
        }
    }

    private fun getOurTaskId(): Int {
        try {
            val result = execShizukuShell("dumpsys activity activities")
            // BackScreenNotificationActivity 在单独一行，不是 Task{...} 行
            // 格式: ActivityRecord{... BackScreenNotificationActivity t19704 f}}
            for (line in result.lines()) {
                if (line.contains("BackScreenNotificationActivity")) {
                    // 在行中找 t19704(数字)
                    val match = Regex("t(\\d+)").find(line)
                    val id = match?.groupValues?.get(1)?.toIntOrNull() ?: continue
                    Log.d(TAG, "Found BackScreenNotificationActivity taskId=$id")
                    return id
                }
            }
            Log.w(TAG, "BackScreenNotificationActivity not found in dumpsys")
        } catch (e: Exception) {
            Log.e(TAG, "Error getting taskId", e)
        }
        return -1
    }

    /**
     * 构建 am start 命令 — 先在 display 0 启动，后续通过 service call 移动到 display 1
     */
    private fun buildLaunchCommand(
        title: String,
        subtitle: String,
        content: String,
        appName: String,
        packageName: String,
        styleExtras: Map<String, String>,
    ): String {
        val sb = StringBuilder()
        sb.append("am start")
        sb.append(" -n ${context.packageName}/.service.BackScreenNotificationActivity")
        sb.append(" -f 0x10000000")  // FLAG_ACTIVITY_NEW_TASK
        sb.append(" --user 0")

        fun appendExtra(key: String, value: String) {
            val escaped = value.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\$", "\\\$")
                .replace("'", "\\'")
            sb.append(" --es $key \"$escaped\"")
        }

        appendExtra("title", title)
        appendExtra("subtitle", subtitle)
        appendExtra("content", content)
        appendExtra("appName", appName)
        appendExtra("packageName", packageName)

        for ((key, value) in styleExtras) {
            appendExtra(key, value)
        }

        return sb.toString()
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

    /** 控制系统背屏亮度（子屏独立亮度设置，值域 0-255） */
    fun setSubDisplayBrightness(brightness: Int = 46) {
        if (!isShizukuRunning() || !hasPermission()) return
        try {
            execShizukuShell("settings put system sub_display_screen_brightness $brightness")
            Log.d(TAG, "Sub display brightness set to $brightness")
        } catch (e: Exception) {
            Log.e(TAG, "Set sub display brightness failed", e)
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

    /** FBS 自身通知被清除时同步关闭背屏 */
    fun onNotificationRemoved(key: String) {
        Log.d(TAG, "onNotificationRemoved: key=$key → dismissing")
        dismissBackScreen()
    }

    /** 通知清除后同步关闭背屏 */
    fun dismissBackScreen() {
        if (!isShizukuRunning() || !hasPermission()) return
        try {
            // V3 方式: 向背屏 Activity 发送 dismiss Intent (FLAG_ACTIVITY_SINGLE_TOP)
            val cmd = "am start -n ${context.packageName}/.service.BackScreenNotificationActivity" +
                    " -f 0x20000000 --es dismiss \"true\" --user 0"
            execShizukuShell(cmd)
            Log.d(TAG, "dismissBackScreen done")
        } catch (e: Exception) {
            Log.e(TAG, "dismissBackScreen failed", e)
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

    /** Canvas 文本自动换行 */
    private fun wrapText(text: String, paint: Paint, maxWidth: Float): List<String> {
        val lines = mutableListOf<String>()
        val paragraphs = text.split("\n")
        for (para in paragraphs) {
            if (para.isEmpty()) { lines.add(""); continue }
            var cur = 0
            while (cur < para.length) {
                var br = getBreakPos(para, cur, paint, maxWidth)
                lines.add(para.substring(cur, br).trim())
                cur = br
                while (cur < para.length && para[cur] == ' ') cur++
            }
        }
        return lines
    }

    private fun getBreakPos(text: String, start: Int, paint: Paint, maxWidth: Float): Int {
        var pos = start + 1
        while (pos <= text.length && paint.measureText(text, start, pos) <= maxWidth) pos++
        val breakAt = if (pos > text.length) text.length else pos - 1
        val spaceIdx = text.lastIndexOf(' ', breakAt - 1)
        return if (spaceIdx > start) spaceIdx + 1 else if (breakAt > start) breakAt else start + 1
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

                Log.d(TAG, "Shizuku: pm list packages returned ${packages.size} pkgs")

                var failed = 0
                val apps = packages.mapNotNull { pkg ->
                    try {
                        val ai = context.packageManager.getApplicationInfo(pkg, 0)
                        val name = context.packageManager.getApplicationLabel(ai).toString()
                        mapOf("package" to pkg, "name" to name)
                    } catch (_: Exception) {
                        failed++
                        null
                    }
                }.sortedBy { it["name"] }

                Log.d(TAG, "Shizuku: ${apps.size} apps resolved, $failed failed (skipped)")
                callback(apps)
            } catch (e: Exception) {
                Log.e(TAG, "Shizuku getInstalledApps failed", e)
                callback(emptyList())
            }
        }.apply { isDaemon = true }.start()
    }

    /** 通过 Shizuku 启用通知监听组件（HyperOS 上 app 自身无法调用 setComponentEnabledSetting） */
    fun enableNotificationListener() {
        if (!isShizukuRunning() || !hasPermission()) return
        try {
            execShizukuShell("pm enable ${context.packageName}/.service.FBSNotificationListenerService")
            Log.d(TAG, "Notification listener component enabled via Shizuku")
        } catch (e: Exception) {
            Log.e(TAG, "enableNotificationListener failed", e)
        }
    }

    fun destroy() {
        Shizuku.removeBinderReceivedListener(binderReceivedListener)
        Shizuku.removeBinderDeadListener(binderDeadListener)
        Shizuku.removeRequestPermissionResultListener(permissionResultListener)
        wakeLock?.let { if (it.isHeld) it.release() }
        Log.d(TAG, "BackScreenController destroyed")
    }
}
