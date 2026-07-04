# FBS 项目长期记忆

## 项目概述
- **名称**: FBS（福帮手）- Flutter Android 背屏通知转发工具
- **包名**: `com.example.fbs`
- **设备**: Xiaomi 2509FPN0BC（HyperOS, Android 16）
- **语言**: Flutter + Kotlin

## Shizuku 集成要点

### 必需的 Manifest 声明（缺一不可）
```xml
<uses-permission android:name="moe.shizuku.manager.permission.API_V23" />
<uses-permission android:name="android.permission.QUERY_ALL_PACKAGES" />
<queries>
    <package android:name="moe.shizuku.privileged.api" />
</queries>
<provider
    android:name="rikka.shizuku.ShizukuProvider"
    android:authorities="${applicationId}.shizuku"
    android:permission="android.permission.INTERACT_ACROSS_USERS_FULL"
    android:multiprocess="false"
    android:enabled="true"
    android:exported="true" />
<meta-data android:name="moe.shizuku.client.V3_SUPPORT" android:value="true" />
```

### SDK 版本
- Shizuku SDK: **13.1.5**
- Shizuku Manager: 13.5.4

### build.gradle 配置
- targetSdk = 37
- minSdk = 24

### 调试工具
- adb: `D:\pcsuite\adb_41\adb.exe`
- Android SDK: `C:\Android\Sdk`
- 日志: `adb logcat -s BackScreenController PermissionHelper FBSNotificationListener`

## 澎湃OS 权限适配

### 官方文档
- 应用列表权限: https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1619
- 自启动权限: https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1830

### 关键 Intent
- 应用列表权限: `com.android.permission.GET_INSTALLED_APPS`
- 自启动: `miui.intent.action.OP_AUTO_START`
- 后台弹出: `miui.intent.action.POWER_HIDE_MODE_APP`

### 启动权限引导
- 入口: `lib/pages/permission_guide_page.dart`
- 完成标志: `SharedPreferences['permission_guide_completed']`
- 必须权限: 通知监听、POST_NOTIFICATIONS、应用列表
- 建议权限: 自启动、后台弹出、电池优化

## 官方背屏应用逆向分析

### 基本信息
- **包名**: `com.xiaomi.subscreencenter`
- **APK**: `E:\MSRR\背屏_RELEASE-1.0.2605272226.apk` (19MB)
- **本质**: 系统应用，`SECONDARY_HOME`，platform 签名

### 真实可用的第三方接口
1. **PinReceiveActivity** (`ACTION_SEND`, text/* + image/*) — 唯一公开投屏入口，不需 Shizuku
2. 写入 `notification_widget.json` + 发 `miui.intent.action.SUB_SCREEN_ON` — 需要 Shizuku
3. `input keyevent 26` 唤醒屏幕 — 需要 Shizuku

### 屏幕控制参数（官方规范）
- AOD 超时: **90000ms (90秒)**
- 唤醒: `PowerManager.wakeUp()` 反射调用
- 锁屏: `KeyguardManager$KeyguardLockedStateListener`
- 背屏开关: `miui.intent.action.SUB_SCREEN_ON/OFF`

### 通知数据格式
- 存储路径: `/data/system/theme_magic/users/0/subscreencenter/notification/notification_widget.json`
- JSON 数组，字段: notificationId, packageName, appName, title, content, timestamp, postTime, isClearable, userId

### FBS 转发策略
- **无 Shizuku**: 仅 PinReceiveActivity (ACTION_SEND)
- **有 Shizuku**: PinReceive + notification_widget.json + 屏幕唤醒 + 90秒超时

## 通知监听注意事项

### 实时动态通知
HyperOS「实时动态」通知内容可能在：
1. `Notification.extras[EXTRA_TITLE]` / `EXTRA_TEXT`
2. `MediaSession.Metadata` — 音乐类
3. `EXTRA_TEXT_LINES` / `EXTRA_MESSAGES` — InboxStyle/MessagingStyle
4. `EXTRA_BIG_TEXT` / `EXTRA_SUB_TEXT` / `EXTRA_SUMMARY_TEXT`
5. `RemoteViews` — HyperOS 自定义 UI（第三方无法读取）

### 主动查询
`onListenerConnected` 后调用 `getActiveNotifications()` 捕获已存在的通知。

### 调试
`adb logcat -s FBSNotificationListener` 查看完整 extras。

## 相关文件
- `android/app/src/main/AndroidManifest.xml`
- `android/app/build.gradle.kts`
- `android/app/src/main/kotlin/com/example/fbs/service/BackScreenController.kt`
- `android/app/src/main/kotlin/com/example/fbs/service/FBSNotificationListenerService.kt`
- `android/app/src/main/kotlin/com/example/fbs/service/PermissionHelper.kt`
- `android/app/src/main/kotlin/com/example/fbs/MainActivity.kt`
- `lib/main.dart`
- `lib/services/native_service.dart`
- `lib/models/monitor_settings.dart`
- `lib/models/notification_item.dart`
- `lib/widgets/notification_card.dart`
- `lib/pages/home_page.dart`
- `lib/pages/settings_page.dart`
- `lib/pages/permission_guide_page.dart`
- `doc/back_screen_analysis.md`
- `android/app/libs/aidl-13.1.5.jar` 等 4 个 SDK jar
