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
import android.util.Log
import com.example.fbs.R
import com.xzakota.hyper.notification.focus.FocusNotification
import com.xzakota.hyper.notification.island.model.TextInfo

/**
 * 小米超级岛通知 — 核心原理:
 *   notification.extras.putBoolean("android.requestPromotedOngoing", true)
 * 系统检测到此 extras 后自动添加 FLAG_PROMOTED_ONGOING (262144) 标志。
 *
 * 场景图标: 根据 iconName 参数切换小图标和主题色
 */
object SuperIslandHelper {

    private const val TAG = "SuperIsland"
    private const val CHANNEL_ID = "fbs_island_v2"
    private const val CHANNEL_NAME = "FBS 超级岛"
    /** 超级岛通知 ID */
    const val NOTIFICATION_ID = 9001

    /** 用户点击关闭按钮标记 — 用于外部判断是否需要重新创建 */
    @Volatile
    var islandDismissed: Boolean = false

    /** 场景 → 自定义 Vector Drawable 映射 */
    private fun getIconRes(iconName: String): Int = when (iconName) {
        "foodDelivery" -> R.drawable.ic_scene_food
        "express" -> R.drawable.ic_scene_express
        "verification" -> R.drawable.ic_scene_verify
        "payment" -> R.drawable.ic_scene_pay
        "meeting" -> R.drawable.ic_scene_meeting
        "travel" -> R.drawable.ic_scene_travel
        "order" -> R.drawable.ic_scene_order
        else -> R.drawable.ic_scene_scan  // bill / system / general
    }

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

    fun sendNotification(
        context: Context, title: String, content: String,
        iconName: String = "general",
        bgColor: Int? = null,
        glow: Boolean = false,
        glowColor: Int = 0,
        callAnimation: Boolean = false,
        iconBitmap: Boolean = false,
    ) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Post focus notification for HyperOS"
                    setAllowBubbles(true)
                }
            )
        }

        val pi = PendingIntent.getActivity(
            context, 0,
            context.packageManager.getLaunchIntentForPackage(context.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 「关闭」按钮 PendingIntent → 取消岛通知
        val dismissPI = PendingIntent.getBroadcast(
            context, 0,
            Intent(context, com.example.fbs.service.DismissReceiver::class.java).apply {
                action = "com.example.fbs.DISMISS_ISLAND"
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val iconRes = getIconRes(iconName)

        val builder = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }).apply {
            setContentTitle(title)
            setContentText(content)
            setSmallIcon(iconRes)
            setContentIntent(pi)
            setAutoCancel(false)
            setOngoing(true)
            setOnlyAlertOnce(true)
            setPriority(Notification.PRIORITY_HIGH)
            setVisibility(Notification.VISIBILITY_PRIVATE)

            // 标准展开岛操作按钮（V3 textButton 会覆盖样式）
            addAction(R.drawable.ic_action_close, "删除", dismissPI)

            // 主题色（默认品牌橙色）
            if (Build.VERSION.SDK_INT >= 31) {
                setColor(bgColor ?: 0xFFFF9500.toInt())
            }
        }

        // ── 超级岛 V3 extras（仅 callAnimation 时构建）──
        if (callAnimation) {
            try {
                val icon = if (iconBitmap) {
                    // 将 VectorDrawable 渲染为 Bitmap 再创建 Icon（发光烘焙模式）
                    val drawable = androidx.core.content.ContextCompat.getDrawable(context, iconRes)
                        ?: throw Exception("Drawable not found: $iconRes")
                    val size = 96
                    val bitmap = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
                    val canvas = android.graphics.Canvas(bitmap)
                    drawable.setBounds(0, 0, size, size)
                    drawable.draw(canvas)
                    Log.i(TAG, "Using Icon.createWithBitmap (iconBitmap=true)")
                    Icon.createWithBitmap(bitmap)
                } else {
                    Icon.createWithResource(context, iconRes)
                }

                val closePI = PendingIntent.getBroadcast(context, 10,
                    Intent(context, com.example.fbs.service.DismissReceiver::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

                val bundle = FocusNotification.buildV3 {
                    val tit = title
                    val ctt = content

                    ticker = tit
                    tickerPic = createPicture("ticker", icon)
                    enableFloat = true
                    updatable = true

                    baseInfo = com.xzakota.hyper.notification.focus.model.BaseInfo().apply {
                        this.title = tit
                        this.content = ctt
                        type = 2
                    }

                    picInfo = com.xzakota.hyper.notification.focus.model.PicInfo().apply {
                        type = 1
                        pic = createPicture("global_light", icon)
                        picDark = createPicture("global_dark", icon)
                    }

                    islandFirstFloat = false
                    if (glow) {
                        try {
                            outEffectSrc = "outer_glow"
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to set outEffectSrc", e)
                        }
                    }

                    textButton = arrayListOf(
                        com.xzakota.hyper.notification.focus.model.ActionInfo().apply {
                            action = createAction("miui_action_cancel",
                                Notification.Action.Builder(null, "删除", closePI).build())
                            actionTitle = "删除"
                        }
                    )

                    island = com.xzakota.hyper.notification.island.template.IslandTemplate().apply {
                        islandProperty = 2
                        smallIslandArea = com.xzakota.hyper.notification.island.model.SmallIslandArea().apply {
                            picInfo = com.xzakota.hyper.notification.island.model.PicInfo().apply {
                                type = 1
                                pic = createPicture("small_icon", icon)
                            }
                        }
                        bigIslandArea = com.xzakota.hyper.notification.island.model.BigIslandArea().apply {
                            imageTextInfoLeft = com.xzakota.hyper.notification.island.model.ImageTextInfo().apply {
                                type = 1
                                picInfo = com.xzakota.hyper.notification.island.model.PicInfo().apply {
                                    type = 1
                                    pic = createPicture("big_icon", icon)
                                }
                            }
                            imageTextInfoRight = com.xzakota.hyper.notification.island.model.ImageTextInfo().apply {
                                type = 3
                                textInfo = TextInfo().apply {
                                    this.title = tit
                                    this.content = ctt
                                }
                            }
                        }
                    }
                }

                builder.addExtras(bundle)
                Log.i(TAG, "Using xzakota FocusNotification.buildV3() API, glow=$glow, callAnimation=$callAnimation")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to build V3 extras via library", e)
            }
        } else {
            Log.i(TAG, "Skipping V3 extras (callAnimation=false), posting basic notification")
        }

        val notification = builder.build()
        notification.extras.putBoolean("android.requestPromotedOngoing", true)
        nm.notify(NOTIFICATION_ID, notification)
        Log.i(TAG, "Super Island notification posted: $title " +
                "(icon=$iconName, bgColor=${bgColor?.let { "#%08X".format(it) }}, glow=$glow)")
    }

    fun cancelNotification(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(NOTIFICATION_ID)
        // 恢复 XMSF 网络
        try {
            BackScreenController.execShell("cmd connectivity set-package-networking-enabled true com.xiaomi.xmsf")
            Log.i(TAG, "XMSF networking re-enabled (cancel)")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to re-enable XMSF networking", e)
        }
    }
}
