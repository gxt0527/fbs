package com.example.fbs.hyperisland

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.graphics.drawable.Icon
import android.os.Bundle
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
    private val activeIds = mutableSetOf<Int>()

    /** 最近一次发送的、与背屏关联的通知 ID */
    @Volatile
    var lastBackScreenNotifId: Int = -1
        private set

    @Synchronized
    fun addActiveId(id: Int) { activeIds.add(id) }

    @Synchronized
    fun removeActiveId(id: Int) { activeIds.remove(id) }

    @Synchronized
    fun isActiveId(id: Int): Boolean = id in activeIds

    /** 取消所有活跃通知（供"清除"按钮使用） */
    @Synchronized
    fun cancelAll(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        for (id in activeIds) {
            nm.cancel(id)
        }
        activeIds.clear()
    }

    /** 取消最近一次与背屏关联的通知（供返回手势使用，不触及其它通知） */
    @Synchronized
    fun cancelLastBackScreen(context: Context) {
        if (lastBackScreenNotifId >= 0) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(lastBackScreenNotifId)
            activeIds.remove(lastBackScreenNotifId)
            lastBackScreenNotifId = -1
        }
    }

    /** 场景分类 → 智能图标资源 ID 映射 */
    private fun sceneIconRes(category: String): Int {
        return when (category) {
            "foodDelivery", "food" -> com.example.fbs.R.drawable.ic_scene_food
            "express" -> com.example.fbs.R.drawable.ic_scene_express
            "payment", "bill" -> com.example.fbs.R.drawable.ic_scene_pay
            "scan" -> com.example.fbs.R.drawable.ic_scene_scan
            "order" -> com.example.fbs.R.drawable.ic_scene_order
            "verification" -> com.example.fbs.R.drawable.ic_scene_verify
            "meeting" -> com.example.fbs.R.drawable.ic_scene_meeting
            "travel" -> com.example.fbs.R.drawable.ic_scene_travel
            else -> com.example.fbs.R.drawable.ic_scene_order
        }
    }

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

        val notifId = NOTIFICATION_ID + notificationIdCounter
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

                    val smallIcon = sceneIconRes(category)
                    // 小岛标题：只显示场景标题（"取餐码"），不含码值
                    val shortTitle = if (title.contains(":")) title.substringBefore(":").trim() else title
                    val builder = Notification.Builder(context, CHANNEL_ID)
                        .setSmallIcon(smallIcon)
                        .setContentTitle(shortTitle)
                        .setContentText(content)
                        .setWhen(System.currentTimeMillis())
                        .setAutoCancel(true)

                    val notif = builder.build()
                    notif.extras.putString("miui.focus.param", islandParams)

                    nm.notify(notifId, notif)
                    addActiveId(notifId)
                    lastBackScreenNotifId = notifId
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

    // ═════════════════════════════════════════════════════════
    // 🆕 模板 #9 — 文本组件2 + 识别图形组件1 + 按钮组件2
    // 适用于：取餐码、电影票等场景
    //
    // ⚠️ 禁止任何对模板的修改，只能通过调用字段更换显示的内容！
    //    模板 JSON 字段（baseInfo/bigIslandArea/hintInfo）不可增删改结构，
    //    如需调整显示内容，请修改调用方传入的参数值。
    // ═════════════════════════════════════════════════════════

    /**
     * 模板 #9 网络阻断转发 — 适用于取餐码场景。
     *
     * 布局：文本组件2（主要文本1/"取餐码"+ 次要文本1/"件数 金额"）
     *      + 识别图形组件1（默认桌面图标）
     *      + 按钮组件2（前置文本1/"到店自取"+ 主要小文本1/"请留意大屏信息"+ 按钮文本/"查看"）
     *
     * 小岛：A区 = 图标 + "取餐码"，B区 = "码值"
     *
     * @param context 应用 Context
     * @param label 主要文本1（如"取餐码"）
     * @param codeValue 主要文本2/码值（如"7656"）
     * @param storeName 次要文本2/店名地址（如"新乡工商职业学院店"）
     * @param items 件数描述（如"1杯"）
     * @param amount 金额（如"¥8"）
     * @param category 场景分类
     */
    fun sendTemplate9(
        context: Context,
        label: String,
        codeValue: String,
        storeName: String,
        items: String,
        amount: String,
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

        val notifId = NOTIFICATION_ID + notificationIdCounter
        notificationIdCounter++

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

        val islandParams = buildIslandJsonTemplate9(label, codeValue, storeName, items, amount, sceneName, category)

        val component = ComponentName(context, NetworkBypassService::class.java)
        val args = UserServiceArgs(component)
            .processNameSuffix("fwd_svc")
            .daemon(false)
            .tag("focus_forward_t9")

        Log.i(TAG, "[T9] 开始 bindUserService...")
        Shizuku.bindUserService(args, object : ServiceConnection {
            override fun onServiceConnected(component: ComponentName, binder: IBinder) {
                try {
                    val service = com.example.fbs.INetworkBypass.Stub.asInterface(binder)
                    Log.i(TAG, "[T9] 已连接，阻断 XMSF...")

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

                    val sceneIconDrawable = sceneIconRes(category)
                    val builder = Notification.Builder(context, CHANNEL_ID)
                        .setSmallIcon(sceneIconDrawable)
                        .setContentTitle("$label: $codeValue")
                        .setContentText(storeName.ifEmpty {
                            when (category) {
                                "foodDelivery", "food" -> "请留意大屏信息"
                                "express" -> "请核对收件人信息"
                                "payment" -> "注意账户安全"
                                "verification" -> "验证码仅限本人使用"
                                "meeting" -> "会议即将开始"
                                "travel" -> "您的行程已安排"
                                "bill" -> "账单已出"
                                "order" -> "订单已生成"
                                else -> "新消息提醒"
                            }
                        })
                        .setWhen(System.currentTimeMillis())
                        .setAutoCancel(true)

                    val notif = builder.build()
                    // 设置场景图标到 miui.focus.pics Bundle（小岛使用）
                    val sceneIcon = Icon.createWithResource(context, sceneIconRes(category))
                    val picsBundle = Bundle()
                    picsBundle.putParcelable("fbs_scene_icon", sceneIcon)
                    notif.extras.putBundle("miui.focus.pics", picsBundle)
                    notif.extras.putString("miui.focus.param", islandParams)

                    nm.notify(notifId, notif)
                    addActiveId(notifId)
                    lastBackScreenNotifId = notifId
                    Log.i(TAG, "[T9] ✅ 通知已发送 id=$notifId")

                    // 3. 短暂等待后恢复
                    try { Thread.sleep(100) } catch (_: Exception) {}
                    service.enableXmsfNetworking()
                    Log.i(TAG, "[T9] ✅ 流程完成")
                } catch (e: Exception) {
                    Log.e(TAG, "[T9] 执行失败", e)
                }
                try {
                    Shizuku.unbindUserService(args, this, true)
                } catch (_: Exception) {}
            }

            override fun onServiceDisconnected(component: ComponentName) {
                Log.w(TAG, "[T9] disconnected")
            }
        })
    }

    /** 场景分类 → 智能图标资源名 */
    private fun sceneIconName(category: String): String {
        return when (category) {
            "foodDelivery", "food" -> "ic_scene_food"
            "express" -> "ic_scene_express"
            "payment", "bill" -> "ic_scene_pay"
            "scan" -> "ic_scene_scan"
            "order" -> "ic_scene_order"
            "verification" -> "ic_scene_verify"
            "meeting" -> "ic_scene_meeting"
            "travel" -> "ic_scene_travel"
            else -> "ic_scene_order"
        }
    }

    /** 构建模板 #9 岛屿 JSON */
    private fun buildIslandJsonTemplate9(
        label: String,
        codeValue: String,
        storeName: String,
        items: String,
        amount: String,
        sceneName: String,
        category: String
    ): String {
        val subTitleText = buildString {
            if (items.isNotEmpty()) { append("件数：$items") }
            if (items.isNotEmpty() && amount.isNotEmpty()) { append("  ") }
            if (amount.isNotEmpty()) { append("金额：¥$amount") }
        }

        // 把件数+金额拼接到店名前面作为 content 字段
        val contentText = buildString {
            if (subTitleText.isNotEmpty()) { append(subTitleText) }
            if (subTitleText.isNotEmpty() && storeName.isNotEmpty()) { append("  ") }
            if (storeName.isNotEmpty()) { append(storeName) }
        }

        val safeLabel = label.ifEmpty { "取餐码" }

        // 根据不同场景调整展开提示文案
        val (hintContent, hintTitle) = when (category) {
            "foodDelivery", "food" -> "到店自取" to "请留意大屏信息"
            "express" -> "请及时取件" to "请核对收件人信息"
            "payment" -> "请核对金额" to "注意账户安全"
            "verification" -> "请勿泄露" to "验证码仅限本人使用"
            "meeting" -> "准时参加" to "会议即将开始"
            "travel" -> "注意行程变动" to "您的行程已安排"
            "bill" -> "请及时缴费" to "账单已出"
            "order" -> "查看订单详情" to "订单已生成"
            else -> "查看详情" to "新消息提醒"
        }

        return "{\"param_v2\":{" +
            "\"business\":\"course_reminder\"," +
            "\"protocol\":1," +
            "\"enableFloat\":true," +
            "\"updatable\":true," +
            "\"reopen\":\"reopen\"," +
            "\"sequence\":$notificationIdCounter," +
            "\"baseInfo\":{" +
                "\"type\":2," +
                "\"title\":\"${escape(safeLabel)}\"," +
            "\"content\":\"${escape(contentText)}\"," +
            "\"extraTitle\":\"${escape(codeValue)}\"," +
                "\"specialTitle\":\"\"," +
                "\"subContent\":\"\"," +
                "\"picFunction\":\"\"," +
                "\"showDivider\":false," +
                "\"showContentDivider\":false," +
                "\"colorTitle\":\"#D32F2F\"," +
                "\"colorExtraTitle\":\"#D32F2F\"," +
                "\"colorExtraTitleDark\":\"#EF5350\"," +
                "\"colorTitleDark\":\"#EF5350\"," +
                "\"colorContent\":\"#333333\"," +
                "\"colorContentDark\":\"#cccccc\"," +
                "\"colorSubTitle\":\"#666666\"," +
                "\"colorSubTitleDark\":\"#aaaaaa\"" +
            "}," +
            "\"picInfo\":{\"type\":1,\"pic\":\"\"}," +
            "\"hintInfo\":{" +
                "\"type\":2," +
                "\"content\":\"${escape(hintContent)}\"," +
                "\"title\":\"${escape(hintTitle)}\"," +
                "\"subContent\":\"\"," +
                "\"subTitle\":\"\"," +
                "\"colorContent\":\"#666666\"," +
                "\"colorContentDark\":\"#aaaaaa\"," +
                "\"colorTitle\":\"#222222\"," +
                "\"colorTitleDark\":\"#eeeeee\"," +
                "\"colorSubContent\":\"#666666\"," +
                "\"colorSubContentDark\":\"#aaaaaa\"," +
                "\"colorSubTitle\":\"#222222\"," +
                "\"colorSubTitleDark\":\"#eeeeee\"," +
                "\"actionInfo\":{" +
                    "\"actionTitle\":\"查看\"," +
                    "\"actionIntentType\":1," +
                    "\"actionIntent\":\"intent:#Intent;component=com.example.fbs/.MainActivity;end\"" +
                "}" +
            "}," +
            "\"param_island\":{" +
                "\"islandProperty\":1," +
                "\"islandTimeout\":3600," +
                "\"bigIslandArea\":{" +
                    "\"templateNo\":9," +
                    "\"imageTextInfoLeft\":{" +
                        "\"type\":1," +
                        "\"picInfo\":{\"type\":1,\"pic\":\"fbs_scene_icon\"}," +
                        "\"textInfo\":{" +
                            "\"title\":\"${escape(safeLabel)}\"," +
                            "\"showHighlightColor\":false," +
                            "\"narrowFont\":false" +
                        "}" +
                    "}," +
                    "\"textInfo\":{" +
                        "\"frontTitle\":\"\"," +
                        "\"title\":\"${escape(codeValue)}\"," +
                        "\"content\":\"${escape(subTitleText)}\"," +
                        "\"showHighlightColor\":false," +
                        "\"narrowFont\":false" +
                    "}" +
                "}," +
                "\"smallIslandArea\":{" +
                    "\"picInfo\":{\"type\":1,\"pic\":\"fbs_scene_icon\"}" +
                "}" +
            "}" +
        "}}"
    }

    /** JSON 字符转义（防 break JSON） */
    private fun escape(s: String): String = s
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
}
