package com.example.fbs.service

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import com.paddle.ocr.EngineConfig
import com.paddle.ocr.PaddleOCR
import com.paddle.ocr.PaddleOCRConfig
import com.paddle.ocr.util.OpenCVUtils
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * PaddleOCR-Lite 单例服务
 * - 单例初始化，不重复加载模型
 * - 后台子线程识别，绝不阻塞UI
 */
class NativeOcrService private constructor() {

    companion object {
        private const val TAG = "NativeOcr"
        private var instance: NativeOcrService? = null
        private var ocr: PaddleOCR? = null
        private var isInitialized = false

        fun getInstance(): NativeOcrService {
            return instance ?: synchronized(this) {
                instance ?: NativeOcrService().also { instance = it }
            }
        }
    }

    /**
     * 初始化OCR引擎（单例，不重复加载）
     * 必须在应用启动时调用一次
     */
    suspend fun init(context: Context) {
        if (isInitialized) {
            Log.d(TAG, "OCR already initialized, skipping")
            return
        }

        withContext(Dispatchers.IO) {
            try {
                // 初始化OpenCV
                OpenCVUtils.init(context)

                // 创建OCR实例 - 使用PP-OCRv6默认配置
                ocr = PaddleOCR.create(
                    context = context,
                    config = PaddleOCRConfig(),
                    engineConfig = EngineConfig(),
                    detModelAssetPath = "models/det/inference.onnx",
                    recModelAssetPath = "models/rec/inference.onnx",
                    recConfigAssetPath = "models/rec/inference.yml",
                )
                isInitialized = true
                Log.d(TAG, "OCR engine initialized successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize OCR engine", e)
                isInitialized = false
            }
        }
    }

    /**
     * 后台线程识别图片文字
     * @param context Context
     * @param imageUri 图片URI字符串 (content://...)
     * @return OcrResult 识别结果
     */
    suspend fun recognizeText(context: Context, imageUri: String): OcrResult {
        return withContext(Dispatchers.IO) {
            try {
                if (!isInitialized || ocr == null) {
                    return@withContext OcrResult(
                        success = false,
                        errorMessage = "OCR引擎未初始化"
                    )
                }

                val uri = Uri.parse(imageUri)
                val bitmap = if (uri.scheme == "file") {
                    BitmapFactory.decodeFile(uri.path)
                } else {
                    context.contentResolver.openInputStream(uri)?.use { stream ->
                        BitmapFactory.decodeStream(stream)
                    }
                }
                if (bitmap == null) {
                    return@withContext OcrResult(
                        success = false,
                        errorMessage = "无法打开图片URI"
                    )
                }

                Log.d(TAG, "Image loaded: ${bitmap.width}x${bitmap.height}")

                // 执行OCR识别，完毕后立即回收Bitmap释放内存
                val startTime = System.currentTimeMillis()
                var ocrResult: OcrResult
                try {
                    val result = ocr?.recognize(bitmap)
                    val totalTime = System.currentTimeMillis() - startTime

                    ocrResult = if (result != null && result.results.isNotEmpty()) {
                        val textLines = result.results.map { it.text }
                        val fullText = textLines.joinToString("\n")
                        Log.d(TAG, "OCR completed: ${result.lineCount} lines, " +
                                "det=${result.detectionTimeMs}ms, rec=${result.recognitionTimeMs}ms")
                        OcrResult(
                            success = true, text = fullText,
                            lineCount = result.lineCount,
                            detectionTimeMs = result.detectionTimeMs,
                            recognitionTimeMs = result.recognitionTimeMs,
                            totalTimeMs = totalTime,
                        )
                    } else {
                        OcrResult(success = false, errorMessage = "未识别到文字")
                    }
                } finally {
                    bitmap.recycle()
                }
                return@withContext ocrResult
            } catch (e: Exception) {
                Log.e(TAG, "OCR recognition failed", e)
                OcrResult(
                    success = false,
                    errorMessage = "识别失败: ${e.message}"
                )
            }
        }
    }

    /**
     * 释放资源
     * 在应用退出时调用
     */
    suspend fun release() {
        withContext(Dispatchers.IO) {
            try {
                ocr?.release()
                ocr = null
                isInitialized = false
                Log.d(TAG, "OCR engine released")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to release OCR engine", e)
            }
        }
    }
}

/**
 * OCR识别结果数据类
 */
data class OcrResult(
    val success: Boolean,
    val text: String = "",
    val lineCount: Int = 0,
    val detectionTimeMs: Long = 0,
    val recognitionTimeMs: Long = 0,
    val totalTimeMs: Long = 0,
    val errorMessage: String = "",
)
