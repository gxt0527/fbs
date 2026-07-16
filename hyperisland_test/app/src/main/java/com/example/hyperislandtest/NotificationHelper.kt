package com.example.hyperislandtest

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Bundle
import android.util.Log
import io.github.d4viddf.hyperisland_kit.*
import io.github.d4viddf.hyperisland_kit.models.*

/**
 * HyperIsland 通知测试工具 — 基于 v0.4.3 实际 API。
 *
 * HyperIslandNotification 直接构造（无 Builder），所有 setter 返回自身实现链式调用。
 */
class NotificationHelper(private val context: Context) {

    companion object {
        private const val TAG = "HyperIslandTest"
        private const val CHANNEL_ID = "hyperisland_test_channel"

        const val ID_BASEINFO = 1001
        const val ID_BASEINFO_BANNER = 1002
        const val ID_BASEINFO_BUTTONS = 1003
        const val ID_CHATINFO = 2001
        const val ID_COVERINFO = 2002
        const val ID_HIGHLIGHT = 2003
        const val ID_HIGHLIGHTV3 = 2004
        const val ID_ANIMTEXT = 3001
        const val ID_ICONTEXT = 3002
        const val ID_SMALLISLAND = 4001
        const val ID_BIGISLAND = 4002
        const val ID_BIGISLAND_COUNTDOWN = 4003
        const val ID_BIGISLAND_PROGRESS = 4004
        const val ID_HINT = 5001
        const val ID_BACKGROUND = 5002
        const val ID_MULTIPROGRESS = 5003
        const val ID_TIMER = 6001
    }

