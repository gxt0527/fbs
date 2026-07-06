package com.example.fbs.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import java.lang.reflect.Method

/**
 * 小米超级岛测试通知 — 用于验证岛通知是否正常工作。
 *
 * 根据小米开发者文档 https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2131
 * 超级岛通知 = 原生 Notification + miui.focus.param JSON 扩展参数。
 *
 * 注意: 正式上线需要在小米开平注册并获取权限，Debug 白名单设备可直接测试。
 */
object SuperIslandHelper {

    private const val TAG = "SuperIsland"
    private const val CHANNEL_ID = "fbs_island_test"
    private const val CHANNEL_NAME = "FBS 超级岛测试"
    private const val NOTIFICATION_ID = 9001

    /**
     * 检测当前设备是否支持超级岛（OS3+）。
     */
    fun isIslandSupported(context: Context): Boolean {
        val featureIsland = try {
            val clazz = Class.forName("android.os.SystemProperties")
            val method: Method = clazz.getDeclaredMethod("getBoolean", String::class.java, Boolean::class.java)
            val result = method.invoke(null, "persist.sys.feature.island", false)
            result as? Boolean ?: false
        } catch (_: Exception) { false }

        val protocolVersion = try {
            Settings.System.getInt(context.contentResolver, "notification_focus_protocol", 0)
        } catch (_: Exception) { 0 }

        Log.d(TAG, "islandSupported=$featureIsland protocolVersion=$protocolVersion")
        return featureIsland || protocolVersion >= 3
    }

    /**
     * 检查应用是否开启焦点通知权限。
     * 返回 true = 已开启（可以显示岛通知）
     */
    fun hasFocusPermission(context: Context): Boolean {
        return try {
            val uri = android.net.Uri.parse("content://miui.statusbar.notification.public")
            val extras = android.os.Bundle()
            extras.putString("package", context.packageName)
            val bundle = context.contentResolver.call(uri, "canShowFocus", null, extras)
            val result = bundle?.getBoolean("canShowFocus", false) ?: false
            Log.d(TAG, "hasFocusPermission=$result")
            result
        } catch (e: Exception) {
            Log.w(TAG, "hasFocusPermission check failed: ${e.message}")
            false
        }
    }

    /**
     * 打开应用的焦点通知权限设置页面。
     */
    fun openFocusNotificationSettings(context: Context) {
        try {
            val intent = android.content.Intent("miui.intent.action.APP_PERM_EDITOR")
                .setClassName("com.miui.securitycenter",
                    "com.miui.permcenter.permissions.PermissionsEditorActivity")
                .putExtra("extra_pkgname", context.packageName)
            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to open focus settings, fallback to app details")
            try {
                val intent = android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(android.net.Uri.parse("package:${context.packageName}"))
                intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    /**
     * 获取完整的诊断信息，用于调试。
     */
    fun getDiagnostics(context: Context): String {
        val island = isIslandSupported(context)
        val focus = hasFocusPermission(context)
        val protocol = try {
            Settings.System.getInt(context.contentResolver, "notification_focus_protocol", 0)
        } catch (_: Exception) { 0 }
        return "island=$island focus=$focus protocol=$protocol"
    }

    /**
     * 发送一条测试超级岛通知 — 模拟打车场景（taxi）。
     *
     * 包含:
     * - 大岛: 左侧图标+文字（行程状态）+ 右侧图片
     * - 小岛: 图标
     * - 焦点通知: 标题+内容+操作按钮
     */
    fun sendTestIslandNotification(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 创建通知渠道
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "FBS 超级岛测试通知"
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
        }

        // ── 1. 构建岛通知 JSON 参数 ──
        val islandParams = """
        {
            "param_v2": {
                "protocol": 1,
                "business": "fbs_test",
                "enableFloat": true,
                "updatable": true,
                "timeout": 5,

                "ticker": "FBS 超级岛测试",
                "aodTitle": "FBS 超级岛测试通知",

                "param_island": {
                    "islandProperty": 1,
                    "bigIslandArea": {
                        "imageTextInfoLeft": {
                            "type": 1,
                            "textInfo": {
                                "frontTitle": "FBS 测试",
                                "title": "超级岛已就绪",
                                "content": "通知转发功能正常",
                                "useHighLight": false
                            }
                        },
                        "imageTextInfoRight": {
                            "type": 2,
                            "textInfo": {
                                "title": "ON",
                                "useHighLight": true
                            }
                        }
                    },
                    "smallIslandArea": {
                        "textInfo": {
                            "title": "FBS",
                            "useHighLight": false
                        }
                    },
                    "shareData": {
                        "pic": "miui.focus.pic_share",
                        "title": "FBS 超级岛测试",
                        "content": "通知转发功能正常运行中",
                        "shareContent": "FBS 超级岛测试通知"
                    }
                },

                "baseInfo": {
                    "title": "FBS 超级岛测试",
                    "content": "通知转发功能已就绪，点击查看详情",
                    "type": 1
                },
                "hintInfo": {
                    "type": 1,
                    "title": "测试通过"
                }
            }
        }
        """.trimIndent()

        // ── 2. 构建原生通知 ──
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = PendingIntent.getActivity(
            context, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder.setContentTitle("FBS 超级岛测试")
            .setContentText("通知转发功能已就绪")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setOngoing(true)

        // ── 3. 添加 Action（可选） ──
        val actionsBundle = Bundle()
        val testActionIntent = Intent("com.example.fbs.ACTION_ISLAND_TEST")
        testActionIntent.setPackage(context.packageName)
        val testPendingIntent = PendingIntent.getBroadcast(
            context, 100, testActionIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val action = Notification.Action.Builder(
            Icon.createWithResource(context, android.R.drawable.ic_dialog_info),
            "查看详情",
            testPendingIntent
        ).build()
        actionsBundle.putParcelable("miui.focus.action_detail", action)
        builder.addExtras(Bundle().apply { putBundle("miui.focus.actions", actionsBundle) })

        // ── 4. 添加图片占位（使用应用自带图标） ──
        val picsBundle = Bundle()
        picsBundle.putParcelable("miui.focus.pic_imageText",
            Icon.createWithResource(context, android.R.drawable.ic_dialog_info))
        picsBundle.putParcelable("miui.focus.pic_share",
            Icon.createWithResource(context, android.R.drawable.ic_dialog_info))
        builder.addExtras(Bundle().apply { putBundle("miui.focus.pics", picsBundle) })

        // ── 5. 构建并发送通知 ──
        val notification = builder.build()
        notification.extras.putString("miui.focus.param", islandParams)

        nm.notify(NOTIFICATION_ID, notification)
        Log.d(TAG, "Test island notification sent (id=$NOTIFICATION_ID)")
    }

    /**
     * 清除测试通知。
     */
    fun cancelTestNotification(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(NOTIFICATION_ID)
        Log.d(TAG, "Test island notification cancelled")
    }
}
