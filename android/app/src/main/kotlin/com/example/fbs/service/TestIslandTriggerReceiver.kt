package com.example.fbs.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 调试用广播接收器：
 *   adb shell am broadcast -a com.example.fbs.TEST_SUPER_ISLAND \
 *       --es title 'Test' --es content 'Hello Basic' --include-stopped-packages -p com.example.fbs
 *
 * 仅走 ToolKit 路径，便于"从零开始"阶段反复触发同一份协议抓 logcat。
 */
class TestIslandTriggerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "Test"
        val content = intent.getStringExtra("content") ?: "Hello HyperIsland"
        val icon = intent.getStringExtra("icon") ?: "general"
        Log.i("TestIslandTrigger", "title=$title content=$content icon=$icon")
        SuperIslandHelper.sendNotification(context, title, content, icon)
    }
}
