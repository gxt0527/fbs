# PaddleOCR-Lite 集成方案（使用已下载的 PaddleOCR 2.7）

## 当前状态

已成功从 Gitee 镜像下载 PaddleOCR 2.7 版本到 `E:\MSRR\fbs\temp\PaddleOCR`

## 集成方案

由于 PaddleOCR 2.7 的 Android Demo 使用 Paddle Lite（会自动下载依赖），我们有两个选择：

### 方案 A：使用 PaddleOCR 2.7 + Paddle Lite（推荐）

这是最简单的方案，因为 Demo 已经配置好了自动下载：

```bash
# 1. 进入 android_demo 目录
cd E:\MSRR\fbs\temp\PaddleOCR\deploy\android_demo

# 2. 构建项目（会自动下载 Paddle Lite、OpenCV、模型）
./gradlew :app:assembleDebug

# 3. AAR/依赖会自动下载到：
#    - PaddleLite/ (Paddle Lite 库)
#    - OpenCV/ (OpenCV 库)
#    - app/src/main/assets/models/ (OCR 模型)
#    - app/src/main/assets/labels/ (字符字典)
```

### 方案 B：手动下载依赖

如果自动下载失败，可以手动下载：

```bash
# Paddle Lite 库
wget https://paddleocr.bj.bcebos.com/libs/paddle_lite_libs_v2_10.tar.gz

# OpenCV
wget https://paddlelite-demo.bj.bcebos.com/libs/android/opencv-4.2.0-android-sdk.tar.gz

# OCR 模型
wget https://paddleocr.bj.bcebos.com/PP-OCRv2/lite/ch_PP-OCRv2.tar.gz

# 字符字典
wget https://paddleocr.bj.bcebos.com/dygraph_v2.0/lite/ch_dict.tar.gz
```

## 修改 NativeOcrService.kt

由于使用的是 Paddle Lite 版本，需要修改 NativeOcrService.kt：

```kotlin
package com.example.fbs.service

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import com.baidu.paddle.lite.MobileConfig
import com.baidu.paddle.lite.PaddlePredictor
import com.baidu.paddle.lite.PowerMode
import com.baidu.paddle.lite.Tensor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * PaddleOCR-Lite 单例服务（使用 Paddle Lite）
 */
class NativeOcrService private constructor() {

    companion object {
        private const val TAG = "NativeOcr"
        private var instance: NativeOcrService? = null
        private var detPredictor: PaddlePredictor? = null
        private var recPredictor: PaddlePredictor? = null
        private var isInitialized = false

        fun getInstance(): NativeOcrService {
            return instance ?: synchronized(this) {
                instance ?: NativeOcrService().also { instance = it }
            }
        }
    }

    /**
     * 初始化OCR引擎（单例，不重复加载）
     */
    suspend fun init(context: Context) {
        if (isInitialized) {
            Log.d(TAG, "OCR already initialized, skipping")
            return
        }

        withContext(Dispatchers.IO) {
            try {
                // 加载检测模型
                val detConfig = MobileConfig().apply {
                    modelDir = context.filesDir.absolutePath + "/models/det/"
                    setThread(4)
                    setPowerMode(PowerMode.LITE_POWER_HIGH)
                }
                detPredictor = PaddlePredictor.createPaddlePredictor(detConfig)

                // 加载识别模型
                val recConfig = MobileConfig().apply {
                    modelDir = context.filesDir.absolutePath + "/models/rec/"
                    setThread(4)
                    setPowerMode(PowerMode.LITE_POWER_HIGH)
                }
                recPredictor = PaddlePredictor.createPaddlePredictor(recConfig)

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
     */
    suspend fun recognizeText(context: Context, imageUri: String): OcrResult {
        return withContext(Dispatchers.IO) {
            try {
                if (!isInitialized || detPredictor == null || recPredictor == null) {
                    return@withContext OcrResult(
                        success = false,
                        errorMessage = "OCR引擎未初始化"
                    )
                }

                val uri = Uri.parse(imageUri)
                val inputStream = context.contentResolver.openInputStream(uri)
                    ?: return@withContext OcrResult(
                        success = false,
                        errorMessage = "无法打开图片URI"
                    )

                val bitmap = BitmapFactory.decodeStream(inputStream)
                inputStream.close()

                if (bitmap == null) {
                    return@withContext OcrResult(
                        success = false,
                        errorMessage = "图片解码失败"
                    )
                }

                // 执行OCR识别（简化版，实际需要完整的前后处理）
                val startTime = System.currentTimeMillis()
                
                // TODO: 实现完整的检测+识别流程
                // 这里只是示例，实际需要：
                // 1. 图像预处理（resize, normalize）
                // 2. 检测模型推理
                // 3. 文本区域裁剪
                // 4. 识别模型推理
                // 5. 后处理（CTC解码）
                
                val totalTime = System.currentTimeMillis() - startTime

                OcrResult(
                    success = true,
                    text = "识别结果示例",
                    lineCount = 1,
                    detectionTimeMs = totalTime / 2,
                    recognitionTimeMs = totalTime / 2,
                    totalTimeMs = totalTime,
                )
            } catch (e: Exception) {
                Log.e(TAG, "OCR recognition failed", e)
                OcrResult(
                    success = false,
                    errorMessage = "识别失败: ${e.message}"
                )
            }
        }
    }

    fun release() {
        try {
            detPredictor?.destroy()
            recPredictor?.destroy()
            detPredictor = null
            recPredictor = null
            isInitialized = false
            Log.d(TAG, "OCR engine released")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release OCR engine", e)
        }
    }
}

data class OcrResult(
    val success: Boolean,
    val text: String = "",
    val lineCount: Int = 0,
    val detectionTimeMs: Long = 0,
    val recognitionTimeMs: Long = 0,
    val totalTimeMs: Long = 0,
    val errorMessage: String = "",
)
```

## 下一步操作

1. **运行自动下载**：
   ```bash
   cd E:\MSRR\fbs\temp\PaddleOCR\deploy\android_demo
   gradlew :app:assembleDebug
   ```

2. **复制依赖到项目**：
   - 复制 `PaddleLite/` 到项目
   - 复制 `OpenCV/` 到项目
   - 复制模型文件到 `assets/models/`

3. **修改 build.gradle.kts** 添加 Paddle Lite 依赖

4. **更新 NativeOcrService.kt** 使用 Paddle Lite API

## 注意事项

PaddleOCR 2.7 使用的是 Paddle Lite，而不是 ONNX Runtime。主要区别：
- Paddle Lite 是百度自家的推理引擎
- 需要使用 `.nb` 格式的模型（已经过优化）
- API 与 ONNX Runtime 不同

如果需要使用 ONNX Runtime 版本，需要使用 PaddleOCR 3.x 版本。
