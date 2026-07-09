package com.example.fbs.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * 小米超级岛通知 — 核心原理:
 *   notification.extras.putBoolean("android.requestPromotedOngoing", true)
 * 系统检测到此 extras 后自动添加 FLAG_PROMOTED_ONGOING (262144) 标志。
 */
object SuperIslandHelper {

    private const val TAG = "SuperIsland"
    private const val CHANNEL_ID = "fbs_island_v2"
    private const val CHANNEL_NAME = "FBS 超级岛"
    private const val NOTIFICATION_ID = 9001

    fun getDiagnostics(context: Context): String {
        val api = Build.VERSION.SDK_INT
        val permOk = hasPromotedPermission(context)
        return "API=$api promoted=$permOk"
    }

    fun hasPromotedPermission(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= 34) {
            context.checkSelfPermission("android.permission.POST_PROMOTED_NOTIFICATIONS") ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        } else false
    }

    fun openFocusNotificationSettings(context: Context) {
        try {
            context.startActivity(
                Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                    setClassName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.permissions.PermissionsEditorActivity"
                    )
                    putExtra("extra_pkgname", context.packageName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
        } catch (_: Exception) {
            try {
                context.startActivity(
                    Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = android.net.Uri.parse("package:${context.packageName}")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
            } catch (_: Exception) {}
        }
    }

    fun sendNotification(context: Context, title: String, content: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "应用提醒服务"
                    setShowBadge(true)
                    enableVibration(false)
                    setSound(null, null)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
            )
        }

        val pi = PendingIntent.getActivity(
            context, 0,
            context.packageManager.getLaunchIntentForPackage(context.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }).apply {
            setContentTitle(title)
            setContentText(content)
            setSmallIcon(android.R.drawable.ic_dialog_info)
            setContentIntent(pi)
            setAutoCancel(false)
            setOngoing(true)
            setCategory(Notification.CATEGORY_STATUS)
            setVisibility(Notification.VISIBILITY_PUBLIC)
        }

        val notification = builder.build()
        notification.extras.putBoolean("android.requestPromotedOngoing", true)
        nm.notify(NOTIFICATION_ID, notification)
        Log.i(TAG, "Super Island notification: $title")
    }

    fun cancelNotification(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(NOTIFICATION_ID)
    }
}
