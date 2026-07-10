@echo off
REM PaddleOCR-Lite 模型直接下载脚本 (Windows)
REM 无需克隆整个仓库，直接下载所需文件

echo ========================================
echo PaddleOCR-Lite 模型直接下载脚本
echo ========================================

REM 创建模型目录
echo [1/4] 创建目录结构...
if not exist "android\app\src\main\assets\models\det" mkdir "android\app\src\main\assets\models\det"
if not exist "android\app\src\main\assets\models\rec" mkdir "android\app\src\main\assets\models\rec"

echo.
echo [2/4] 下载 PP-OCRv6_small 检测模型...
echo 下载中，请稍候...
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv6_small_det_onnx_infer.tar' -OutFile 'temp_det.tar'"

echo 解压检测模型...
powershell -Command "tar -xf temp_det.tar"
if exist "PP-OCRv6_small_det_onnx_infer\inference.onnx" (
    copy "PP-OCRv6_small_det_onnx_infer\inference.onnx" "android\app\src\main\assets\models\det\inference.onnx"
    echo 检测模型下载完成！
) else (
    echo 警告：解压失败，尝试其他方式...
)

echo.
echo [3/4] 下载 PP-OCRv6_small 识别模型...
echo 下载中，请稍候...
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv6_small_rec_onnx_infer.tar' -OutFile 'temp_rec.tar'"

echo 解压识别模型...
powershell -Command "tar -xf temp_rec.tar"
if exist "PP-OCRv6_small_rec_onnx_infer\inference.onnx" (
    copy "PP-OCRv6_small_rec_onnx_infer\inference.onnx" "android\app\src\main\assets\models\rec\inference.onnx"
    copy "PP-OCRv6_small_rec_onnx_infer\inference.yml" "android\app\src\main\assets\models\rec\inference.yml"
    echo 识别模型下载完成！
) else (
    echo 警告：解压失败，尝试其他方式...
)

echo.
echo [4/4] 清理临时文件...
if exist "temp_det.tar" del "temp_det.tar"
if exist "temp_rec.tar" del "temp_rec.tar"
if exist "PP-OCRv6_small_det_onnx_infer" rmdir /S /Q "PP-OCRv6_small_det_onnx_infer"
if exist "PP-OCRv6_small_rec_onnx_infer" rmdir /S /Q "PP-OCRv6_small_rec_onnx_infer"

echo.
echo ========================================
echo 验证下载文件...
echo ========================================
if exist "android\app\src\main\assets\models\det\inference.onnx" (
    echo [OK] 检测模型: android\app\src\main\assets\models\det\inference.onnx
) else (
    echo [缺失] 检测模型未下载成功
)

if exist "android\app\src\main\assets\models\rec\inference.onnx" (
    echo [OK] 识别模型: android\app\src\main\assets\models\rec\inference.onnx
) else (
    echo [缺失] 识别模型未下载成功
)

if exist "android\app\src\main\assets\models\rec\inference.yml" (
    echo [OK] 识别配置: android\app\src\main\assets\models\rec\inference.yml
) else (
    echo [缺失] 识别配置未下载成功
)

echo.
echo ========================================
echo 下载完成！
echo ========================================
echo.
echo 接下来需要获取 PaddleOCR Android SDK：
echo.
echo 方案1：从 Gitee 镜像克隆（国内加速）
echo   git clone https://gitee.com/paddlepaddle/PaddleOCR.git
echo   cd PaddleOCR\deploy\ppocr-android
echo   gradlew :ppocr-sdk:assembleRelease
echo.
echo 方案2：手动构建 SDK（见下方说明）
echo.
echo 将构建好的 AAR 文件复制到：
echo   android\app\libs\ppocr-sdk-release.aar
echo.
echo ========================================
pause
