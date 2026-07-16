package com.example.hyperislandtest

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast

/**
 * 接收 HyperIsland 通知按钮点击的广播接收器。
 *
 * 所有通知按钮通过 addAction() / addHiddenAction() 注册到这个接收器，
 * 用 action 字段区分不同按钮。
 */
class TestBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "HyperIslandTest"

        // Action keys 用于 Intent 的 action 字段
        const val ACTION_OPEN = "ACTION_OPEN"
        const val ACTION_REPLY = "ACTION_REPLY"
        const val ACTION_LIKE = "ACTION_LIKE"
        const val ACTION_DISMISS = "ACTION_DISMISS"
        const val ACTION_NEXT = "ACTION_NEXT"
        const val ACTION_STOP = "ACTION_STOP"
        const val ACTION_CALL = "ACTION_CALL"
        const val ACTION_MARK_READ = "ACTION_MARK_READ"
        const val ACTION_ACCEPT = "ACTION_ACCEPT"
        const val ACTION_DECLINE = "ACTION_DECLINE"

        // Intent 中附加的额外数据 key
        const val EXTRA_TEST_NAME = "test_name"
        const val EXTRA_NOTIFICATION_ID = "notification_id"

        /**
         * 创建用于通知按钮的 PendingIntent。
         */
        fun createPendingIntent(
            context: Context,
            action: String,
            testName: String,
            notificationId: Int,
            requestCode: Int = System.currentTimeMillis().toInt()
        ): android.app.PendingIntent {
            val intent = Intent(context, TestBroadcastReceiver::class.java).apply {
                this.action = action
                putExtra(EXTRA_TEST_NAME, testName)
                putExtra(EXTRA_NOTIFICATION_ID, notificationId)
            }
            return android.app.PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: "unknown"
        val testName = intent.getStringExtra(EXTRA_TEST_NAME) ?: ""
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)

        Log.d(TAG, "Action received: $action (test=$testName, id=$notificationId)")

        val message = when (action) {
            ACTION_OPEN -> "打开应用"
            ACTION_REPLY -> "回复消息"
            ACTION_LIKE -> "点赞"
            ACTION_DISMISS -> "关闭通知"
            ACTION_NEXT -> "下一首"
            ACTION_STOP -> "停止"
            ACTION_CALL -> "拨打电话"
            ACTION_MARK_READ -> "标记已读"
            ACTION_ACCEPT -> "接受"
            ACTION_DECLINE -> "拒绝"
            else -> "未知操作: $action"
        }

        Toast.makeText(context, "测试[$testName]: $message", Toast.LENGTH_SHORT).show()
    }
}
