# FBS 开发环境 — 完整搭建清单

> 项目: FBS (Flutter Back Screen) — 通知转发工具
> 最后验证: 2026-07-06, `flutter build apk --debug` 编译成功，通知监听+应用列表过滤功能正常

---

## 1. 必需软件版本

| 组件 | 版本 | 用途 |
|------|------|------|
| Flutter SDK | 3.44.4 (Dart 3.12.2) | 框架 |
| JDK | **17** (OpenJDK 17.0.2) | Gradle/Android 编译 (**不能用 JDK 26，jlink 不兼容**) |
| Android SDK cmdline-tools | latest | sdkmanager |
| Android SDK Platform | android-36, android-37 | 编译目标 |
| Android Build Tools | 37.0.0 | APK 构建 |
| Android Platform Tools | latest | adb |
| Gradle | 9.1.0 (自动下载) | 构建系统 |
| Kotlin | 2.3.20 (AGP 内置) | Android 语言 |
| AGP (Android Gradle Plugin) | 9.0.1 | Android 构建插件 |
| Shizuku SDK | 13.1.5 | 权限管理 |
| VS Code | latest | IDE |
| VS Code 扩展 | dart-code.dart-code + dart-code.flutter | Dart/Flutter 支持 |

---

## 2. 目录结构 (Windows)

```
C:\flutter\                          ← Flutter SDK
C:\Android\Sdk\                      ← Android SDK
  cmdline-tools\latest\              ← sdkmanager
  platforms\android-36\              ← 平台 36
  platforms\android-37\              ← 平台 37
  build-tools\37.0.0\               ← 构建工具
  platform-tools\                    ← adb
  tools\bin\avdmanager.bat           ← 从 cmdline-tools 复制（修复 VS Code 警告）
D:\MSRR\fbs\                         ← 项目根目录
D:\jdk17\jdk-17.0.2\                ← OpenJDK 17.0.2（给 Gradle 用）
C:\Users\Admin\.gradle\              ← Gradle 缓存（自动创建）
```

---

## 3. 安装步骤（新电脑从零开始）

### 3.1 下载软件

| 软件 | 下载地址 |
|------|----------|
| Flutter 3.44.4 | `https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.44.4-stable.zip` |
| OpenJDK 17.0.2 | `https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_windows-x64_bin.zip` |
| Android cmdline-tools | `https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip` |

### 3.2 安装顺序

```powershell
# 1. 解压 Flutter 到 C:\flutter
# 2. 解压 JDK 17 到 D:\jdk17\jdk-17.0.2
# 3. 解压 cmdline-tools 到 C:\Android\Sdk\cmdline-tools\latest\

# 4. 设置环境变量（管理员 PowerShell）
[Environment]::SetEnvironmentVariable("JAVA_HOME", "D:\jdk17\jdk-17.0.2", "Machine")
[Environment]::SetEnvironmentVariable("ANDROID_HOME", "C:\Android\Sdk", "Machine")
[Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", "C:\Android\Sdk", "Machine")

# 5. 添加 PATH
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
$newPath = "$currentPath;C:\flutter\bin;C:\flutter\bin\mingit\mingw64\bin;D:\jdk17\jdk-17.0.2\bin;C:\Android\Sdk\platform-tools;C:\Android\Sdk\cmdline-tools\latest\bin"
[Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")

# 6. 配置 Flutter
flutter config --android-sdk C:\Android\Sdk
flutter config --no-analytics

# 7. 安装 Android SDK 组件
sdkmanager --install "platforms;android-36" "platforms;android-37" "build-tools;37.0.0" "platform-tools"
sdkmanager --licenses   # 全部 accept

# 8. 修复 VS Code avdmanager 警告
Copy-Item "C:\Android\Sdk\cmdline-tools\latest\bin\avdmanager.bat" "C:\Android\Sdk\tools\bin\avdmanager.bat"

# 9. VS Code 扩展
code --install-extension dart-code.dart-code
code --install-extension dart-code.flutter

# 10. 验证
flutter doctor
java -version   # 应显示 openjdk 17.0.2
```

---

## 4. 项目关键配置文件（换电脑后需确认）

### `android/local.properties`
```properties
sdk.dir=C:\\Android\\Sdk
flutter.sdk=C:\\flutter
flutter.buildMode=debug
flutter.versionName=1.0.0
flutter.versionCode=1
```

### `android/gradle.properties`
```properties
org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.text=ALL-UNNAMED --add-opens=java.desktop/java.awt.font=ALL-UNNAMED
android.useAndroidX=true
android.newDsl=false
android.builtInKotlin=false
kotlin.incremental=false
org.gradle.java.home=D:\\jdk17\\jdk-17.0.2
```

> **注意**: `org.gradle.java.home` 路径指向 JDK 17，如果 JDK 解压到不同位置需要修改。

### `android/settings.gradle.kts`
```kotlin
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}
```

### `android/app/build.gradle.kts` 关键片段
```kotlin
compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
defaultConfig {
    minSdk = 24
    targetSdk = 37
}
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
dependencies {
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
}
```

