# PaddleOCR-Lite 替代下载方案

## 方案1：使用 Gitee 镜像（推荐）

```bash
# 从 Gitee 镜像克隆（国内加速）
git clone https://gitee.com/paddlepaddle/PaddleOCR.git

# 进入 Android SDK 目录
cd PaddleOCR/deploy/ppocr-android

# 构建 AAR
./gradlew :ppocr-sdk:assembleRelease

# AAR 输出位置
# ppocr-sdk/build/outputs/aar/ppocr-sdk-release.aar
```

## 方案2：使用第三方预编译 AAR

如果无法克隆仓库，可以使用以下预编译库：

### 选项 A：paddleocr4android

GitHub: https://github.com/equationl/paddleocr4android

```gradle
// 在 settings.gradle.kts 添加
include(":paddleocr4android")

// 在 app/build.gradle.kts 添加
implementation(project(":paddleocr4android"))
```

### 选项 B：使用 ONNX Runtime 直接集成

如果不需要完整的 PaddleOCR SDK，可以只使用 ONNX Runtime：

```gradle
dependencies {
    // 只需要 ONNX Runtime
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.21.1")
    implementation("com.quickbirdstudios:opencv:4.5.3")
}
```

然后手动实现 OCR 推理逻辑。

## 方案3：使用 ML Kit（Google 官方）

如果对 PaddleOCR 没有硬性要求，可以使用 Google ML Kit：

```gradle
dependencies {
    // Google ML Kit 文字识别
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}
```

优点：
- Google 官方维护
- 无需下载模型文件
- 自动更新
- 中文支持好

缺点：
- 需要 Google Play Services
- 不是完全离线

## 方案4：使用 Tesseract.js（纯 Dart 实现）

如果不想使用原生代码，可以使用纯 Dart 实现：

```yaml
# pubspec.yaml
dependencies:
  tesseract_ocr: ^0.3.0
```

优点：
- 纯 Dart 实现
- 无需原生代码
- 跨平台

缺点：
- 性能较差
- 中文支持有限

## 推荐方案

**最佳方案**：使用 Gitee 镜像克隆 PaddleOCR 项目

**快速方案**：使用 Google ML Kit

**离线方案**：手动下载模型文件 + 使用 ONNX Runtime

## 模型文件直链下载

如果只需要模型文件，可以使用以下直链：

### PP-OCRv6_small 模型

```bash
# 检测模型
wget https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv6_small_det_onnx_infer.tar

# 识别模型
wget https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv6_small_rec_onnx_infer.tar
```

### 解压后文件结构

```
PP-OCRv6_small_det_onnx_infer/
└── inference.onnx

PP-OCRv6_small_rec_onnx_infer/
├── inference.onnx
└── inference.yml
```

### 复制到项目

```
android/app/src/main/assets/models/
├── det/
│   └── inference.onnx
└── rec/
    ├── inference.onnx
    └── inference.yml
```

## 快速测试

下载模型后，运行以下命令测试：

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
