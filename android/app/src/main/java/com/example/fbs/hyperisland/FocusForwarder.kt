package com.example.fbs.hyperisland

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.os.IBinder
import android.util.Log
import rikka.shizuku.Shizuku
import rikka.shizuku.Shizuku.UserServiceArgs

/**
 * 网络阻断转发器 — 生产版本。
 *
 * 流程：阻断 XMSF → 发焦点通知 → 恢复 XMSF
 * 不涉及背屏 Activity。
 */
object FocusForwarder {

    private const val CHANNEL_ID = "hi_test_ch"
    private const val CHANNEL_NAME = "超级岛测试"
    private const val TAG = "FocusForwarder"
    private const val NOTIFICATION_ID = 9100

    private var notificationIdCounter = 0

    /**
     * 发送网络阻断后的超级岛通知。
     *
     * @param context 应用 Context
     * @param title 通知标题（如"取餐码: 7656"）— 通知栏 + baseInfo.title
     * @param content 门店/地址信息（如"新乡工商职业学院店"）— 大岛左侧内容
     * @param subtitle 副标题（如"金额：¥8"），可选 — baseInfo.subTitle
     * @param codeValue 码值（如"7656"）— 大岛右侧主显示
     * @param category 场景分类
     */
    fun send(
        context: Context,
        title: String,
        content: String,
        subtitle: String,
        codeValue: String,
        category: String
    ) {
        if (!Shizuku.pingBinder()) {
            Log.w(TAG, "Shizuku 不可用")
            return
        }
        if (Shizuku.checkSelfPermission() != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "Shizuku 无权限")
            return
        }

        val notifId = NOTIFICATION_ID + (notificationIdCounter % 100)
        notificationIdCounter++

        // 构建 JSON（复用已验证成功的 course_reminder 模板）
        val sceneName = when (category) {
            "foodDelivery", "food" -> "智能分类：美食"
            "express" -> "智能分类：快递"
            "payment", "bill" -> "智能分类：支付"
            "scan" -> "智能分类：扫码"
            "order" -> "智能分类：订单"
            "verification" -> "智能分类：验证"
            "meeting" -> "智能分类：会议"
            "travel" -> "智能分类：出行"
            else -> "智能分类：通用"
        }

        val islandParams = buildIslandJson(title, content, subtitle, codeValue, sceneName)

        // 准备 Shizuku UserService
        val component = ComponentName(context, NetworkBypassService::class.java)
        val args = UserServiceArgs(component)
            .processNameSuffix("fwd_svc")
            .daemon(false)
            .tag("focus_forward")

        Log.i(TAG, "开始 bindUserService...")
        Shizuku.bindUserService(args, object : ServiceConnection {
            override fun onServiceConnected(component: ComponentName, binder: IBinder) {
                try {
                    val service = com.example.fbs.INetworkBypass.Stub.asInterface(binder)
                    Log.i(TAG, "已连接，阻断 XMSF...")

                    // 1. 阻断 XMSF
                    service.disableXmsfNetworking()
                    try { Thread.sleep(300) } catch (_: Exception) {}

                    // 2. 构建通知
                    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        nm.createNotificationChannel(
                            NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH)
                        )
                    }

                    val smallIcon = android.R.drawable.ic_dialog_info
                    // 小岛标题：只显示场景标题（"取餐码"），不含码值
                    val shortTitle = if (title.contains(":")) title.substringBefore(":").trim() else title
                    val builder = Notification.Builder(context, CHANNEL_ID)
                        .setSmallIcon(smallIcon)
                        .setContentTitle(shortTitle)
                        .setContentText(content)
                        .setAutoCancel(true)

                    val notif = builder.build()
                    notif.extras.putString("miui.focus.param", islandParams)

                    nm.notify(notifId, notif)
                    Log.i(TAG, "✅ 通知已发送 id=$notifId")

                    // 3. 短暂等待后恢复
                    try { Thread.sleep(100) } catch (_: Exception) {}
                    service.enableXmsfNetworking()
                    Log.i(TAG, "✅ 流程完成")
                } catch (e: Exception) {
                    Log.e(TAG, "执行失败", e)
                }
                try {
                    Shizuku.unbindUserService(args, this, true)
                } catch (_: Exception) {}
            }

            override fun onServiceDisconnected(component: ComponentName) {
                Log.w(TAG, "disconnected")
            }
        })
    }

    /** 构建岛屿 JSON */
    private fun buildIslandJson(
        title: String,
        content: String,
        subtitle: String,
        codeValue: String,
        sceneName: String
    ): String {
        // 芯片显示文本：从 title 中提取短标签（"取餐码: 7656" → "取餐码"）
        val shortLabel = if (title.contains(":")) title.substringBefore(":").trim() else title
        // 大岛右侧：码值（最突出）
        val rightTitle = codeValue.ifEmpty { subtitle }
        // 大岛左侧标题：场景标签（"取餐码"），显示在小岛左侧图标旁边
        val leftTitle = shortLabel

        return "{\"param_v2\":{" +
            "\"business\":\"course_reminder\"," +
            "\"protocol\":1," +
            "\"enableFloat\":true," +
            "\"updatable\":true," +
            "\"reopen\":\"reopen\"," +
            "\"sequence\":$notificationIdCounter," +
            "\"baseInfo\":{\"type\":2,\"title\":\"${escape(title)}\",\"content\":\"${escape(content)}\",\"subTitle\":\"${escape(subtitle)}\",\"extraTitle\":\"\",\"specialTitle\":\"\",\"subContent\":\"\",\"picFunction\":\"\",\"showDivider\":true,\"showContentDivider\":false,\"colorTitle\":\"#111111\",\"colorTitleDark\":\"#ffffff\",\"colorContent\":\"#333333\",\"colorContentDark\":\"#cccccc\",\"colorSubTitle\":\"#666666\",\"colorSubTitleDark\":\"#aaaaaa\"}," +
            "\"picInfo\":{\"type\":1,\"pic\":\"\"}," +
            "\"hintInfo\":{\"type\":2,\"content\":\"${escape(shortLabel)}\",\"title\":\"\",\"subContent\":\"\",\"subTitle\":\"\",\"actionInfo\":{\"actionTitle\":\"查看\",\"actionIntentType\":1,\"actionIntent\":\"intent:#Intent;component=com.example.fbs/.MainActivity;end\"}}," +
            "\"param_island\":{\"islandProperty\":1,\"islandTimeout\":3600," +
            "\"bigIslandArea\":{\"templateNo\":2,\"imageTextInfoLeft\":{\"type\":1,\"picInfo\":{\"type\":1,\"pic\":\"\"},\"textInfo\":{\"title\":\"${escape(leftTitle)}\",\"content\":\"${escape(content)}\",\"showHighlightColor\":false,\"narrowFont\":false}},\"textInfo\":{\"frontTitle\":\"\",\"title\":\"${escape(rightTitle)}\",\"content\":\"\",\"showHighlightColor\":false,\"narrowFont\":false}}" +
            "}}}"
    }

    /** JSON 字符转义（防 break JSON） */
    private fun escape(s: String): String = s
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
}
