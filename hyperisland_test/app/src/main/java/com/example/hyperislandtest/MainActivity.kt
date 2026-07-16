package com.example.hyperislandtest

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat

/**
 * HyperIsland 测试主界面。
 *
 * 按功能分组，每个按钮触发一种 HyperIsland 通知样式。
 * 从最基础到最复杂排列，覆盖所有 Templates、Islands 和 Components。
 */
class MainActivity : AppCompatActivity() {

    private lateinit var helper: NotificationHelper
    private val sectionViews = mutableListOf<TextView>()

    // 通知权限请求（Android 13+）
    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            Toast.makeText(this, "通知权限已授予", Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(this, "请授予通知权限以发送 HyperIsland 通知", Toast.LENGTH_LONG).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        helper = NotificationHelper(this)
        helper.ensureChannel()

        // 请求通知权限
        requestNotificationPermission()

        // 构建 UI
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(16, 16, 16, 16)
        }

        val scrollView = ScrollView(this)
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            spacing = 12.dp
        }

        // 标题
        content.addView(createTitle("⚡ HyperIsland 测试工具"))
        content.addView(createSubtitle("基于 hyperisland_kit:0.4.3，点按钮发送通知"))

        // ====== 第一部分：Templates ======
        addSection(content, "📋 Templates（通知卡片模板）")
        content.addView(createTestButton("1️⃣  BaseInfo 标准", "左图标 + 标题 + 正文", R.drawable.ic_check) {
            helper.testBaseInfoSimple()
        })
        content.addView(createTestButton("2️⃣  BaseInfo 横幅", "右图标、暴雨预警样式", R.drawable.ic_location) {
            helper.testBaseInfoBanner()
        })
        content.addView(createTestButton("3️⃣  BaseInfo + 页脚按钮", "三个操作按钮在底部", R.drawable.ic_heart) {
            helper.testBaseInfoWithActions()
        })
        content.addView(createTestButton("4️⃣  ChatInfo 聊天", "发送人头像 + 消息", R.drawable.ic_check) {
            helper.testChatInfo()
        })
        content.addView(createTestButton("5️⃣  CoverInfo 媒体", "大封面 + 歌曲信息", R.drawable.ic_music) {
            helper.testCoverInfo()
        })
        content.addView(createTestButton("6️⃣  HighlightInfo 高亮", "录音中 + 实时计时器", R.drawable.ic_check) {
            helper.testHighlightInfo()
        })
        content.addView(createTestButton("7️⃣  HighlightInfo V3", "金额标签 + 操作按钮", R.drawable.ic_check) {
            helper.testHighlightInfoV3()
        })

        // ====== 第二部分：Animated Info ======
        addSection(content, "🎬 Animated Info（动画图标）")
        content.addView(createTestButton("🔟  AnimTextInfo", "系统动画 + 标题 + 正文", R.drawable.ic_music) {
            helper.testAnimTextInfo()
        })
        content.addView(createTestButton("1️⃣1️⃣  IconTextInfo", "动画 + 三级文本", R.drawable.ic_music) {
            helper.testIconTextInfo()
        })

        // ====== 第三部分：Dynamic Island ======
        addSection(content, "🏝️ Dynamic Island（灵动岛）")
        content.addView(createTestButton("1️⃣2️⃣  小岛基础", "胶囊图标", R.drawable.ic_check) {
            helper.testSmallIsland()
        })
        content.addView(createTestButton("1️⃣3️⃣  小岛 + 进度环", "胶囊图标带圆形进度", R.drawable.ic_check) {
            helper.testSmallIslandProgress()
        })
        content.addView(createTestButton("1️⃣4️⃣  大岛基础", "左图标+文本 + 右图标", R.drawable.ic_music) {
            helper.testBigIslandSimple()
        })
        content.addView(createTestButton("1️⃣5️⃣  大岛倒计时", "数字翻转 + 倒计时", R.drawable.ic_check) {
            helper.testBigIslandCountdown()
        })
        content.addView(createTestButton("1️⃣6️⃣  大岛进度环", "圆形进度 + 文本", R.drawable.ic_check) {
            helper.testBigIslandProgress()
        })
        content.addView(createTestButton("1️⃣7️⃣  大岛数字", "固定数字显示", R.drawable.ic_check) {
            helper.testBigIslandFixedDigit()
        })

        // ====== 第四部分：Components ======
        addSection(content, "🧩 Components（附加组件）")
        content.addView(createTestButton("1️⃣8️⃣  提示胶囊", "顶部小胶囊", R.drawable.ic_location) {
            helper.testHint()
        })
        content.addView(createTestButton("1️⃣9️⃣  背景图片", "全屏背景覆盖", R.drawable.ic_heart) {
            helper.testBackground()
        })
        content.addView(createTestButton("2️⃣0️⃣  分段进度", "多节点批次进度", R.drawable.ic_doc) {
            helper.testMultiProgress()
        })
        content.addView(createTestButton("2️⃣1️⃣  步骤进度", "当前/总共 步骤指示", R.drawable.ic_check) {
            helper.testStepProgress()
        })
        content.addView(createTestButton("2️⃣2️⃣  文本按钮", "药丸形 Accept/Decline", R.drawable.ic_check) {
            helper.testTextButtons()
        })

        scrollView.addView(content)
        root.addView(scrollView)
        setContentView(root)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) { // Android 13+
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    // --- UI 辅助方法 ---

    private fun createTitle(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 20f
            setTextColor(0xFF6200EE.toInt())
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setPadding(0, 8, 0, 4)
        }
    }

    private fun createSubtitle(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 13f
            setTextColor(0xFF888888.toInt())
            setPadding(0, 0, 0, 16)
        }
    }

    private fun addSection(container: LinearLayout, title: String) {
        val tv = TextView(this).apply {
            this.text = title
            textSize = 16f
            setTextColor(0xFF3700B3.toInt())
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setPadding(0, 20, 0, 8)
        }
        sectionViews.add(tv)
        container.addView(tv)
    }

    private fun createTestButton(
        label: String,
        description: String,
        iconRes: Int,
        onClick: () -> Unit
    ): Button {
        return Button(this).apply {
            text = "$label\n$description"
            textSize = 14f
            setTextColor(0xFFFFFFFF.toInt())
            setBackgroundColor(0xFF6200EE.toInt())
            setPadding(20, 16, 20, 16)
            textAlignment = TextView.TEXT_ALIGNMENT_TEXT_START
            setOnClickListener {
                try {
                    onClick()
                    Toast.makeText(context, "已发送: $label", Toast.LENGTH_SHORT).show()
                } catch (e: Exception) {
                    Toast.makeText(context, "失败: ${e.message}", Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    /** dp 转 px 扩展属性 */
    private val Int.dp: Int
        get() = (this * resources.displayMetrics.density).toInt()

    /** 设置 LinearLayout 的 item 间距 */
    private var LinearLayout.spacing: Int
        get() = 0
        set(value) {
            for (i in 0 until childCount) {
                val child = getChildAt(i)
                val lp = child.layoutParams as? LinearLayout.LayoutParams
                if (lp != null && i > 0) {
                    lp.topMargin = value
                }
            }
        }
}
