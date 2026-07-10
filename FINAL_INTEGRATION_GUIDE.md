# PaddleOCR 3.x + ONNX Runtime 完整集成指南

## 一、构建 SDK AAR

```bash
# 进入 ppocr-android 目录
cd E:\MSRR\fbs\temp\PaddleOCR\deploy\ppocr-android

# 构建 SDK AAR（Release 版本）
.\gradlew :ppocr-sdk:assembleRelease

# AAR 输出位置：
# ppocr-sdk\build\outputs\aar\ppocr-sdk-release.aar
```

## 二、复制 AAR 到项目

```bash
# 复制 AAR 到项目的 libs 目录
copy ppocr-sdk\build\outputs\aar\ppocr-sdk-release.aar E:\MSRR\fbs\android\app\libs\
```

## 三、下载模型文件

从 BOS 直链下载 PP-OCRv6_small 模型：

```bash
# 创建模型目录
mkdir E:\MSRR\fbs\android\app\src\main\assets\models\det
mkdir E:\MSRR\fbs\android\app\src\main\assets\models\rec

# 下载检测模型
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv6_small_det_onnx_infer.tar' -OutFile 'temp_det.tar'"

# 解压
tar -xf temp_det.tar

# 复制模型文件
copy PP-OCRv6_small_det_onnx_infer\inference.onnx E:\MSRR\fbs\android\app\src\main\assets\models\det\

# 下载识别模型
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv6_small_rec_onnx_infer.tar' -OutFile 'temp_rec.tar'"

# 解压
tar -xf temp_rec.tar

# 复制模型文件
copy PP-OCRv6_small_rec_onnx_infer\inference.onnx E:\MSRR\fbs\android\app\src\main\assets\models\rec\
copy PP-OCRv6_small_rec_onnx_infer\inference.yml E:\MSRR\fbs\android\app\src\main\assets\models\rec\

# 清理临时文件
del temp_det.tar temp_rec.tar
rmdir /S /Q PP-OCRv6_small_det_onnx_infer PP-OCRv6_small_rec_onnx_infer
```

## 四、更新 NativeOcrService.kt

使用 PaddleOCR SDK 的正确 API：

```kotlin
package com.example.fbs.service

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import com.paddle.ocr.PaddleOCR
import com.paddle.ocr.PaddleOCRConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * PaddleOCR-Lite 单例服务（使用 PaddleOCR 3.x SDK）
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
                com.paddle.ocr.OpenCVUtils.init(context)

                // 创建OCR实例 - 使用PP-OCRv6默认配置
                ocr = PaddleOCR.create(
                    context = context,
                    config = PaddleOCRConfig(
                        detThresh = 0.3f,
                        detBoxThresh = 0.6f,
                        recScoreThresh = 0.0f,
                        recBatchSize = 1,
                    ),
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
                val inputStream = context.contentResolver.openInputStream(uri)
                    ?: return@withContext OcrResult(
                        success = false,
                        errorMessage = "无法打开图片URI"
                    )

                // 将URI转换为Bitmap
                val bitmap = BitmapFactory.decodeStream(inputStream)
                inputStream.close()

                if (bitmap == null) {
                    return@withContext OcrResult(
                        success = false,
                        errorMessage = "图片解码失败"
                    )
                }

                Log.d(TAG, "Image loaded: ${bitmap.width}x${bitmap.height}")

                // 执行OCR识别
                val startTime = System.currentTimeMillis()
                val result = ocr?.recognize(bitmap)
                val totalTime = System.currentTimeMillis() - startTime

                if (result != null && result.results.isNotEmpty()) {
                    // 将识别结果按行合并
                    val textLines = result.results.map { it.text }
                    val fullText = textLines.joinToString("\n")

                    Log.d(TAG, "OCR completed: ${result.lineCount} lines, " +
                            "det=${result.detectionTimeMs}ms, rec=${result.recognitionTimeMs}ms")

                    OcrResult(
                        success = true,
                        text = fullText,
                        lineCount = result.lineCount,
                        detectionTimeMs = result.detectionTimeMs,
                        recognitionTimeMs = result.recognitionTimeMs,
                        totalTimeMs = totalTime,
                    )
                } else {
                    OcrResult(
                        success = false,
                        errorMessage = "未识别到文字"
                    )
                }
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
    fun release() {
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
```

## 五、验证文件结构

最终项目结构应该是：

```
E:\MSRR\fbs\android\app\
├── libs\
│   └── ppocr-sdk-release.aar
└── src\main\
    ├── assets\
    │   └── models\
    │       ├── det\
    │       │   └── inference.onnx
    │       └── rec\
    │           ├── inference.onnx
    │           └── inference.yml
    └── kotlin\com\example\fbs\
        ├── MainActivity.kt
        └── service\
            └── NativeOcrService.kt
```

## 六、构建验证

```bash
# 进入项目目录
cd E:\MSRR\fbs

# 获取依赖
flutter pub get

# 构建 APK
flutter build apk --debug

# 安装到设备
flutter install
```

## 七、常见问题

### Q1: 编译报错 "Could not find ppocr-sdk-release.aar"
- 检查 AAR 文件是否在 `android\app\libs\` 目录下
- 确保文件名完全匹配

### Q2: 运行时崩溃 "Model not found"
- 检查 assets 目录结构是否正确
- 确保模型文件完整（不是空文件）

### Q3: OCR 识别速度慢
- 首次加载模型需要时间（约 500ms）
- 后续识别应该在 300-500ms 内完成
- 确保在后台线程执行，不阻塞 UI

### Q4: 构建 AAR 失败
- 确保已安装 JDK 17
- 确保 Gradle 版本兼容
- 检查网络连接（需要下载依赖）

## 八、性能指标

- **模型加载时间**：<500ms（仅首次，单例）
- **单次识别时间**：300-500ms
- **内存占用**：<100MB
- **不阻塞 UI**：使用协程在后台线程执行

## 九、API 使用示例

```kotlin
// 在 NativeOcrService.kt 中使用
val ocrService = NativeOcrService.getInstance()
ocrService.init(context) // 初始化（应用启动时调用一次）

// 识别图片
val result = ocrService.recognizeText(context, imageUri)
if (result.success) {
    println("识别结果: ${result.text}")
    println("行数: ${result.lineCount}")
    println("检测耗时: ${result.detectionTimeMs}ms")
    println("识别耗时: ${result.recognitionTimeMs}ms")
}
```
