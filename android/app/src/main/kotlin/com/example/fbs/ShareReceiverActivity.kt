package com.example.fbs

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File

/**
 * 透明 Activity，接收系统复制菜单 (PROCESS_TEXT) 和分享菜单 (SEND) 的 Intent。
 * 收到后将数据转发给 MainActivity 的 MethodChannel，然后立即 finish()。
 */
class ShareReceiverActivity : Activity() {

    companion object {
        private const val TAG = "ShareReceiver"
        /** MainActivity 需要在 configureFlutterEngine 后设置此回调 */
        var onSharedContent: ((type: String, text: String?, imageUri: String?) -> Unit)? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        finish()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
        finish()
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return

        when (action) {
            Intent.ACTION_PROCESS_TEXT -> {
                val text = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
                if (!text.isNullOrBlank()) {
                    Log.d(TAG, "PROCESS_TEXT: ${text.take(100)}")
                    // 启动 MainActivity 并传递数据
                    launchMainActivity(type = "text", text = text)
                }
            }
            Intent.ACTION_SEND -> {
                val mimeType = intent.type ?: ""
                if (mimeType.startsWith("image/")) {
                    val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                    if (uri != null) {
                        Log.d(TAG, "SEND image: $uri")
                        // 复制到缓存目录（避免URI权限在异步OCR时过期）
                        val cachedUri = copyToCache(uri)
                        launchMainActivity(type = "image", imageUri = cachedUri?.toString() ?: uri.toString())
                    }
                } else {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                    if (!text.isNullOrBlank()) {
                        Log.d(TAG, "SEND text: ${text.take(100)}")
                        launchMainActivity(type = "text", text = text)
                    }
                }
            }
        }
    }

    private fun launchMainActivity(
        type: String,
        text: String? = null,
        imageUri: String? = null,
    ) {
        // 优先通过静态回调传递（如果 MainActivity 已启动）
        if (onSharedContent != null) {
            onSharedContent?.invoke(type, text, imageUri)
            return
        }

        // 否则启动 MainActivity 并带上 extras
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_SEND
            putExtra("share_type", type)
            text?.let { putExtra("share_text", it) }
            imageUri?.let { putExtra("share_image_uri", it) }
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(launchIntent)
    }

    /**
     * 将URI指向的图片复制到应用缓存目录，返回FileProvider content:// URI。
     * 避免URI临时权限在异步OCR识别时过期。
     */
    private fun copyToCache(uri: Uri): Uri? {
        return try {
            val tempFile = File(cacheDir, "shared_images")
            tempFile.mkdirs()
            val dest = File(tempFile, "img_${System.currentTimeMillis()}.png")

            if (uri.scheme == "file") {
                // file:// URI — 直接读取文件路径
                val src = File(uri.path!!)
                if (!src.exists()) return null
                src.inputStream().use { it.copyTo(dest.outputStream()) }
            } else {
                // content:// URI — 通过 ContentResolver（需要URI权限处于活动状态）
                val inputStream = contentResolver.openInputStream(uri) ?: return null
                inputStream.use { it.copyTo(dest.outputStream()) }
            }

            Log.d(TAG, "Cached to: $dest (${dest.length()} bytes)")
            FileProvider.getUriForFile(this, "$packageName.fileprovider", dest)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to cache image", e)
            null
        }
    }
}
