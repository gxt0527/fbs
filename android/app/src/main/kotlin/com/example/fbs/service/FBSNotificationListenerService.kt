package com.example.fbs.service

import android.app.Notification
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.example.fbs.hyperisland.FocusForwarder
import io.flutter.plugin.common.EventChannel

enum class NotifEventType { POSTED, REMOVED }

data class NotifRemovedInfo(
    val notificationId: Int,
    val packageName: String,
    val notificationKey: String,
    val reason: String
)

class FBSNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "FBSNotificationListener"
        private const val POLL_INTERVAL_MS = 5000L
        private const val MAX_SEEN_KEYS = 500
        var eventSink: EventChannel.EventSink? = null
            private set
        @Volatile
        var backScreenController: com.example.fbs.service.BackScreenController? = null

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

    /// 添加 key 并自动清理最旧的条目
    private fun addSeenKey(key: String) {
        if (seenKeys.size >= MAX_SEEN_KEYS) {
            // 清空一半最旧条目（LinkedHashSet 保持插入顺序）
            val toRemove = seenKeys.take(seenKeys.size / 2)
            seenKeys.removeAll(toRemove.toSet())
        }
        seenKeys.add(key)
    }

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

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "========== NotificationListener connected ==========")
        dumpActiveNotifications()
        seenKeys.clear()
        pollActiveNotifications()
        pollHandler.postDelayed(pollRunnable, POLL_INTERVAL_MS)
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "NotificationListener disconnected")
        pollHandler.removeCallbacks(pollRunnable)
    }

    private fun pollActiveNotifications() {
        try {
            val activeNotifications = activeNotifications ?: return
            Log.d(TAG, "=== Poll active: ${activeNotifications.size} active, ${seenKeys.size} seen ===")

            activeNotifications.forEach { sbn ->
                val key = sbn.key
                if (key in seenKeys) return@forEach
                addSeenKey(key)
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

        // 🔍 捕获第三方超级岛的通知 extras（用于分析按钮/动画格式）
        if (sbn.packageName == "com.binge.misuperisland") {
            Log.w(TAG, "=== 3RD PARTY NOTIFICATION ===")
            Log.w(TAG, "ID=${sbn.id} key=${sbn.key} chan=${sbn.notification.channelId}")
            val extras = sbn.notification.extras
            if (extras != null) {
                Log.w(TAG, "Extras keys: ${extras.keySet().joinToString(", ")}")
                for (key in extras.keySet()) {
                    val value = extras.get(key)
                    if (value is Bundle) {
                        Log.w(TAG, "  Bundle[$key]: keys=${value.keySet()}")
                        for (k2 in value.keySet()) {
                            Log.w(TAG, "    Bundle[$key][$k2]=${value.get(k2)}")
                        }
                    } else if (value is String && value.length < 2000) {
                        Log.w(TAG, "  String[$key]=$value")
                    } else {
                        Log.w(TAG, "  $key=${value?.toString()?.take(500)}")
                    }
                }
            }
            Log.w(TAG, "=== END 3RD PARTY ===")
        }

        addSeenKey(sbn.key)
        processAndSendNotification(sbn, "posted")
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        if (sbn == null) return
        if (sbn.packageName == "com.example.fbs" &&
            (sbn.id == SuperIslandHelper.NOTIFICATION_ID || FocusForwarder.isActiveId(sbn.id))
        ) {
            Log.d(TAG, "FBS notification removed (id=${sbn.id}), dismissing back screen")
            FocusForwarder.removeActiveId(sbn.id)
            // 通知 Flutter 层同步清除
            sendRemovedToFlutter(
                NotifRemovedInfo(
                    notificationId = sbn.id,
                    packageName = sbn.packageName,
                    notificationKey = sbn.key,
                    reason = "notification_removed"
                )
            )
            // 方式1: 直接 finish Activity（同一进程，最可靠）
            val act = com.example.fbs.service.BackScreenNotificationActivity.instance
            if (act != null && !act.isFinishing) {
                Log.d(TAG, "Direct finish() Activity")
                act.finish()
                return
            }
            // 方式2: Shizuku am start 发送 dismiss Intent（Activity 存活但引用丢失）
            backScreenController?.onNotificationRemoved(sbn.key)
        } else {
            Log.d(TAG, "NOTIF removed: key=${sbn.key} pkg=${sbn.packageName} id=${sbn.id} (ignored)")
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
}
