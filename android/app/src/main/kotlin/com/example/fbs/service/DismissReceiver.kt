package com.example.fbs.service

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 超级岛通知的"关闭"按钮处理 — 取消通知。
 * 在 Notification.Builder 中通过 addAction 的 PendingIntent.getBroadcast 触发。
 */
class DismissReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(SuperIslandHelper.NOTIFICATION_ID)
        SuperIslandHelper.islandDismissed = true
        Log.d("DismissReceiver", "Island notification dismissed by user action")

        // 恢复 XMSF 网络，让官方灵动岛恢复正常
        try {
            BackScreenController.execShell("cmd connectivity set-package-networking-enabled true com.xiaomi.xmsf")
            Log.i("DismissReceiver", "XMSF networking re-enabled")
        } catch (e: Exception) {
            Log.w("DismissReceiver", "Failed to re-enable XMSF networking", e)
        }
    }
}
