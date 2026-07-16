package com.example.fbs.hyperisland

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.graphics.drawable.Icon
import android.os.IBinder
import android.util.Log
import rikka.shizuku.Shizuku
import rikka.shizuku.Shizuku.UserServiceArgs

/**
 * HyperIsland 测试辅助类 — 仅保留网络阻断方案。
 *
 * 20 种模板已移除，仅保留已被验证成功的网络阻断方案。
 */
class TestNotificationHelper(private val ctx: Context) {

    companion object {
        private const val CHANNEL = "hi_test_ch"
        const val TAG = "HITest"
        private var bypassCounter = 0
    }

    fun ensureChannel() {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "超级岛测试", NotificationManager.IMPORTANCE_HIGH))
    }

    // ═══════════════════════════════════
    // ✅ 网络阻断方案（唯一已验证成功）
    // ═══════════════════════════════════

    /** 网络阻断方案：阻断 XMSF → 普通发通知 → 恢复 XMSF */
    fun testNetworkBypass() {
        try {
            if (!Shizuku.pingBinder()) {
                Log.w(TAG, "[Bypass] Shizuku 不可用")
                return
            }
            if (Shizuku.checkSelfPermission() != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                Log.w(TAG, "[Bypass] Shizuku 无权限")
                return
            }

            // 每次用不同的 ID，避免系统 filterOut old
            val notifId = 501 + (bypassCounter % 100)
            bypassCounter++
            val seq = bypassCounter
            val islandParams = "{\"param_v2\":{" +
                "\"business\":\"course_reminder\"," +
                "\"protocol\":1," +
                "\"enableFloat\":true," +
                "\"updatable\":true," +
                "\"reopen\":\"reopen\"," +
                "\"sequence\":$seq," +
                "\"baseInfo\":{\"type\":2,\"title\":\"高等数学\",\"content\":\"第1-2节｜A301｜08:00\",\"subTitle\":\"\",\"extraTitle\":\"\",\"specialTitle\":\"\",\"subContent\":\"\",\"picFunction\":\"\",\"showDivider\":true,\"showContentDivider\":false,\"colorTitle\":\"#111111\",\"colorTitleDark\":\"#ffffff\",\"colorContent\":\"#333333\",\"colorContentDark\":\"#cccccc\"}," +
                "\"picInfo\":{\"type\":1,\"pic\":\"\"}," +
                "\"hintInfo\":{\"type\":2,\"content\":\"即将上课\",\"title\":\"\",\"subContent\":\"地点\",\"subTitle\":\"A301\",\"colorContent\":\"#666666\",\"colorContentDark\":\"#aaaaaa\",\"colorTitle\":\"#222222\",\"colorTitleDark\":\"#eeeeee\",\"colorSubContent\":\"#666666\",\"colorSubContentDark\":\"#aaaaaa\",\"colorSubTitle\":\"#222222\",\"colorSubTitleDark\":\"#eeeeee\",\"actionInfo\":{\"actionTitle\":\"查看课表\",\"actionIntentType\":1,\"actionIntent\":\"intent:#Intent;component=com.example.fbs/.hyperisland.HyperIslandTestActivity;end\"}}," +
                "\"param_island\":{\"islandProperty\":1,\"islandTimeout\":3600," +
                "\"bigIslandArea\":{\"templateNo\":2,\"imageTextInfoLeft\":{\"type\":1,\"textInfo\":{\"title\":\"高等数学\",\"content\":\"\",\"showHighlightColor\":false,\"narrowFont\":false}},\"textInfo\":{\"frontTitle\":\"\",\"title\":\"A301\",\"content\":\"\",\"showHighlightColor\":false,\"narrowFont\":false}}," +
                "\"smallIslandArea\":{\"picInfo\":{\"type\":1,\"pic\":\"miui.focus.pic_small\",\"picDark\":\"miui.focus.pic_small_dark\"}}}" +
            "}}"
            Log.w(TAG, "[Bypass] JSON >>> $islandParams")

            val component = ComponentName(ctx, com.example.fbs.hyperisland.NetworkBypassService::class.java)
            val args = UserServiceArgs(component)
                .processNameSuffix("bypass_svc")
                .daemon(false)
                .tag("bypass")

            Log.w(TAG, "[Bypass] 开始 bindUserService...")
            Shizuku.bindUserService(args, object : ServiceConnection {
                override fun onServiceConnected(component: ComponentName, binder: IBinder) {
                    try {
                        val service = com.example.fbs.INetworkBypass.Stub.asInterface(binder)
                        Log.w(TAG, "[Bypass] 已连接，准备阻断 XMSF...")

                        // 1. 阻断 XMSF 网络
                        val disabled = service.disableXmsfNetworking()
                        Log.w(TAG, "[Bypass] disableXmsfNetworking: $disabled")

                        // 2. 等待防火墙生效
                        try { Thread.sleep(300) } catch (_: Exception) {}

                        // 3. 从 App 进程发通知
                        val notif = Notification.Builder(ctx, CHANNEL)
                            .setSmallIcon(android.R.drawable.ic_dialog_info)
                            .setContentTitle("高等数学")
                            .setContentText("第1-2节｜A301｜08:00")
                            .setAutoCancel(true)
                            .build()
                        notif.extras.putString("miui.focus.param", islandParams)
                        (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(notifId, notif)
                        Log.w(TAG, "[Bypass] ✅ 通知已发送 id=$notifId")

                        // 4. 短暂等待
                        try { Thread.sleep(100) } catch (_: Exception) {}

                        // 5. 恢复 XMSF 网络
                        val enabled = service.enableXmsfNetworking()
                        Log.w(TAG, "[Bypass] enableXmsfNetworking: $enabled")
                        Log.w(TAG, "[Bypass] ✅ 流程完成！")
                    } catch (e: Exception) {
                        Log.e(TAG, "[Bypass] 执行失败", e)
                    }
                    try {
                        Shizuku.unbindUserService(args, this, true)
                    } catch (_: Exception) {}
                }

                override fun onServiceDisconnected(component: ComponentName) {
                    Log.w(TAG, "[Bypass] disconnected")
                }
            })
            Log.w(TAG, "[Bypass] bindUserService 已调用")
        } catch (e: Exception) {
            Log.e(TAG, "[Bypass] 失败", e)
        }
    }

    // ═══════════════════════════════════
    // 📋 FBS 转发模板
    // ═══════════════════════════════════

    /**
     * FBS 通知转发模板。
     * 模拟从背屏 App 转发通知到超级岛的场景。
     */
    fun testFbsForwardTemplate() {
        try {
            if (!Shizuku.pingBinder()) {
                Log.w(TAG, "[FBS] Shizuku 不可用")
                return
            }
            if (Shizuku.checkSelfPermission() != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                Log.w(TAG, "[FBS] Shizuku 无权限")
                return
            }

            val notifId = 601 + (bypassCounter % 100)
            bypassCounter++

            // 来源应用 — 使用 FBS 自带的智能场景分类图标
            val sourcePkg = "com.example.fbs"
            val sourceIcon = Icon.createWithResource(ctx, com.example.fbs.R.drawable.ic_scene_food)
            val sourceIntent = ctx.packageManager.getLaunchIntentForPackage(sourcePkg)
            // 构建 JSON — 小米官方格式，展示取餐信息
            val islandParams = "{\"param_v2\":{" +
                "\"business\":\"course_reminder\"," +
                "\"protocol\":1," +
                "\"enableFloat\":true," +
                "\"updatable\":true," +
                "\"reopen\":\"reopen\"," +
                "\"sequence\":$bypassCounter," +
                "\"baseInfo\":{\"type\":2,\"title\":\"取餐码: 7656\",\"content\":\"门店：新乡工商职业学院店\",\"subTitle\":\"金额：¥8 ｜ 件数：1杯\",\"extraTitle\":\"\",\"specialTitle\":\"\",\"subContent\":\"\",\"picFunction\":\"\",\"showDivider\":true,\"showContentDivider\":false,\"colorTitle\":\"#D32F2F\",\"colorTitleDark\":\"#EF5350\",\"colorContent\":\"#333333\",\"colorContentDark\":\"#cccccc\",\"colorSubTitle\":\"#666666\",\"colorSubTitleDark\":\"#aaaaaa\"}," +
                "\"picInfo\":{\"type\":1,\"pic\":\"\"}," +
                "\"hintInfo\":{\"type\":2,\"content\":\"智能分类：美食\",\"title\":\"\",\"subContent\":\"\",\"subTitle\":\"\",\"actionInfo\":{\"actionTitle\":\"查看\",\"actionIntentType\":1,\"actionIntent\":\"intent:#Intent;component=com.example.fbs/.MainActivity;end\"}}," +
                "\"param_island\":{\"islandProperty\":1,\"islandTimeout\":3600," +
                "\"bigIslandArea\":{\"templateNo\":2,\"imageTextInfoLeft\":{\"type\":1,\"picInfo\":{\"type\":1,\"pic\":\"miui.focus.pic_small\"},\"textInfo\":{\"title\":\"取餐码\",\"content\":\"新乡工商职业学院店\",\"showHighlightColor\":false,\"narrowFont\":false}},\"textInfo\":{\"frontTitle\":\"\",\"title\":\"7656 ｜ 1杯\",\"content\":\"\",\"showHighlightColor\":false,\"narrowFont\":false}}," +
                "\"smallIslandArea\":{\"picInfo\":{\"type\":1,\"pic\":\"miui.focus.pic_small\",\"picDark\":\"miui.focus.pic_small_dark\"}}}" +
            "}}"
            Log.w(TAG, "[FBS] JSON >>> $islandParams")

            val component = ComponentName(ctx, com.example.fbs.hyperisland.NetworkBypassService::class.java)
            val args = UserServiceArgs(component)
                .processNameSuffix("fbs_svc")
                .daemon(false)
                .tag("fbs_forward")

            Log.w(TAG, "[FBS] 开始 bindUserService...")
            Shizuku.bindUserService(args, object : ServiceConnection {
                override fun onServiceConnected(component: ComponentName, binder: IBinder) {
                    try {
                        val service = com.example.fbs.INetworkBypass.Stub.asInterface(binder)
                        Log.w(TAG, "[FBS] 已连接，准备阻断 XMSF...")

                        // 1. 阻断 XMSF
                        service.disableXmsfNetworking()
                        try { Thread.sleep(300) } catch (_: Exception) {}

                        // 2. 构建通知（使用智能场景分类图标）
                        val builder = Notification.Builder(ctx, CHANNEL)
                            .setSmallIcon(com.example.fbs.R.drawable.ic_scene_food)
                            .setContentTitle("取餐码: 7656")
                            .setContentText("新乡工商职业学院店")
                            .setAutoCancel(true)

                        // 设置跳转到 FBS
                        if (sourceIntent != null) {
                            val pi = android.app.PendingIntent.getActivity(
                                ctx, notifId, sourceIntent,
                                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
                            builder.setContentIntent(pi)
                        }

                        val notif = builder.build()
                        notif.extras.putString("miui.focus.param", islandParams)

                        (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(notifId, notif)
                        Log.w(TAG, "[FBS] ✅ 通知已发送 id=$notifId")

                        // 3. 短暂等待后恢复 XMSF
                        try { Thread.sleep(100) } catch (_: Exception) {}
                        service.enableXmsfNetworking()
                        Log.w(TAG, "[FBS] ✅ 流程完成！")
                    } catch (e: Exception) {
                        Log.e(TAG, "[FBS] 执行失败", e)
                    }
                    try {
                        Shizuku.unbindUserService(args, this, true)
                    } catch (_: Exception) {}
                }

                override fun onServiceDisconnected(component: ComponentName) {
                    Log.w(TAG, "[FBS] disconnected")
                }
            })
            Log.w(TAG, "[FBS] bindUserService 已调用")
        } catch (e: Exception) {
            Log.e(TAG, "[FBS] 失败", e)
        }
    }
}
