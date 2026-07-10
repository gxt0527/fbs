@echo off
REM PaddleOCR-Lite 文件下载脚本 (Windows)

echo ========================================
echo PaddleOCR-Lite 集成文件准备脚本
echo ========================================

REM 创建临时目录
if not exist "temp_ocr" mkdir temp_ocr
cd temp_ocr

echo.
echo [1/4] 下载模型文件...

REM 创建模型目录
if not exist "models\det" mkdir models\det
if not exist "models\rec" mkdir models\rec

REM 下载检测模型 (使用PowerShell)
echo 下载检测模型...
powershell -Command "Invoke-WebRequest -Uri 'https://huggingface.co/PaddlePaddle/PP-OCRv6_small_det_onnx/resolve/main/inference.onnx' -OutFile 'models\det\inference.onnx'"

REM 下载识别模型
echo 下载识别模型...
powershell -Command "Invoke-WebRequest -Uri 'https://huggingface.co/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/main/inference.onnx' -OutFile 'models\rec\inference.onnx'"

REM 下载识别配置
echo 下载识别配置...
powershell -Command "Invoke-WebRequest -Uri 'https://huggingface.co/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/main/inference.yml' -OutFile 'models\rec\inference.yml'"

echo.
echo [2/4] 复制模型文件到项目...

REM 复制模型文件
xcopy /E /Y "models" "..\..\android\app\src\main\assets\models"

echo.
echo [3/4] 清理临时文件...
cd ..
rmdir /S /Q temp_ocr

echo.
echo [4/4] 完成！
echo.
echo ========================================
echo 模型文件已复制到：
echo android\app\src\main\assets\models\
echo ========================================
echo.
echo 接下来请：
echo 1. 从PaddleOCR项目构建AAR包
echo 2. 将AAR复制到 android\app\libs\ 目录
echo 3. 运行 flutter pub get
echo 4. 运行 flutter build apk --debug 测试
echo ========================================
pause