### `android/build.gradle.kts` 关键片段
```kotlin
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
    compilerOptions {
        freeCompilerArgs.add("-Xincremental-compilation=false")
    }
}
```

### `.vscode/settings.json`
```json
{
    "dart.flutterSdkPath": "C:\\flutter",
    "dart.sdkPath": "C:\\flutter\\bin\\cache\\dart-sdk",
    "git.path": "C:\\flutter\\bin\\mingit\\mingw64\\bin\\git.exe",
    "files.autoSave": "onFocusChange",
    "editor.formatOnSave": true
}
```

### `android/gradle/wrapper/gradle-wrapper.properties`
```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-9.1.0-all.zip
```

---

## 5. 构建命令

```powershell
# 每次打开终端需设置（或写入系统环境变量）
$env:JAVA_HOME = "D:\jdk17\jdk-17.0.2"
$env:Path = "D:\jdk17\jdk-17.0.2\bin;C:\flutter\bin;C:\Android\Sdk\cmdline-tools\latest\bin;C:\Android\Sdk\platform-tools;" + $env:Path

# 获取依赖
flutter pub get

# 运行（无线调试）
flutter run

# 构建 APK
flutter build apk --debug
flutter build apk --release

# 无线 ADB 连接（手机开启无线调试后）
adb pair <手机IP>:<配对端口>     # 输入配对码
adb connect <手机IP>:<连接端口>
flutter devices                  # 确认设备已识别
```

---

## 6. 已知坑 & 注意事项

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| `java.lang.ClassNotFoundException: java.util.concurrent.ConcurrentHashMap` | Kotlin daemon 与 JDK 26 不兼容 | `kotlin.incremental=false` + `--add-opens` flags |
| `JdkImageTransform` / `jlink.exe` 失败 | AGP 调用 jlink，JDK 26 的 jlink 无法处理 android-36 core-for-system-modules.jar | 使用 JDK 17（`org.gradle.java.home` 指向 JDK 17） |
| Gradle cache 删除失败 (IOException) | 上次构建的 daemon 占用文件锁 | `Get-Process java \| Stop-Process -Force`，等几秒再构建 |
| VS Code 警告 avdmanager 缺失 | Android SDK tools 目录无 avdmanager | 从 cmdline-tools 复制 `avdmanager.bat` |
| `flutter pub get` 超时 | 网络无法直连 Google | 使用中国镜像：`$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"` + `$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"` |
| PowerShell `curl`/`Invoke-WebRequest` 失败 | 无外网访问 | Java `HttpURLConnection` 和 `sdkmanager` 可正常联网 |

---

## 7. 设备连接

- **设备**: Xiaomi 2509FPN0BC (popsicle), Android 16 (API 36)
- **连接方式**: 无线 ADB (`adb connect <IP>:<端口>`)
- **首次配对**: `adb pair` + 配对码（手机无线调试页面获取）
- **已验证**: `flutter run` 编译部署成功

---

## 8. 快速验证清单（换电脑后逐项检查）

```powershell
flutter --version          # 应显示 3.44.4
java -version              # 应显示 openjdk 17.0.2
flutter doctor             # 除 Chrome/VS 外全绿
adb devices                # 显示已连接设备
flutter pub get            # 成功无报错
flutter run                # 编译部署成功
```

---

## 9. 开发日志

### 2026-07-06 通知监听应用列表过滤

**需求：**
- 在设置页控制哪些应用的通知需要监听转发
- 应用列表包含用户应用和系统应用，分两组可折叠显示
- "全部消息"开关控制消息类型：开启=所有类型，关闭=仅焦点/实时动态
- 应用列表开关始终生效

**改动文件：**
- `FBSNotificationListenerService.kt` — 添加 native 层 `shouldMonitorPackage(packageName, isRegular)` 过滤
- `MainActivity.kt` — `getInstalledApps()` 包含系统应用，返回 `isSystem` 字段
- `MonitorSettings` — `shouldMonitor()` 应用列表优先过滤
- `native_service.dart` — 传递 `isSystem` 字段，新增 `updateMonitorSettings()` 方法
- `settings_page.dart` — 新增"监听应用列表"入口（二级菜单）
- `monitor_apps_page.dart` — 新建：可折叠的应用列表页面，支持搜索、全选

**过滤逻辑：**
```
enabledApps.contains(pkg) == false → 跳过（应用列表始终生效）
monitorAll == true → 已选应用的所有类型消息都转发
monitorAll == false → 仅焦点/实时动态通知转发
```

**验证结果（2026-07-06）：**
- `monitorAll=false enabled=0 apps` → `Skip: com.xiaomi.finddevice regular=true` 过滤正常
- 应用列表加载：485 个应用（用户 484 + 系统 1）

### 2026-07-06 之前的工作

详见 git commit 历史。主要功能：
- 背屏通知渲染 Activity（display 1）
- Shizuku 权限管理
- 通知样式自定义（颜色/字号/摄像头避让）
- 通知栏同步清除
- 超级岛测试通知
- 返回手势修复（dispatchKeyEvent）
