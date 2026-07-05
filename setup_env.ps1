# FBS Development Environment Setup Script
# Run this script as Administrator for best results

$ErrorActionPreference = "Stop"

Write-Host "=== FBS 开发环境初始化 ===" -ForegroundColor Cyan

# ---------- 1. Java JDK 17 ----------
$javaHome = "D:\jdk17\jdk-17.0.2"
if (-not (Test-Path "$javaHome\bin\java.exe")) {
    Write-Host "[1/4] JDK 17 未安装，请手动下载并解压:" -ForegroundColor Yellow
    Write-Host "  下载地址: https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_windows-x64_bin.zip" -ForegroundColor Yellow
    Write-Host "  解压到: D:\jdk17\jdk-17.0.2" -ForegroundColor Yellow
} else {
    Write-Host "[1/4] JDK 17 已安装: $javaHome" -ForegroundColor Green
}

# ---------- 2. Flutter SDK ----------
$flutterPath = "C:\flutter"
$flutterBin = "$flutterPath\bin\flutter.bat"
if (-not (Test-Path $flutterBin)) {
    Write-Host "[2/4] Flutter SDK 未安装，请手动下载并解压:" -ForegroundColor Yellow
    Write-Host "  下载地址: https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.44.4-stable.zip" -ForegroundColor Yellow
    Write-Host "  解压到: C:\flutter" -ForegroundColor Yellow
} else {
    Write-Host "[2/4] Flutter SDK 已安装" -ForegroundColor Green
}

# ---------- 3. Android SDK ----------
$androidSdk = "C:\Android\Sdk"
$sdkManager = "$androidSdk\cmdline-tools\latest\bin\sdkmanager.bat"

if ((Test-Path "$javaHome\bin\java.exe") -and (Test-Path $sdkManager)) {
    Write-Host "[3/4] 使用 sdkmanager 安装 Android SDK 组件..." -ForegroundColor Cyan
    $env:JAVA_HOME = $javaHome
    $env:Path = "$javaHome\bin;$env:Path"

    & $sdkManager --install "platforms;android-36" "platforms;android-37" "build-tools;37.0.0" "platform-tools" 2>&1
    & $sdkManager --licenses 2>&1

    # 修复 VS Code avdmanager 警告
    $toolsBin = "$androidSdk\tools\bin"
    if (-not (Test-Path "$toolsBin\avdmanager.bat")) {
        New-Item -ItemType Directory -Path $toolsBin -Force | Out-Null
        Copy-Item "$androidSdk\cmdline-tools\latest\bin\avdmanager.bat" "$toolsBin\avdmanager.bat"
        Write-Host "  已复制 avdmanager.bat 到 tools\bin\" -ForegroundColor Green
    }

    Write-Host "[3/4] Android SDK 组件安装完成" -ForegroundColor Green
} else {
    Write-Host "[3/4] sdkmanager 不可用（缺少 JDK 17 或 cmdline-tools）" -ForegroundColor Yellow
}

# ---------- 4. Flutter config ----------
Write-Host "[4/4] 配置 Flutter..." -ForegroundColor Cyan
& "$flutterPath\bin\flutter.bat" config --android-sdk $androidSdk 2>&1
& "$flutterPath\bin\flutter.bat" config --no-analytics 2>&1

# ---------- 5. VS Code 扩展 ----------
$vscodeExts = @("dart-code.dart-code", "dart-code.flutter")
foreach ($ext in $vscodeExts) {
    $check = & code --list-extensions 2>&1 | Select-String $ext
    if (-not $check) {
        Write-Host "  安装 VS Code 扩展: $ext" -ForegroundColor Yellow
        & code --install-extension $ext 2>&1
    }
}

Write-Host ""
Write-Host "=== 环境初始化完成 ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "请重新打开终端，然后运行以下命令验证:" -ForegroundColor White
Write-Host "  flutter --version      # 应显示 3.44.4" -ForegroundColor Yellow
Write-Host "  java -version          # 应显示 openjdk 17.0.2" -ForegroundColor Yellow
Write-Host "  flutter doctor         # 检查环境" -ForegroundColor Yellow
Write-Host "  flutter pub get        # 获取依赖" -ForegroundColor Yellow
Write-Host "  flutter run            # 编译运行" -ForegroundColor Yellow
