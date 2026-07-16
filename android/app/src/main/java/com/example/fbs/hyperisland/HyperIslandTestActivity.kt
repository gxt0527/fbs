package com.example.fbs.hyperisland

import android.app.Activity
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/**
 * 超级岛测试页面 — 仅测试网络阻断方案。
 *
 * 入口: adb shell am start -n com.example.fbs/.hyperisland.HyperIslandTestActivity
 */
class HyperIslandTestActivity : Activity() {

    private lateinit var h: TestNotificationHelper

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        h = TestNotificationHelper(this)
        h.ensureChannel()

        val scroll = ScrollView(this)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 24, 24, 24)
        }

        root.addView(tv("FBS 超级岛测试", 22f, 0xFF6200EE.toInt(), true))
        spacer(root)

        btn(root, "🌐 网络阻断 + 通知发送", "阻断XMSF网络→发通知→恢复（已验证稳定）") {
            h.testNetworkBypass()
        }

        section(root, "📋 FBS 转发模板（测试）")
        btn(root, "取餐码模板", "取餐码:7656 门店:... 金额:¥8 图标:背屏") {
            h.testFbsForwardTemplate()
        }

        spacer(root)
        root.addView(tv("环境要求：", 14f, 0xFF888888.toInt(), true))
        root.addView(tv("• Shizuku 已授权", 13f, 0xFF888888.toInt(), false))
        root.addView(tv("• Secure Settings 已写入", 13f, 0xFF888888.toInt(), false))
        root.addView(tv("• 屏幕解锁亮屏", 13f, 0xFF888888.toInt(), false))

        scroll.addView(root)
        setContentView(scroll)
    }

    private fun tv(text: String, size: Float, color: Int, bold: Boolean) = TextView(this).apply {
        this.text = text
        textSize = size
        setTextColor(color)
        if (bold) typeface = android.graphics.Typeface.DEFAULT_BOLD
    }

    private fun spacer(container: LinearLayout) {
        container.addView(TextView(this).apply { text = ""; setPadding(0, 6, 0, 6) })
    }

    private fun section(container: LinearLayout, title: String) {
        container.addView(tv(title, 16f, 0xFF3700B3.toInt(), true).apply { setPadding(0, 16, 0, 8) })
    }

    private fun btn(container: LinearLayout, label: String, desc: String, onClick: () -> Unit) {
        val b = Button(this).apply {
            text = "$label  — $desc"
            setTextColor(0xFFFFFFFF.toInt())
            setBackgroundColor(0xFF6200EE.toInt())
            textAlignment = TextView.TEXT_ALIGNMENT_TEXT_START
            setPadding(20, 14, 20, 14)
            setOnClickListener {
                try {
                    onClick()
                    Toast.makeText(this@HyperIslandTestActivity, "已发送", Toast.LENGTH_SHORT).show()
                } catch (e: Exception) {
                    Toast.makeText(this@HyperIslandTestActivity, "失败: ${e.message}", Toast.LENGTH_LONG).show()
                }
            }
        }
        container.addView(b, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = 6; bottomMargin = 6 })
    }
}
