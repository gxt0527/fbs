package com.example.fbs.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.github.d4viddf.hyperisland_kit.HyperIslandNotification
import io.github.d4viddf.hyperisland_kit.HyperPicture

/**
 * HyperIsland-ToolKit 0.4.3 minimal Getting Started implementation.
 * Reference: https://hyperisland.d4viddf.com/docs/getting-started/
 */
object SuperIslandHelper {

    private const val TAG = "SuperIsland"
    private const val CHANNEL_ID = "fbs_island_v1"
    private const val CHANNEL_NAME = "FBS 超级岛"
    const val NOTIFICATION_ID = 9001

    /** 用户点击关闭按钮标记（供 DismissReceiver 使用） */
    @Volatile
    var islandDismissed: Boolean = false

    fun isSupported(context: Context): Boolean =
        HyperIslandNotification.isSupported(context)

    /**
     * 诊断信息（MainActivity 调用）
     */
    fun getDiagnostics(context: Context): String {
        val supported = isSupported(context)
        val sdk = Build.VERSION.SDK_INT
        return "HyperIslandToolKit supported=$supported SDK=$sdk"
    }

    /**
     * Android 14+ POST_PROMOTED_NOTIFICATIONS 权限检测
     */
    fun hasPromotedPermission(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= 34) {
            context.checkSelfPermission("android.permission.POST_PROMOTED_NOTIFICATIONS") ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        } else false
    }

    /**
     * 打开小米焦点通知权限设置页（MainActivity 调用）
     */
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

    /**
     * 发送 HyperOS 动态岛通知
     * 完全按 getting-started "Basic Usage" 章节实现
     * 使用 setBaseInfo + setSmallIsland (不是 setSmallIslandIcon)
     */
    fun sendNotification(
        context: Context,
        title: String,
        content: String,
        iconName: String = "general",
    ) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
                )
            )
        }

        val smallIconRes = android.R.drawable.ic_dialog_info

        // 1. 构造 Builder: businessName=fbs, ticker=content
        val builder = HyperIslandNotification.Builder(context, "fbs_demo", content)
            .setBaseInfo(
                title = title,
                content = content,
                pictureKey = "my_icon"
            )
            .setSmallIsland("my_icon")  // 正确 API: setSmallIsland

        // 2. register image resource
        builder.addPicture(HyperPicture("my_icon", context, smallIconRes))

        // 3. build resource bundle + json payload
        val resBundle = builder.buildResourceBundle()
        val jsonPayload = builder.buildJsonParam()

        // 4. build standard Android notification
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIconRes)
            .setContentTitle(title)
            .setContentText(content)
            .setAutoCancel(true)
            .build()

        // 5. attach HyperOS extras
        notification.extras.putAll(resBundle)
        notification.extras.putString("miui.focus.param", jsonPayload)

        // 6. notify
        nm.notify(NOTIFICATION_ID, notification)
        Log.i(TAG, "sent: title=$title")
    }

    fun cancelNotification(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(NOTIFICATION_ID)
    }
}