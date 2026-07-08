package com.example.fbs.service

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import android.view.Display
import io.flutter.plugin.common.EventChannel

enum class NotifEventType { POSTED, REMOVED }

data class NotifRemovedInfo(
    val notificationId: Int,
    val packageName: String,
    val notificationKey: String,
    val reason: String
)

/** 镜像通知条目 (供 ListenerService 维护, BackScreenNotificationActivity 读取) */
data class NotifItem(
    val key: String,           // StatusBarNotification.key
    val packageName: String,
    val appName: String,
    val title: String,
    val content: String,
    val subText: String,
    val isFocus: Boolean,
    val isClearable: Boolean,
    val postTime: Long
)

class FBSNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "FBSNotificationListener"
        private const val POLL_INTERVAL_MS = 5000L
        private const val PREFS_NAME = "fbs_mirror_prefs"
        private const val KEY_MIRROR_ENABLED = "mirror_enabled"

        @Volatile
        var instance: FBSNotificationListenerService? = null
            private set

        /** 镜像开关 — 从 SharedPreferences 读写 */
        @Volatile
        var mirrorEnabled: Boolean = true
            private set

        fun updateMirrorEnabled(context: android.content.Context, enabled: Boolean) {
            mirrorEnabled = enabled
            context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_MIRROR_ENABLED, enabled).apply()
            Log.d(TAG, "Mirror enabled=$enabled")
        }

        var eventSink: EventChannel.EventSink? = null
            private set

        fun setEventSink(sink: EventChannel.EventSink?) {
            eventSink = sink
        }

        fun requestRebind(context: android.content.Context) {
            try {
                val cn = android.content.ComponentName(
                    context,
                    FBSNotificationListenerService::class.java
                )
                requestRebind(cn)
                Log.d(TAG, "requestRebind called for $cn")
            } catch (e: Exception) {
                Log.e(TAG, "requestRebind failed", e)
            }
        }

        fun sendNotificationToFlutter(
            title: String,
            content: String,
            packageName: String,
            appName: String = "",
            category: String = "",
            isFocusNotification: Boolean = false,
            isOngoing: Boolean = false,
            notificationId: Int = 0,
            groupKey: String = "",
            channelId: String = "",
            subText: String = "",
            bigText: String = "",
            notificationKey: String = ""
        ) {
            val data = mapOf(
                "title" to title,
                "content" to content,
                "packageName" to packageName,
                "appName" to appName,
                "category" to category,
                "timestamp" to System.currentTimeMillis(),
                "isFocusNotification" to isFocusNotification,
                "isOngoing" to isOngoing,
                "notificationId" to notificationId,
                "groupKey" to groupKey,
                "channelId" to channelId,
                "subText" to subText,
                "bigText" to bigText,
                "notificationKey" to notificationKey
            )
            eventSink?.success(data)
        }

        fun sendRemovedToFlutter(info: NotifRemovedInfo) {
            val data = mapOf(
                "type" to "removed",
                "notificationId" to info.notificationId,
                "packageName" to info.packageName,
                "notificationKey" to info.notificationKey,
                "reason" to info.reason
            )
            eventSink?.success(data)
        }
    }

    private val seenKeys = mutableSetOf<String>()
    /** 当前已镜像的通知 map: key → NotifItem */
    private val mirroredItems = java.util.concurrent.ConcurrentHashMap<String, NotifItem>()

    private val pollHandler = Handler(Looper.myLooper() ?: Looper.getMainLooper())
    private val pollRunnable = object : Runnable {
        override fun run() {
            pollActiveNotifications()
            pollHandler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent): IBinder? {
        Log.d(TAG, "onBind")
        return super.onBind(intent)
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        val prefs = getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
        mirrorEnabled = prefs.getBoolean(KEY_MIRROR_ENABLED, true)
        Log.d(TAG, "onCreate — mirrorEnabled=$mirrorEnabled")
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
        Log.d(TAG, "onDestroy")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "========== NotificationListener connected ==========")
        dumpActiveNotifications()
        seenKeys.clear()
        mirroredItems.clear()
        pollActiveNotifications()
        pollHandler.postDelayed(pollRunnable, POLL_INTERVAL_MS)
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "NotificationListener disconnected")
        pollHandler.removeCallbacks(pollRunnable)
        mirroredItems.clear()
    }

    private fun pollActiveNotifications() {
        try {
            val activeNotifications = activeNotifications ?: return
            Log.d(TAG, "=== Poll active: ${activeNotifications.size} active, ${seenKeys.size} seen ===")

            activeNotifications.forEach { sbn ->
                val key = sbn.key
                if (key in seenKeys) return@forEach
                seenKeys.add(key)
                processAndSendNotification(sbn, "poll")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error polling active notifications", e)
        }
    }

    private fun dumpActiveNotifications() {
        try {
            val activeNotifications = activeNotifications
            Log.d(TAG, "=== Dump active notifications count: ${activeNotifications?.size ?: 0} ===")
            activeNotifications?.take(20)?.forEachIndexed { index, sbn ->
                val extras = sbn.notification.extras
                val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
                val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
                val summaryText = extras?.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString() ?: ""
                val subText = extras?.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
                val bigText = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
                val template = extras?.getString(Notification.EXTRA_TEMPLATE) ?: ""

                Log.d(TAG, "  [$index] pkg=${sbn.packageName} key=${sbn.key} " +
                    "id=${sbn.id} cat=${sbn.notification.category} " +
                    "ongoing=${sbn.isOngoing} clearable=${sbn.isClearable} " +
                    "group=${sbn.groupKey} flags=${sbn.notification.flags} " +
                    "title=[$title] text=[$text] sum=[$summaryText] sub=[$subText] big=[$bigText] template=[$template]")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error dumping active notifications", e)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        seenKeys.add(sbn.key)
        processAndSendNotification(sbn, "posted")
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        if (sbn != null) {
            val reason = when {
                sbn.isClearable -> "USER_OR_APP"
                else -> "ONGOING_REMOVED"
            }
            Log.d(TAG, "NOTIF removed: pkg=${sbn.packageName} key=${sbn.key} id=${sbn.id} reason=$reason")
            sendRemovedToFlutter(
                NotifRemovedInfo(
                    notificationId = sbn.id,
                    packageName = sbn.packageName,
                    notificationKey = sbn.key,
                    reason = reason
                )
            )
            // 镜像: 从活跃列表移除，刷新或消除背屏
            val removed = mirroredItems.remove(sbn.key)
            if (removed != null) {
                Log.d(TAG, "Mirror removed: key=${sbn.key}, remaining=${mirroredItems.size}")
                refreshOrDismissMirror()
            }
        }
    }

    override fun onNotificationRankingUpdate(rankingMap: RankingMap?) {
        super.onNotificationRankingUpdate(rankingMap)
        Log.d(TAG, "onNotificationRankingUpdate")
    }

    private fun processAndSendNotification(sbn: StatusBarNotification, source: String) {
        val notification = sbn.notification
        val extras = notification.extras

        val title = extractTitle(extras, notification)
        val content = extractContent(extras, notification)

        val subText = extras?.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
        val bigText = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val summaryText = extras?.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString() ?: ""
        val template = extras?.getString(Notification.EXTRA_TEMPLATE) ?: ""
        val category = notification.category ?: ""
        val groupKey = sbn.groupKey ?: ""
        val channelId = notification.channelId ?: ""

        var appName = ""
        try {
            val ai = packageManager.getApplicationInfo(sbn.packageName, 0)
            appName = packageManager.getApplicationLabel(ai).toString()
        } catch (_: Exception) {}

        Log.d(TAG, "NOTIF $source | pkg=${sbn.packageName}($appName) key=${sbn.key} " +
            "id=${sbn.id} cat=$category ongoing=${sbn.isOngoing} " +
            "clearable=${sbn.isClearable} group=$groupKey " +
            "flags=0x${notification.flags.toString(16)} priority=${notification.priority} " +
            "channel=$channelId style=${notification.javaClass.simpleName} template=$template")
        Log.d(TAG, "NOTIF title=[$title] content=[$content] sub=[$subText] big=[$bigText] sum=[$summaryText]")

        extras?.keySet()?.take(15)?.forEach { key ->
            val value = extras[key]
            val valueStr = when (value) {
                is String -> value.take(80)
                is CharSequence -> value.toString().take(80)
                else -> value?.javaClass?.simpleName ?: "null"
            }
            Log.d(TAG, "  extras[$key] = $valueStr")
        }

        val isFocus = isFocusNotification(notification)

        val fullContent = when {
            bigText.isNotEmpty() && content.isNotEmpty() -> "$content\n$bigText"
            content.isNotEmpty() -> content
            subText.isNotEmpty() -> subText
            summaryText.isNotEmpty() -> summaryText
            else -> ""
        }

        sendNotificationToFlutter(
            title = title,
            content = fullContent,
            packageName = sbn.packageName,
            appName = appName,
            category = category,
            isFocusNotification = isFocus,
            isOngoing = sbn.isOngoing,
            notificationId = sbn.id,
            groupKey = groupKey,
            channelId = channelId,
            subText = subText,
            bigText = bigText,
            notificationKey = sbn.key
        )

        // ── 镜像: 如果启用且不是自身通知, 加入背屏列表 ──
        feedMirror(sbn, appName, title, content, subText, isFocus)
    }

    private fun extractTitle(extras: Bundle?, notification: Notification): String {
        extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.let {
            if (it.isNotEmpty()) return it
        }
        extras?.getCharSequence("android.title.big")?.toString()?.let {
            if (it.isNotEmpty()) return it
        }
        if (notification.contentView != null) {
            Log.d(TAG, "  [title fallback] contentView class: ${notification.contentView.javaClass.name}")
        }
        extras?.getString(Notification.EXTRA_TEMPLATE)?.let {
            Log.d(TAG, "  [title fallback] template: $it")
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val mediaSessionToken = notification.extras
                    ?.getParcelable<android.media.session.MediaSession.Token>(
                        Notification.EXTRA_MEDIA_SESSION
                    )
                if (mediaSessionToken != null) {
                    val mediaController = android.media.session.MediaController(this, mediaSessionToken)
                    val metadata = mediaController.metadata
                    val mediaTitle = metadata?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE) ?: ""
                    Log.d(TAG, "  [media style] title=$mediaTitle")
                    if (mediaTitle.isNotEmpty()) return mediaTitle
                }
            }
        } catch (e: Exception) {
            Log.d(TAG, "  [media style] extract failed: ${e.message}")
        }
        return ""
    }

    private fun extractContent(extras: Bundle?, notification: Notification): String {
        extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.let {
            if (it.isNotEmpty()) return it
        }
        extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.let {
            if (it.isNotEmpty()) return it
        }
        extras?.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.let {
            if (it.isNotEmpty()) return it
        }
        extras?.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()?.let {
            if (it.isNotEmpty()) return it
        }
        extras?.getCharSequence(Notification.EXTRA_INFO_TEXT)?.toString()?.let {
            if (it.isNotEmpty()) return it
        }
        extras?.getCharSequence("android.text")?.toString()?.let {
            if (it.isNotEmpty()) return it
        }
        extras?.getCharSequence("android.title")?.toString()?.let {
            if (it.isNotEmpty()) return it
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val mediaToken = notification.extras
                    ?.getParcelable<android.media.session.MediaSession.Token>(
                        Notification.EXTRA_MEDIA_SESSION
                    )
                if (mediaToken != null) {
                    val mc = android.media.session.MediaController(this, mediaToken)
                    val artist = mc.metadata?.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST) ?: ""
                    val album = mc.metadata?.getString(android.media.MediaMetadata.METADATA_KEY_ALBUM) ?: ""
                    if (artist.isNotEmpty()) return "$artist - $album"
                }
            }
        } catch (_: Exception) {}
        try {
            val lines = extras?.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            if (lines != null && lines.isNotEmpty()) {
                return lines.joinToString("\n") { it.toString() }
            }
        } catch (_: Exception) {}
        try {
            val messages = extras?.getParcelableArray(Notification.EXTRA_MESSAGES)
            if (messages != null && messages.isNotEmpty()) {
                val lastMsg = messages.lastOrNull()
                if (lastMsg is Bundle) {
                    val msgText = lastMsg.getCharSequence("text")?.toString() ?: ""
                    if (msgText.isNotEmpty()) return msgText
                }
            }
        } catch (_: Exception) {}
        return ""
    }

    private fun isFocusNotification(notification: Notification): Boolean {
        if (notification.fullScreenIntent != null) {
            Log.d(TAG, "Focus: fullScreenIntent")
            return true
        }
        val category = notification.category
        if (category != null) {
            when (category) {
                Notification.CATEGORY_CALL,
                Notification.CATEGORY_ALARM,
                Notification.CATEGORY_REMINDER,
                Notification.CATEGORY_EVENT -> {
                    Log.d(TAG, "Focus: category=$category")
                    return true
                }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                val channel = manager.getNotificationChannel(notification.channelId)
                if (channel != null && channel.importance >= NotificationManager.IMPORTANCE_HIGH) {
                    Log.d(TAG, "Focus: channel importance=${channel.importance}")
                    return true
                }
            } catch (_: Exception) {}
        }
        if (notification.priority >= Notification.PRIORITY_HIGH) {
            Log.d(TAG, "Focus: priority=${notification.priority}")
            return true
        }
        return false
    }

    // ═══════════════════════════════════════════
    //  背屏镜像 (mirror) 方法
    // ═══════════════════════════════════════════

    /** 将一条通知加入镜像列表并推送到背屏 */
    private fun feedMirror(sbn: StatusBarNotification, appName: String, title: String,
                           content: String, subText: String, isFocus: Boolean) {
        if (!mirrorEnabled) return
        // 跳过自身通知避免循环
        if (sbn.packageName == packageName) return

        val item = NotifItem(
            key = sbn.key,
            packageName = sbn.packageName,
            appName = appName,
            title = if (title.isNotEmpty()) title else appName,
            content = content,
            subText = subText,
            isFocus = isFocus,
            isClearable = sbn.isClearable,
            postTime = sbn.postTime
        )
        mirroredItems[sbn.key] = item
        Log.d(TAG, "Mirror add: key=${sbn.key} pkg=${sbn.packageName} title=[${item.title}] total=${mirroredItems.size}")
        pushMirror()
    }

    /** 推送当前镜像列表到背屏 (launch 或 broadcast refresh) */
    private fun pushMirror() {
        if (mirroredItems.isEmpty()) return
        val json = buildNotificationJson()
        if (json.isBlank()) return

        val styleExtras = readStylePrefs()
        val needsWake = checkDisplayOneNeedsWake()

        if (BackScreenController.backScreenActivityAlive) {
            // Activity 已在 display 1 → 发送进程内广播刷新
            Log.d(TAG, "Mirror push: backScreen alive, sending refresh broadcast (${mirroredItems.size} items)")
            val intent = Intent(BackScreenController.ACTION_MIRROR_REFRESH)
            intent.setPackage(packageName)
            intent.putExtra("notificationsJson", json)
            for ((k, v) in styleExtras) {
                intent.putExtra(k, v)
            }
            sendBroadcast(intent)
        } else {
            // 背屏 Activity 不在 → 通过 Shizuku shell 启动
            if (!BackScreenController.isShizukuReady() || !BackScreenController.hasShizukuPermission()) {
                Log.d(TAG, "Mirror push: Shizuku not ready, skip launch")
                return
            }
            val launchCmd = "input keyevent KEYCODE_WAKEUP && " +
                BackScreenController.buildMirrorLaunchCommand(this, json, styleExtras, needsWake)
            Log.d(TAG, "Mirror push: launching activity (${mirroredItems.size} items)")
            Thread {
                try {
                    // 1. 唤醒 + am start
                    val result = BackScreenController.execShell(launchCmd)
                    Log.d(TAG, "Mirror launch result: ${result.take(200)}")
                    Thread.sleep(300)
                    // 2. 移屏到 display 1 + 杀官方背屏（一条命令原子执行，旧版已验证）
                    val taskId = findMirrorTaskId()
                    if (taskId > 0) {
                        BackScreenController.execShell(
                            "service call activity_task 50 i32 $taskId i32 1; " +
                            "am force-stop com.xiaomi.subscreencenter"
                        )
                        Log.d(TAG, "Mirror: moved task $taskId → display 1 + killed subscreencenter")
                    } else {
                        Log.w(TAG, "Mirror: no taskId found, attempting force-stop only")
                        BackScreenController.execShell("am force-stop com.xiaomi.subscreencenter")
                    }
                    // 3. 设置 90s 超时防止 display 1 灭屏
                    BackScreenController.execShell("settings put system screen_off_timeout 90000")
                    Log.d(TAG, "Mirror: screen_off_timeout set to 90000")
                } catch (e: Exception) {
                    Log.e(TAG, "Mirror launch failed", e)
                }
            }.apply { isDaemon = true; start() }
        }
    }

    /** 镜像列表变化后: 发送刷新或消除 */
    private fun refreshOrDismissMirror() {
        if (mirroredItems.isEmpty()) {
            Log.d(TAG, "Mirror: list empty, dismissing back screen")
            if (BackScreenController.backScreenActivityAlive) {
                val intent = Intent(BackScreenController.ACTION_MIRROR_DISMISS)
                intent.setPackage(packageName)
                sendBroadcast(intent)
            } else {
                // Activity 已不在, 不需要 dismiss
                Log.d(TAG, "Mirror: Activity already gone, nothing to dismiss")
            }
        } else {
            pushMirror()
        }
    }

    /** 清除所有镜像通知 (供 Flutter 层调用 "清除背屏") */
    fun clearAllMirrored() {
        Log.d(TAG, "Clear all mirrored (${mirroredItems.size} items)")
        val keys = mirroredItems.keys.toList()
        mirroredItems.clear()
        for (key in keys) {
            try { cancelNotification(key) } catch (_: Exception) {}
        }
        // cancelNotification 会触发 onNotificationRemoved → refreshOrDismissMirror → dismiss
    }

    /** 构建镜像通知 JSON 数组字符串 */
    private fun buildNotificationJson(): String {
        val arr = org.json.JSONArray()
        for (item in mirroredItems.values) {
            val obj = org.json.JSONObject()
            obj.put("key", item.key)
            obj.put("title", item.title)
            obj.put("subText", item.subText)
            obj.put("content", item.content)
            obj.put("appName", item.appName)
            obj.put("packageName", item.packageName)
            obj.put("category", if (item.isFocus) "focus" else "")
            obj.put("isSticky", true)
            obj.put("isFocus", item.isFocus)
            obj.put("isClearable", item.isClearable)
            arr.put(obj)
        }
        return arr.toString()
    }

    /** 读取 SharedPreferences 中的样式参数 (与 NotificationStyle 相同 keys) */
    private fun readStylePrefs(): Map<String, String> {
        val prefs = getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
        val all = prefs.all
        fun readStr(key: String): String? = all["flutter.$key"]?.toString()
        fun readDouble(key: String, default: Double): Double {
            val v = all["flutter.$key"] ?: return default
            return when (v) {
                is Number -> v.toDouble()
                is String -> v.toDoubleOrNull() ?: default
                else -> default
            }
        }
        fun readInt(key: String, default: Int): Int {
            val v = all["flutter.$key"] ?: return default
            return when (v) {
                is Number -> v.toInt()
                is String -> v.toLongOrNull()?.toInt() ?: default
                else -> default
            }
        }
        fun readBool(key: String, default: Boolean): Boolean {
            val v = all["flutter.$key"] ?: return default
            return when (v) {
                is Boolean -> v
                is String -> v.equals("true", ignoreCase = true)
                else -> default
            }
        }

        val map = mutableMapOf<String, String>()
        map["titleFontSize"] = String.format("%.1f", readDouble("style_titleFontSize", 28.0))
        map["subtitleFontSize"] = String.format("%.1f", readDouble("style_subtitleFontSize", 20.0))
        map["contentFontSize"] = String.format("%.1f", readDouble("style_contentFontSize", 16.0))
        map["titleColor"] = readInt("style_titleColor", 0xFFFFFFFF.toInt()).toUInt().toString(16).padStart(8, '0')
        map["subtitleColor"] = readInt("style_subtitleColor", 0xFFB0B0B0.toInt()).toUInt().toString(16).padStart(8, '0')
        map["contentColor"] = readInt("style_contentColor", 0xFFE0E0E0.toInt()).toUInt().toString(16).padStart(8, '0')
        map["backgroundColor"] = readInt("style_backgroundColor", 0xFF1A1A2E.toInt()).toUInt().toString(16).padStart(8, '0')
        map["showAppIcon"] = readBool("style_showAppIcon", true).toString()
        map["showTimestamp"] = readBool("style_showTimestamp", true).toString()
        map["cameraAvoidanceEnabled"] = readBool("style_cameraAvoidance", false).toString()
        map["horizontalOffset"] = "85"
        map["padding"] = readDouble("style_padding", 24.0).toInt().toString()
        map["spacing"] = readDouble("style_spacing", 12.0).toInt().toString()
        return map
    }

    /** 检查 display 1 是否需要唤醒 */
    private fun checkDisplayOneNeedsWake(): Boolean {
        return try {
            val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            val backDisplay = dm.getDisplay(1)
            val state = backDisplay?.state ?: Display.STATE_UNKNOWN
            state == Display.STATE_OFF || state == Display.STATE_UNKNOWN
        } catch (_: Exception) { true }
    }

    /** 查找镜像 Activity 的 taskId */
    private fun findMirrorTaskId(): Int {
        return try {
            val result = BackScreenController.execShell("am stack list")
            for (line in result.lines()) {
                if (line.contains("BackScreenNotificationActivity") && line.contains("taskId=")) {
                    return Regex("taskId=(\\d+)").find(line)?.groupValues?.get(1)?.toIntOrNull() ?: -1
                }
            }
            -1
        } catch (_: Exception) { -1 }
    }
}
