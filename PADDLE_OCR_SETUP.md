# PaddleOCR-Lite 集成指南

## 一、下载所需文件

### 1. 下载PaddleOCR项目（包含SDK和模型）

```bash
# 克隆PaddleOCR项目
git clone https://github.com/PaddlePaddle/PaddleOCR.git
cd PaddleOCR/deploy/ppocr-android
```

### 2. 构建AAR包

```bash
# 编译SDK模块为AAR
./gradlew :ppocr-sdk:assembleRelease
```

AAR输出位置：`ppocr-sdk/build/outputs/aar/ppocr-sdk-release.aar`

### 3. 下载模型文件

从HuggingFace下载PP-OCRv6_small模型：

```bash
# 创建模型目录
mkdir -p ppocr-sdk/src/main/assets/models/det
mkdir -p ppocr-sdk/src/main/assets/models/rec

# 下载检测模型
wget https://huggingface.co/PaddlePaddle/PP-OCRv6_small_det_onnx/resolve/main/inference.onnx \
  -O ppocr-sdk/src/main/assets/models/det/inference.onnx

# 下载识别模型
wget https://huggingface.co/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/main/inference.onnx \
  -O ppocr-sdk/src/main/assets/models/rec/inference.onnx

wget https://huggingface.co/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/main/inference.yml \
  -O ppocr-sdk/src/main/assets/models/rec/inference.yml
```

## 二、复制文件到项目

### 1. 复制AAR文件

```bash
# 将AAR复制到项目的libs目录
cp ppocr-sdk/build/outputs/aar/ppocr-sdk-release.aar \
  E:\MSRR\fbs\android\app\libs\
```

### 2. 复制模型文件

```bash
# 创建assets目录
mkdir -p E:\MSRR\fbs\android\app\src\main\assets\models\det
mkdir -p E:\MSRR\fbs\android\app\src\main\assets\models\rec

# 复制模型文件
cp ppocr-sdk/src/main/assets/models/det/inference.onnx \
  E:\MSRR\fbs\android\app\src\main\assets\models\det\

cp ppocr-sdk/src/main/assets/models/rec/inference.onnx \
  E:\MSRR\fbs\android\app\src\main\assets\models\rec\

cp ppocr-sdk/src/main/assets/models/rec/inference.yml \
  E:\MSRR\fbs\android\app\src\main\assets\models\rec\
```

## 三、最终文件结构

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
        ├── MainActivity.kt (已修改)
        └── service\
            └── NativeOcrService.kt (新增)
```

## 四、验证安装

1. 确保AAR文件在 `android/app/libs/` 目录下
2. 确保模型文件在 `android/app/src/main/assets/models/` 目录下
3. 运行 `flutter pub get`
4. 运行 `flutter build apk --debug` 测试编译

## 五、常见问题

### Q1: 编译报错 "Could not find ppocr-sdk-release.aar"
- 检查AAR文件是否在正确的目录下
- 确保文件名完全匹配

### Q2: 运行时崩溃 "Model not found"
- 检查assets目录结构是否正确
- 确保模型文件完整（不是空文件）

### Q3: OCR识别速度慢
- 首次加载模型需要时间（约500ms）
- 后续识别应该在300-500ms内完成
- 确保在后台线程执行，不阻塞UI

## 六、API使用示例

```kotlin
// 在NativeOcrService.kt中使用
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
