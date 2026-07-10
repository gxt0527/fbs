package com.example.fbs.service

import android.app.Notification
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import io.flutter.plugin.common.EventChannel

class FBSNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "FBSNotificationListener"
        var eventSink: EventChannel.EventSink? = null
            private set
        var backScreenController: BackScreenController? = null

        /** 鐩戝惉杩囨护 鈥?鐢?Flutter 璁剧疆椤靛悓姝ヨ繃鏉?*/
        @Volatile
        var monitorAll = false
        @Volatile
        var enabledApps = setOf<String>()

        fun setEventSink(sink: EventChannel.EventSink?) { eventSink = sink }

        /** Flutter 璁剧疆椤佃皟鐢細鍚屾鐩戝惉閰嶇疆鍒?native 灞?*/
        fun updateMonitorSettings(monitorAll: Boolean, enabledApps: List<String>) {
            this.monitorAll = monitorAll
            this.enabledApps = enabledApps.toSet()
            Log.d("FBSNotificationListener", "Monitor settings updated: monitorAll=$monitorAll enabled=${enabledApps.size} apps")
        }

        /** 鍒ゆ柇璇ュ寘鍚嶆槸鍚﹀簲琚洃鍚?         *  @param isRegular 鏄惁涓烘櫘閫氭秷鎭紙闈炵劍鐐?闈炲疄鏃跺姩鎬侊級
         *  搴旂敤鍒楄〃濮嬬粓杩囨护锛沵onitorAll 鎺у埗鏄惁鍖呭惈鏅€氭秷鎭?*/
        fun shouldMonitorPackage(packageName: String, isRegular: Boolean): Boolean {
            if (!enabledApps.contains(packageName)) return false
            if (monitorAll) return true
            // 鍏抽棴鍏ㄩ儴鐩戝惉鏃讹紝鏅€氭秷鎭笉鏀捐
            return !isRegular
        }

        fun sendToFlutter(
            title: String, content: String, packageName: String,
            appName: String = "", category: String = "", isFocus: Boolean = false,
            isOngoing: Boolean = false, key: String = "", subText: String = "",
            bigText: String = "",
        ) {
            eventSink?.success(mapOf(
                "title" to title, "content" to content, "packageName" to packageName,
                "appName" to appName, "category" to category,
                "timestamp" to System.currentTimeMillis(),
                "isFocusNotification" to isFocus, "isOngoing" to isOngoing,
                "notificationKey" to key, "subText" to subText, "bigText" to bigText,
            ))
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
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "NotificationListener disconnected")
    }

    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?    //  閫氱煡鏂板 / 鏇存柊锛圚yOS 鐒︾偣閫氱煡閫氳繃鍚屼竴鍥炶皟鏇存柊锛?    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val notif = sbn.notification
        val extras = notif.extras
        val sbnKey = sbn.key

        // 鎻愬彇瀛楁
        val title = extractTitle(extras, notif)
        val content = extractContent(extras, notif)
        val subText = extras?.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
        val bigText = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val category = notif.category ?: ""
        val isFocus = isFocusNotification(notif)
        val isOngoing = sbn.isOngoing

        // 鑾峰彇搴旂敤鍚?        var appName = ""
        try {
            val ai = packageManager.getApplicationInfo(sbn.packageName, 0)
            appName = packageManager.getApplicationLabel(ai).toString()
        } catch (_: Exception) {}

        Log.d(TAG, "NOTIF | key=$sbnKey pkg=${sbn.packageName}($appName) " +
            "focus=$isFocus ongoing=$isOngoing cat=$category " +
            "title=[${title.take(30)}] content=[${content.take(50)}]")

        // 鈫?鑳屽睆鎺у埗鍣?(搴旂敤鍒楄〃濮嬬粓杩囨护锛屽叏閮ㄧ洃鍚帶鍒舵秷鎭被鍨?
        val isRegular = !isFocus && !isOngoing
        if (!shouldMonitorPackage(sbn.packageName, isRegular)) {
            Log.d(TAG, "Skip: ${sbn.packageName} regular=$isRegular")
            return
        }

        // 鈫?Flutter (UI 鏄剧ず鐢?
        sendToFlutter(
            title = title, content = content, packageName = sbn.packageName,
            appName = appName, category = category, isFocus = isFocus,
            isOngoing = isOngoing, key = sbnKey, subText = subText, bigText = bigText,
        )

        // 鈫?鑳屽睆鎺у埗鍣?        backScreenController?.onNotificationAdded(
            key = sbnKey, title = title, content = content,
            packageName = sbn.packageName, appName = appName,
            isFocus = isFocus, isOngoing = isOngoing,
            category = category, subText = subText, bigText = bigText,
        )
    }

    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?    //  閫氱煡绉婚櫎 鈥?鍚屾娓呴櫎鑳屽睆
    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        if (sbn == null) return
        val key = sbn.key
        Log.d(TAG, "NOTIF removed: key=$key pkg=${sbn.packageName}")
        backScreenController?.onNotificationRemoved(key)
    }

    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?    //  杞 鈥?鐢ㄤ簬妫€娴嬭秴鏃朵涪澶辩殑鐒︾偣閫氱煡鍙樺寲
    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?    override fun onNotificationRankingUpdate(rankingMap: RankingMap?) {
        super.onNotificationRankingUpdate(rankingMap)
        // 涓嶄綔澶勭悊锛屼緷璧?onNotificationPosted / onNotificationRemoved 椹卞姩
    }

    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?    //  杈呭姪: 娲昏穬閫氱煡 dump + 鎻愬彇
    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?
    private fun dumpActiveNotifications() {
        try {
            val active = activeNotifications
            Log.d(TAG, "=== Active count: ${active?.size ?: 0} ===")
            active?.take(10)?.forEachIndexed { i, sbn ->
                val e = sbn.notification.extras
                val t = e?.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
                val c = e?.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
                Log.d(TAG, "  [$i] key=${sbn.key} pkg=${sbn.packageName} cat=${sbn.notification.category} title=[$t] text=[${c.take(40)}]")
            }
        } catch (e: Exception) {
            Log.e(TAG, "dumpActive error", e)
        }
    }

    private fun extractTitle(extras: Bundle?, notif: Notification): String {
        extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.let { if (it.isNotEmpty()) return it }
        extras?.getCharSequence("android.title.big")?.toString()?.let { if (it.isNotEmpty()) return it }
        return ""
    }

    private fun extractContent(extras: Bundle?, notif: Notification): String {
        extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.let { if (it.isNotEmpty()) return it }
        extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.let { if (it.isNotEmpty()) return it }
        extras?.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.let { if (it.isNotEmpty()) return it }
        extras?.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()?.let { if (it.isNotEmpty()) return it }
        extras?.getCharSequence(Notification.EXTRA_INFO_TEXT)?.toString()?.let { if (it.isNotEmpty()) return it }
        // MediaStyle
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val token = notif.extras?.getParcelable<android.media.session.MediaSession.Token>(Notification.EXTRA_MEDIA_SESSION)
                if (token != null) {
                    val mc = android.media.session.MediaController(this, token)
                    val meta = mc.metadata
                    val artist = meta?.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST) ?: ""
                    val album = meta?.getString(android.media.MediaMetadata.METADATA_KEY_ALBUM) ?: ""
                    if (artist.isNotEmpty()) return "$artist - $album"
                }
            }
        } catch (_: Exception) {}
        // InboxStyle
        try {
            val lines = extras?.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            if (lines != null && lines.isNotEmpty()) return lines.joinToString("\n") { it.toString() }
        } catch (_: Exception) {}
        // MessagingStyle
        try {
            val msgs = extras?.getParcelableArray(Notification.EXTRA_MESSAGES)
            if (msgs != null && msgs.isNotEmpty()) {
                val last = msgs.lastOrNull()
                if (last is Bundle) {
                    val msg = last.getCharSequence("text")?.toString() ?: ""
                    if (msg.isNotEmpty()) return msg
                }
            }
        } catch (_: Exception) {}
        return ""
    }

    private fun isFocusNotification(notif: Notification): Boolean {
        if (notif.fullScreenIntent != null) return true
        val cat = notif.category ?: return false
        return cat == Notification.CATEGORY_CALL
            || cat == Notification.CATEGORY_ALARM
            || cat == Notification.CATEGORY_REMINDER
            || cat == Notification.CATEGORY_EVENT
    }
}
