import re

with open(r'E:\MSRR\fbs\android\app\src\main\kotlin\com\example\fbs\service\BackScreenNotificationActivity.kt', 'r', encoding='utf-8') as f:
    content = f.read()

# Add camera avoidance and more style extras to the intent parsing section
old = '''            val showAppIcon = intent.getStringExtra("showAppIcon")?.toBooleanStrictOrNull() ?: true
            val showTimestamp = intent.getStringExtra("showTimestamp")?.toBooleanStrictOrNull() ?: true
            val padding = intent.getStringExtra("padding")?.toFloatOrNull() ?: 24f
            val spacing = intent.getStringExtra("spacing")?.toFloatOrNull() ?: 12f
            displayDurationMs = intent.getStringExtra("displayDurationMs")?.toLongOrNull() ?: 10000L'''

new = '''            val showAppIcon = intent.getStringExtra("showAppIcon")?.toBooleanStrictOrNull() ?: true
            val showTimestamp = intent.getStringExtra("showTimestamp")?.toBooleanStrictOrNull() ?: true
            val cameraAvoidance = intent.getStringExtra("cameraAvoidanceEnabled")?.toBooleanStrictOrNull() ?: false
            val padding = intent.getStringExtra("padding")?.toFloatOrNull() ?: 24f
            val spacing = intent.getStringExtra("spacing")?.toFloatOrNull() ?: 12f
            val horizontalOffset = intent.getStringExtra("horizontalOffset")?.toFloatOrNull() ?: 0f
            displayDurationMs = intent.getStringExtra("displayDurationMs")?.toLongOrNull() ?: 10000L

            // 摄像头避开：背屏摄像头在左侧 ~296px cutout
            val cameraOffsetPx = if (cameraAvoidance) {
                try { display?.cutout?.safeInsetLeft?.toFloat() ?: 296f } catch (_: Exception) { 296f }
            } else 0f
            val contentOffset = horizontalOffset + cameraOffsetPx'''

content = content.replace(old, new, 1)

# Update the RenderConfig creation to pass new values
old2 = '''            renderView = NotificationRenderView(
                context = this,
                config = RenderConfig(
                    title = if (title.isNotEmpty()) title else appName,
                    subtitle = subtitle,
                    content = content,
                    titleFontSize = titleFontSize,
                    subtitleFontSize = subtitleFontSize,
                    contentFontSize = contentFontSize,
                    titleColor = titleColor,
                    subtitleColor = subtitleColor,
                    contentColor = contentColor,
                    backgroundColor = backgroundColor,
                    showAppIcon = showAppIcon,
                    showTimestamp = showTimestamp,
                    padding = padding,
                    spacing = spacing,
                )
            )'''

new2 = '''            renderView = NotificationRenderView(
                context = this,
                config = RenderConfig(
                    title = if (title.isNotEmpty()) title else appName,
                    subtitle = subtitle,
                    content = content,
                    titleFontSize = titleFontSize,
                    subtitleFontSize = subtitleFontSize,
                    contentFontSize = contentFontSize,
                    titleColor = titleColor,
                    subtitleColor = subtitleColor,
                    contentColor = contentColor,
                    backgroundColor = backgroundColor,
                    showAppIcon = showAppIcon,
                    showTimestamp = showTimestamp,
                    cameraAvoidance = cameraAvoidance,
                    padding = padding,
                    spacing = spacing,
                    contentOffset = contentOffset,
                )
            )'''

content = content.replace(old2, new2, 1)

# Update RenderConfig data class to add new fields
old3 = '''    data class RenderConfig(
        val title: String,
        val subtitle: String,
        val content: String,
        val titleFontSize: Float,
        val subtitleFontSize: Float,
        val contentFontSize: Float,
        val titleColor: Int,
        val subtitleColor: Int,
        val contentColor: Int,
        val backgroundColor: Int,
        val showAppIcon: Boolean,
        val showTimestamp: Boolean,
        val padding: Float,
        val spacing: Float,
    )'''

new3 = '''    data class RenderConfig(
        val title: String,
        val subtitle: String,
        val content: String,
        val titleFontSize: Float,
        val subtitleFontSize: Float,
        val contentFontSize: Float,
        val titleColor: Int,
        val subtitleColor: Int,
        val contentColor: Int,
        val backgroundColor: Int,
        val showAppIcon: Boolean,
        val showTimestamp: Boolean,
        val cameraAvoidance: Boolean = false,
        val padding: Float,
        val spacing: Float,
        val contentOffset: Float = 0f,
    )'''

content = content.replace(old3, new3, 1)

# Update NotificationRenderView to use contentOffset for drawing
# Find the onDraw method and add contentOffset to all x coordinates
old4 = '''        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)

            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0 || h <= 0) return'''

new4 = '''        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)

            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0 || h <= 0) return
            val ox = config.contentOffset  // 摄像头避开偏移'''

content = content.replace(old4, new4, 1)

# Update the title drawing to use ox offset
# Find "canvas.drawText(config.title" in onDraw
old5 = '''            if (config.showAppIcon) {
                val iconLeft = p
                val iconTop = y'''

new5 = '''            if (config.showAppIcon) {
                val iconLeft = p + ox
                val iconTop = y'''

content = content.replace(old5, new5, 1)

# Update the non-icon title
old6 = '''                canvas.drawText(config.title, p, y + config.titleFontSize, titlePaint)
                y += config.titleFontSize + s
            }

            // ── 副标题 ──
            if (config.subtitle.isNotEmpty()) {
                canvas.drawText(config.subtitle, p, y + config.subtitleFontSize, subtitlePaint)'''

new6 = '''                canvas.drawText(config.title, p + ox, y + config.titleFontSize, titlePaint)
                y += config.titleFontSize + s
            }

            // ── 副标题 ──
            if (config.subtitle.isNotEmpty()) {
                canvas.drawText(config.subtitle, p + ox, y + config.subtitleFontSize, subtitlePaint)'''

content = content.replace(old6, new6, 1)

# Update content text
old7 = '''            val contentText = fitText(config.content, contentPaint, maxWidth, h - y - p)
            canvas.drawText(contentText, p, y + config.contentFontSize, contentPaint)'''

new7 = '''            val contentText = fitText(config.content, contentPaint, maxWidth - ox, h - y - p)
            canvas.drawText(contentText, p + ox, y + config.contentFontSize, contentPaint)'''

content = content.replace(old7, new7, 1)

with open(r'E:\MSRR\fbs\android\app\src\main\kotlin\com\example\fbs\service\BackScreenNotificationActivity.kt', 'w', encoding='utf-8') as f:
    f.write(content)

print('Camera avoidance + style extras added')
