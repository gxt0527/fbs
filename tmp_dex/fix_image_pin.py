import re

with open(r'E:\MSRR\fbs\android\app\src\main\kotlin\com\example\fbs\service\BackScreenController.kt', 'r', encoding='utf-8') as f:
    content = f.read()

# Find and replace displayImageOnBackScreen method
old = '''    /** 渲染内容并发送图片到背屏 */
    fun displayImageOnBackScreen(imagePath: String, title: String) {
        val now = System.currentTimeMillis()
        if (now - lastForwardTime < GLOBAL_COOLDOWN_MS) return
        lastForwardTime = now

        if (!isShizukuRunning() || !hasPermission()) return

        try {
            execShizukuShell("input keyevent KEYCODE_WAKEUP; input keyevent KEYCODE_WAKEUP")
            execShizukuShell("dumpsys deviceidle disable")

            val intent = android.content.Intent(context, Class.forName("com.example.fbs.service.BackScreenNotificationActivity")).apply {
                putExtra("imagePath", imagePath)
                putExtra("title", title)
                putExtra("isImageMode", "true")
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            Thread.sleep(500)

            val taskId = getOurTaskId()
            if (taskId > 0) {
                execShizukuShell("service call activity_task 50 i32 $taskId i32 1; am force-stop $SUBSCREEN_PACKAGE; input keyevent KEYCODE_WAKEUP")
            }

            Thread {
                try { Thread.sleep(500); execShizukuShell("am force-stop $SUBSCREEN_PACKAGE") }
                catch (_: Exception) {}
            }.start()
        } catch (e: Exception) {
            Log.e(TAG, "displayImageOnBackScreen failed", e)
        }
    }

    /** Canvas 文本换'''

new = '''    /**
     * 图片贴背屏 — 走官方 PinReceiveActivity（无需 Shizuku）
     * 流程: 渲染通知 → Bitmap → PNG → FileProvider URI → ACTION_SEND image/png → PinReceiveActivity
     */
    fun renderAndPinImage(title: String, subtitle: String, content: String): String {
        return try {
            val w = 976; val h = 596; val p = 48f; val density = 3.0f
            val titleSize = 28f * density; val bodySize = 16f * density

            val bitmap = android.graphics.Bitmap.createBitmap(w, h, android.graphics.Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bitmap)

            canvas.drawColor(android.graphics.Color.parseColor("#1A1A1E"))

            val titlePaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.WHITE; textSize = titleSize
                typeface = android.graphics.Typeface.DEFAULT_BOLD
            }
            val bodyPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.parseColor("#BBBBBB"); textSize = bodySize
            }

            var y = p
            canvas.drawText(title.take(30), p, y + titleSize, titlePaint)
            y += titleSize + 14f * density

            if (subtitle.isNotEmpty()) {
                canvas.drawText(subtitle.take(40), p, y + bodySize, bodyPaint)
                y += bodySize + 10f * density
            }

            val maxWidth = w - p * 2f
            for (line in wrapText(content, bodyPaint, maxWidth)) {
                canvas.drawText(line, p, y + bodySize, bodyPaint)
                y += bodySize + 4f * density
            }

            val wmPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.parseColor("#555555"); textSize = 11f * density
            }
            canvas.drawText("FBS ${java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date())}", p, h - p, wmPaint)

            val file = java.io.File(context.cacheDir, "fbs_pin.png")
            java.io.FileOutputStream(file).use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, it) }
            bitmap.recycle()

            val uri = androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
            context.grantUriPermission(SUBSCREEN_PACKAGE, uri, android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)

            val intent = android.content.Intent().apply {
                setClassName(SUBSCREEN_PACKAGE, "${SUBSCREEN_PACKAGE}.pin.PinReceiveActivity")
                action = android.content.Intent.ACTION_SEND
                type = "image/png"
                putExtra(android.content.Intent.EXTRA_STREAM, uri)
                putExtra(android.content.Intent.EXTRA_TEXT, "$title $content")
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)
            Log.d(TAG, "Image pinned to back screen: ${file.length()} bytes")
            "ok"
        } catch (e: Exception) {
            Log.e(TAG, "renderAndPinImage failed", e)
            "failed: ${e.message}"
        }
    }

    /** Canvas 文本换'''

content = content.replace(old, new, 1)
with open(r'E:\MSRR\fbs\android\app\src\main\kotlin\com\example\fbs\service\BackScreenController.kt', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
