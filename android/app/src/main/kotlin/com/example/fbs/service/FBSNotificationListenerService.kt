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
import java.util.concurrent.ConcurrentHashMap

class FBSNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "FBSNotificationListener"
        var eventSink: EventChannel.EventSink? = null
            private set
        var backScreenController: BackScreenController? = null

        /** 监听过滤 — 由 Flutter 设置页同步过来 */
        @Volatile
        var monitorAll = false
        @Volatile
        var enabledApps = setOf<String>()

        /** 应用名缓存 — 避免每个通知都调用 packageManager.getApplicationInfo() */
        private val appNameCache = ConcurrentHashMap<String, String>()

        /** 通知频率统计 — 用于诊断卡顿 */
        private var notifCount = 0
        private var windowStart = System.currentTimeMillis()
        private const val FREQ_WINDOW_MS = 10_000L

        fun setEventSink(sink: EventChannel.EventSink?) { eventSink = sink }

        /** Flutter 设置页调用：同步监听配置到 native 层 */
        fun updateMonitorSettings(monitorAll: Boolean, enabledApps: List<String>) {
            this.monitorAll = monitorAll
            this.enabledApps = enabledApps.toSet()
            Log.d("FBSNotificationListener", "Monitor settings updated: monitorAll=$monitorAll enabled=${enabledApps.size} apps")
        }

        /** 判断该包名是否应被监听
         *  @param isRegular 是否为普通消息（非焦点/非实时动态）
         *  应用列表始终过滤；monitorAll 控制是否包含普通消息 */
        fun shouldMonitorPackage(packageName: String, isRegular: Boolean): Boolean {
            if (!enabledApps.contains(packageName)) return false
            if (monitorAll) return true
            // 关闭全部监听时，普通消息不放行
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

        /** 获取缓存的应用名，避免重复 PM 调用 */
        fun getCachedAppName(packageName: String, provider: android.content.pm.PackageManager): String {
            appNameCache[packageName]?.let { return it }
            return try {
                val ai = provider.getApplicationInfo(packageName, 0)
                val name = provider.getApplicationLabel(ai).toString()
                appNameCache[packageName] = name
                name
            } catch (_: Exception) { "" }
        }

        /** 记录通知频率，每 FREQ_WINDOW_MS 输出一次统计 */
        fun logFrequency() {
            notifCount++
            val now = System.currentTimeMillis()
            if (now - windowStart >= FREQ_WINDOW_MS) {
                val rate = notifCount * 1000.0 / (now - windowStart)
                Log.w(TAG, ">>> FREQ: $notifCount notifs in ${now - windowStart}ms (${String.format("%.1f", rate)} notif/s)")
                notifCount = 0
                windowStart = now
            }
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

    // ═══════════════════════════════════════════
    //  通知新增 / 更新（HyOS 焦点通知通过同一回调更新）
    // ═══════════════════════════════════════════
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        logFrequency()

        val notif = sbn.notification
        val extras = notif.extras
        val sbnKey = sbn.key

        // 提取字段
        val title = extractTitle(extras, notif)
        val content = extractContent(extras, notif)
        val subText = extras?.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
        val bigText = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val category = notif.category ?: ""
        val isFocus = isFocusNotification(notif)
        val isOngoing = sbn.isOngoing

        // 获取应用名（使用缓存）
        val appName = getCachedAppName(sbn.packageName, packageManager)

        Log.d(TAG, "NOTIF | key=$sbnKey pkg=${sbn.packageName}($appName) " +
            "focus=$isFocus ongoing=$isOngoing cat=$category " +
            "title=[${title.take(30)}] content=[${content.take(50)}]")

        // → 背屏控制器 (应用列表始终过滤，全部监听控制消息类型)
        val isRegular = !isFocus && !isOngoing
        if (!shouldMonitorPackage(sbn.packageName, isRegular)) {
            Log.d(TAG, "Skip: ${sbn.packageName} regular=$isRegular")
            return
        }

        // → Flutter (UI 显示 + 背屏转发)
        sendToFlutter(
            title = title, content = content, packageName = sbn.packageName,
            appName = appName, category = category, isFocus = isFocus,
            isOngoing = isOngoing, key = sbnKey, subText = subText, bigText = bigText,
        )

        // 注意: 不再直接调用 backScreenController?.onNotificationAdded()
        // 背屏转发由 Flutter 层 _forwardToBackScreenWithDedup → displayOnBackScreenV2 处理
        // 避免双重 am start 导致通知渲染到正面屏幕 (display 0)
    }

    // ═══════════════════════════════════════════
    //  通知移除 — 同步清除背屏
    // ═══════════════════════════════════════════
    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        if (sbn == null) return
        val key = sbn.key
        Log.d(TAG, "NOTIF removed: key=$key pkg=${sbn.packageName}")
        backScreenController?.onNotificationRemoved(key)
    }

    // ═══════════════════════════════════════════
    //  轮询 — 用于检测超时丢失的焦点通知变化
    // ═══════════════════════════════════════════
    override fun onNotificationRankingUpdate(rankingMap: RankingMap?) {
        super.onNotificationRankingUpdate(rankingMap)
        // 不作处理，依赖 onNotificationPosted / onNotificationRemoved 驱动
    }

    // ═══════════════════════════════════════════
    //  辅助: 活跃通知 dump + 提取
    // ═══════════════════════════════════════════

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