    fun ensureChannel() {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL_ID, "HyperIsland 测试", NotificationManager.IMPORTANCE_HIGH
        ).apply { description = "HyperIsland Toolkit 功能测试" })
    }

    // ============================
    // Templates
    // ============================

    /** 1. BaseInfo 标准（左图标） */
    fun testBaseInfoSimple() {
        val name = "BaseInfo"
        val n = HyperIslandNotification(context, "t1", name).apply {
            setLogEnabled(true)
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_check", context, R.drawable.ic_check))
            setBaseInfo(title = "下载完成", content = "年度报告.pdf", pictureKey = "icon_check")
            setSmallIsland("icon_check")
            setIslandConfig(priority = 2, timeout = 5000, dismissible = true, needCloseAnimation = true)
        }
        send(name, ID_BASEINFO, n)
    }

    /** 2. BaseInfo 横幅（右图标） */
    fun testBaseInfoBanner() {
        val name = "横幅"
        val n = HyperIslandNotification(context, "t2", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_loc", context, R.drawable.ic_location))
            setBaseInfo(type = 2, title = "暴雨预警", content = "朝阳区强降雨", pictureKey = "icon_loc",
                colorTitle = "#D32F2F")
            setSmallIsland("icon_loc")
            setIslandConfig(priority = 2, timeout = 5000, dismissible = true, needCloseAnimation = true)
        }
        send(name, ID_BASEINFO_BANNER, n)
    }

    /** 3. BaseInfo + 页脚按钮 */
    fun testBaseInfoWithActions() {
        val name = "BaseInfo+按钮"
        val open = TestBroadcastReceiver.createPendingIntent(context, "ACTION_OPEN", name, ID_BASEINFO_BUTTONS, 1)
        val like = TestBroadcastReceiver.createPendingIntent(context, "ACTION_LIKE", name, ID_BASEINFO_BUTTONS, 2)
        val n = HyperIslandNotification(context, "t3", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_check", context, R.drawable.ic_check))
            addPicture(HyperPicture("icon_heart", context, R.drawable.ic_heart))
            setBaseInfo(title = "新消息", content = "你收到一条 HyperIsland 测试消息", pictureKey = "icon_check")
            setSmallIsland("icon_check")
            setIslandConfig(priority = 2, timeout = 5000, dismissible = true, needCloseAnimation = true)
            addAction(HyperAction(key = "open", title = "打开", pendingIntent = open, actionIntentType = 2))
            addAction(HyperAction(key = "like", title = "赞", context = context, drawableRes = R.drawable.ic_heart,
                pendingIntent = like, actionIntentType = 2))
        }
        send(name, ID_BASEINFO_BUTTONS, n)
    }

    /** 4. ChatInfo 聊天 */
    fun testChatInfo() {
        val name = "ChatInfo"
        val reply = TestBroadcastReceiver.createPendingIntent(context, "ACTION_REPLY", name, ID_CHATINFO, 1)
        val n = HyperIslandNotification(context, "t4", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_check", context, R.drawable.ic_check))
            setChatInfo(title = "李四", content = "明天下午三点会议室见", pictureKey = "icon_check",
                titleColor = "#1976D2", contentColor = "#333333")
            setSmallIsland("icon_check")
            setIslandConfig(priority = 2, timeout = 5000, dismissible = true, needCloseAnimation = true)
            addAction(HyperAction(key = "reply", title = "回复", pendingIntent = reply, actionIntentType = 2))
        }
        send(name, ID_CHATINFO, n)
    }

    /** 5. CoverInfo 媒体 */
    fun testCoverInfo() {
        val name = "CoverInfo"
        val next = TestBroadcastReceiver.createPendingIntent(context, "ACTION_NEXT", name, ID_COVERINFO, 1)
        val n = HyperIslandNotification(context, "t5", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_music", context, R.drawable.ic_music))
            setCoverInfo(picKey = "icon_music", title = "波西米亚狂想曲", content = "Queen", subContent = "A Night at the Opera")
            setSmallIsland("icon_music")
            setIslandConfig(priority = 2, timeout = 5000, dismissible = true, needCloseAnimation = true)
            addAction(HyperAction(key = "next", title = "下一首", context = context, drawableRes = R.drawable.ic_music,
                pendingIntent = next, actionIntentType = 2))
        }
        send(name, ID_COVERINFO, n)
    }

    /** 6. HighlightInfo 录音高亮 */
    fun testHighlightInfo() {
        val name = "HighlightInfo"
        val now = System.currentTimeMillis()
        val timer = TimerInfo(timerType = 1, timerWhen = now - 120_000, timerTotal = 0, timerSystemCurrent = now)
        val n = HyperIslandNotification(context, "t6", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_check", context, R.drawable.ic_check))
            setHighlightInfo(title = "正在录音", content = "会议记录", subContent = "02:00", picKey = "icon_check", timer = timer)
            setSmallIsland("icon_check")
            setIslandConfig(priority = 2, timeout = null, dismissible = false, needCloseAnimation = true)
        }
        send(name, ID_HIGHLIGHT, n)
    }

    /** 7. HighlightInfoV3 标签 */
    fun testHighlightInfoV3() {
        val name = "V3标签"
        val open = TestBroadcastReceiver.createPendingIntent(context, "ACTION_OPEN", name, ID_HIGHLIGHTV3, 1)
        val n = HyperIslandNotification(context, "t7", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_check", context, R.drawable.ic_check))
            setHighlightInfoV3(primaryText = "¥128.00", secondaryText = "已支付", highLightText = "已完成",
                actionInfo = HyperAction(key = "open_order", title = "查看", pendingIntent = open, actionIntentType = 2))
            setSmallIsland("icon_check")
            setIslandConfig(priority = 2, timeout = 5000, dismissible = true, needCloseAnimation = true)
        }
        send(name, ID_HIGHLIGHTV3, n)
    }

    /** 8. AnimTextInfo 动画 */
    fun testAnimTextInfo() {
        val name = "动画"
        val n = HyperIslandNotification(context, "t8", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            setAnimTextInfo(src = "voiceWaveSmall", title = "语音助理", content = "正在听你说话...", loop = true)
            setIslandConfig(priority = 2, timeout = 5000, dismissible = true, needCloseAnimation = true)
        }
        send(name, ID_ANIMTEXT, n)
    }

    /** 9. IconTextInfo 动画+三级文本 */
    fun testIconTextInfo() {
        val name = "IconTextInfo"
        val n = HyperIslandNotification(context, "t9", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            setIconTextInfo(src = "voiceWaveSmall", title = "系统更新", content = "正在安装...", subContent = "请勿关闭设备")
            setIslandConfig(priority = 2, timeout = 5000, dismissible = true, needCloseAnimation = true)
        }
        send(name, ID_ICONTEXT, n)
    }

    // ============================
    // Dynamic Island
    // ============================

    /** 10. 小岛基础图标 */
    fun testSmallIsland() {
        val name = "小岛基础"
        val n = HyperIslandNotification(context, "t10", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_check", context, R.drawable.ic_check))
            setBaseInfo(title = "下载中", content = "文件下载中", pictureKey = "icon_check")
            setSmallIsland("icon_check")
            setIslandConfig(priority = 0, timeout = null, dismissible = false, needCloseAnimation = true)
        }
        send(name, ID_SMALLISLAND, n)
    }

    /** 11. 小岛 + 进度环 */
    fun testSmallIslandProgress() {
        val name = "小岛进度环"
        val n = HyperIslandNotification(context, "t11", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_check", context, R.drawable.ic_check))
            setBaseInfo(title = "同步中", content = "数据同步 45%", pictureKey = "icon_check")
            setSmallIslandCircularProgress(picKey = "icon_check", progress = 45, color = "#1976D2",
                bgColor = "#E3F2FD", isCCW = false)
            setIslandConfig(priority = 0, timeout = null, dismissible = false, needCloseAnimation = true)
        }
        send(name, ID_SMALLISLAND + 1, n)
    }

    /** 12. 大岛基础（左图标+文本 / 右图标） */
    fun testBigIslandSimple() {
        val name = "大岛基础"
        val n = HyperIslandNotification(context, "t12", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_music", context, R.drawable.ic_music))
            addPicture(HyperPicture("icon_heart", context, R.drawable.ic_heart))
            setBaseInfo(title = "正在播放", content = "Queen - 波西米亚狂想曲", pictureKey = "icon_music")
            setSmallIsland("icon_music")
            setIslandConfig(priority = 2, timeout = 5000, dismissible = true, needCloseAnimation = true)
            setBigIslandInfo(
                left = ImageTextInfoLeft(type = 1, picInfo = PicInfo(pic = "icon_music"),
                    textInfo = TextInfo(title = "波西米亚狂想曲")),
                right = ImageTextInfoRight(type = 2, picInfo = PicInfo(pic = "icon_heart"))
            )
        }
        send(name, ID_BIGISLAND, n)
    }

    /** 13. 大岛倒计时 */
    fun testBigIslandCountdown() {
        val name = "大岛倒计时"
        val n = HyperIslandNotification(context, "t13", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_check", context, R.drawable.ic_check))
            setBaseInfo(title = "番茄时钟", content = "休息倒计时 5:00", pictureKey = "icon_check", colorTitle = "#FF6D00")
            setSmallIsland("icon_check")
            setIslandConfig(priority = 2, timeout = null, dismissible = false, needCloseAnimation = true)
            setBigIslandCountdown(timerWhen = System.currentTimeMillis() + 5 * 60 * 1000, picKey = "icon_check")
        }
        send(name, ID_BIGISLAND_COUNTDOWN, n)
    }

    /** 14. 大岛进度环 */
    fun testBigIslandProgress() {
        val name = "大岛进度环"
        val n = HyperIslandNotification(context, "t14", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_check", context, R.drawable.ic_check))
            setBaseInfo(title = "云端同步", content = "同步进行中 72%", pictureKey = "icon_check")
            setSmallIsland("icon_check")
            setIslandConfig(priority = 0, timeout = null, dismissible = false, needCloseAnimation = true)
            setBigIslandProgressCircle(picKey = "icon_check", title = "同步中", progress = 72,
                color = "#1976D2", showProgress = true)
        }
        send(name, ID_BIGISLAND_PROGRESS, n)
    }

    /** 15. 大岛固定数字 */
    fun testBigIslandFixedDigit() {
        val name = "大岛数字"
        val n = HyperIslandNotification(context, "t15", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_check", context, R.drawable.ic_check))
            setBaseInfo(title = "通知计数", content = "你有 3 条未读消息", pictureKey = "icon_check")
            setSmallIsland("icon_check")
            setIslandConfig(priority = 2, timeout = 5000, dismissible = true, needCloseAnimation = true)
            setBigIslandFixedWidthDigit(digit = 3, content = "未读", showHighlightColor = true)
        }
        send(name, ID_BIGISLAND_PROGRESS + 1, n)
    }

    // ============================
    // Components
    // ============================

    /** 16. 提示胶囊 */
    fun testHint() {
        val name = "提示胶囊"
        val open = TestBroadcastReceiver.createPendingIntent(context, "ACTION_OPEN", name, ID_HINT, 1)
        val n = HyperIslandNotification(context, "t16", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_location", context, R.drawable.ic_location))
            setBaseInfo(title = "外卖配送", content = "骑手正在赶往你的位置", pictureKey = "icon_location")
            setSmallIsland("icon_location")
            setIslandConfig(priority = 2, timeout = 5000, dismissible = true, needCloseAnimation = true)
            addHiddenAction(HyperAction(key = "hint_open", title = "查看", pendingIntent = open, actionIntentType = 2))
            setHintInfo(title = "预计 5 分钟到达")
        }
        send(name, ID_HINT, n)
    }

    /** 17. 背景 */
    fun testBackground() {
        val name = "背景"
        val n = HyperIslandNotification(context, "t17", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_heart", context, R.drawable.ic_heart))
            addPicture(HyperPicture("icon_music", context, R.drawable.ic_music))
            setCoverInfo(picKey = "icon_music", title = "Bohemian Rhapsody", content = "Queen")
            setSmallIsland("icon_music")
            setIslandConfig(priority = 2, timeout = 5000, dismissible = true, needCloseAnimation = true)
            setBackground(picKey = "icon_heart", colorBg = "#2D2D2D", type = 1)
        }
        send(name, ID_BACKGROUND, n)
    }

    /** 18. MultiProgress 分段进度 */
    fun testMultiProgress() {
        val name = "分段进度"
        val n = HyperIslandNotification(context, "t18", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_doc", context, R.drawable.ic_doc))
            setBaseInfo(title = "批量下载", content = "3/4 个文件已完成", pictureKey = "icon_doc")
            setSmallIsland("icon_doc")
            setIslandConfig(priority = 0, timeout = 5000, dismissible = true, needCloseAnimation = true)
            setMultiProgress(title = "下载进度", progress = 75, color = "#34C759", pointNum = 4)
            setProgressBar(progress = 75, color = "#34C759")
        }
        send(name, ID_MULTIPROGRESS, n)
    }

    /** 19. StepProgress 步骤 */
    fun testStepProgress() {
        val name = "步骤进度"
        val n = HyperIslandNotification(context, "t19", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_check", context, R.drawable.ic_check))
            setBaseInfo(title = "安装中", content = "步骤 3/5", pictureKey = "icon_check")
            setSmallIsland("icon_check")
            setIslandConfig(priority = 0, timeout = 5000, dismissible = false, needCloseAnimation = true)
            setStepProgress(current = 3, total = 5, color = "#1976D2")
        }
        send(name, ID_MULTIPROGRESS + 1, n)
    }

    /** 20. 文本按钮 */
    fun testTextButtons() {
        val name = "文本按钮"
        val accept = TestBroadcastReceiver.createPendingIntent(context, "ACTION_ACCEPT", name, 9999, 1)
        val decline = TestBroadcastReceiver.createPendingIntent(context, "ACTION_DECLINE", name, 9999, 2)
        val n = HyperIslandNotification(context, "t20", name).apply {
            setSmallWindowTarget("com.example.hyperislandtest.MainActivity")
            addPicture(HyperPicture("icon_check", context, R.drawable.ic_check))
            setBaseInfo(title = "好友请求", content = "张三 请求添加你为好友", pictureKey = "icon_check")
            setSmallIsland("icon_check")
            setIslandConfig(priority = 2, timeout = 8000, dismissible = true, needCloseAnimation = true)
            setTextButtons(
                HyperAction("accept", "接受", accept, 2, bgColor = "#34C759", titleColor = "#FFFFFF"),
                HyperAction("decline", "拒绝", decline, 2, bgColor = "#FF3B30", titleColor = "#FFFFFF")
            )
        }
        send(name, 9999, n)
    }

    // ============================
    // 内部
    // ============================

    private fun send(testName: String, id: Int, n: HyperIslandNotification) {
        try {
            if (!HyperIslandNotification.isSupported(context)) {
                Log.w(TAG, "当前设备不支持 HyperIsland: $testName")
                return
            }
            val jsonParam = n.buildJsonParam()
            val resBundle = n.buildResourceBundle()

            val notification = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_check)
                .setContentTitle(testName)
                .setContentText("HyperIsland 测试")
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_STATUS)

            val extras = Bundle()
            extras.putString("miui.focus.param", jsonParam)
            extras.putAll(resBundle)
            notification.setExtras(extras)

            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(id, notification.build())
            Log.d(TAG, "发送成功: $testName (id=$id)")
        } catch (e: Exception) {
            Log.e(TAG, "发送失败: $testName", e)
        }
    }
}
