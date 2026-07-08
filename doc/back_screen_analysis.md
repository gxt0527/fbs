# 官方背屏应用逆向分析报告

## 基本信息

- **APK**: 背屏_RELEASE-1.0.2605272226.apk (19.3 MB)
- **包名**: `com.xiaomi.subscreencenter`
- **版本**: RELEASE-1.0.2605272226
- **类型**: 系统应用 (platform 签名, SECONDARY_HOME)

## 架构概览

```
┌──────────────────────────────────────────────────┐
│              官方背屏架构                           │
├──────────────────────────────────────────────────┤
│  SubScreenLauncher (SECONDARY_HOME)                │
│  ├── DozeService (DreamService - AOD息屏显示)       │
│  ├── TouchInteractionService (触控手势)             │
│  ├── NotificationPanel (通知面板)                   │
│  ├── MainPanel / SmartAssistantPanel (主屏/智能助手) │
│  ├── PinReceiveActivity (第三方投屏入口)             │
│  └── GuideActivity (引导页)                        │
├──────────────────────────────────────────────────┤
│  数据存储路径:                                      │
│  /data/system/theme_magic/users/{userId}/         │
│    subscreencenter/                               │
│      config/user_pref.json                        │
│      config/widget.json                           │
│      notification/notification_widget.json         │
│      pin/pin_info.json                            │
│      smart_assistant/ (各类智能场景)                │
└──────────────────────────────────────────────────┘
```

## 关键权限 (系统级，普通应用无法获取)

| 权限 | 用途 |
|------|------|
| `DEVICE_POWER` | 屏幕电源控制 |
| `WRITE_SECURE_SETTINGS` | 写入系统设置 |
| `STATUS_BAR_SERVICE` | 状态栏集成 |
| `INTERNAL_SYSTEM_WINDOW` | 系统级悬浮窗 |
| `INJECT_EVENTS` | 模拟输入事件 |
| `INTERACT_ACROSS_USERS_FULL` | 跨用户交互 |
| `com.android.systemui.permission.NOTIFICATION` | SystemUI通知权限 |
| `MANAGE_ACTIVITY_TASKS` | 管理Activity栈 |

## 通知处理流程

### 1. 通知来源
官方背屏通过 SystemUI 获取通知，路径为：
- `content://statusbar.notification` — 状态栏通知
- `content://statusbar.notification/canShowFocus` — 焦点通知
- `content://keyguard.notification/notifications` — 锁屏通知

### 2. 背屏通知参数 (Notification Extras)
系统应用在发送通知时，可以附加以下 extras 来指定背屏行为：

```
miui.rear.param          — 背屏参数 (JSON)
miui.rear.param.media_data — 媒体数据
miui.rear.actions        — 背屏动作
miui.rear.param.user_unlocked — 用户解锁状态
miui.rear.pics           — 图片资源
```

### 3. 通知存储格式
`notification_widget.json` — JSON 数组，每个元素包含:
```json
{
  "notificationId": int,
  "packageName": "string",
  "appName": "string",
  "title": "string",
  "content": "string",
  "timestamp": long,
  "postTime": long,
  "isClearable": boolean,
  "userId": int
}
```

### 4. 通知分类
- **focus** (焦点通知): 来电、闹钟等高优先级通知
- **rear** (背屏通知): 带有 `miui.rear.param` 的普通通知
- **ringing** (响铃通知): 正在响铃状态的通知

## 屏幕控制机制

### 唤醒屏幕
```java
// 官方使用反射调用 PowerManager.wakeUp()
PowerManager.wakeUp() called successfully
// 回退方案
Failed to wake up screen by reflection, using fallback
```

### 亮屏时长
```
SubScreen aod turn off, timeout = 90000     // 90秒
SubScreenAlarmTimeout                        // 超时定时器
SubScreenAutoOffAlarmTimeout                 // 自动关闭定时器
```

### 息屏控制
```
miui.intent.action.SUB_SCREEN_OFF           // 背屏关闭广播
miui.intent.action.SUB_SCREEN_ON            // 背屏开启广播
SubScreen go to sleep because large touch area   // 大面积触摸触发息屏
```

### 锁屏状态
```
KeyguardManager$KeyguardLockedStateListener  // 锁屏状态监听
SUBSCRIBE_TO_KEYGUARD_LOCKED_STATE          // 锁屏状态订阅权限
```

## 第三方应用集成方式

### PinReceiveActivity (唯一公开接口)
```xml
<activity android:name=".pin.PinReceiveActivity" exported="true">
    <intent-filter>
        <action android:name="android.intent.action.SEND" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:mimeType="image/*" />
        <data android:mimeType="text/*" />
    </intent-filter>
</activity>
```

## 背屏展示的 8 种形式

1. **AOD 息屏显示** (DozeService): 时钟+通知摘要，90秒自动关闭
2. **通知面板** (notification_widget.json): JSON数组渲染通知卡
3. **固定消息** (PinReceiveActivity): 第三方 ACTION_SEND 投屏
4. **智能助手卡片** (11种): alarm/car_hailing/ev/food_delivery/music/phone/privacy/sports/stock/timer/miHomeCamera
5. **背屏原生通知** (rear.param): miui.rear.* extras，支持按钮/图片/媒体
6. **焦点通知**: fullScreenIntent，来电/闹钟
7. **桌面时钟** (DeskClock Widget)
8. **主面板** (MainPanel): BottomBarView + TimeView

## FBS 原有问题

### 问题1: 使用了不存在的组件
```kotlin
// ❌ 不存在
ComponentName(SUBSCREEN_PACKAGE, "$SUBSCREEN_PACKAGE.activity.SubScreenActivity")
// ✅ 正确的投屏入口
ComponentName(SUBSCREEN_PACKAGE, "$SUBSCREEN_PACKAGE.pin.PinReceiveActivity")
```

### 问题2: 使用了不存在的广播
```kotlin
// ❌ 不存在
Intent("com.xiaomi.subscreencenter.SHOW_NOTIFICATION")
// ❌ protected broadcast，第三方无法发送 (即使 Shizuku am broadcast 也失败)
Intent("miui.intent.action.SUB_SCREEN_ON")
```

### 问题3: 使用了不存在的内容提供者
```kotlin
// ❌ 不存在
Uri.parse("content://$SUBSCREEN_PACKAGE.provider/notification")
// ❌ ContentProvider 需系统权限，读/写均失败
Uri.parse("content://com.xiaomi.subscreencenter.settings.SubScreenAppProvider/packages")
```

## 修复方案

### 方案A: PinReceiveActivity (无需 Shizuku) ✅ 已验证
```kotlin
val intent = Intent().apply {
    component = ComponentName(SUBSCREEN_PACKAGE, "$SUBSCREEN_PACKAGE.pin.PinReceiveActivity")
    action = Intent.ACTION_SEND
    type = "text/plain"
    putExtra(Intent.EXTRA_TEXT, "$title\n$content")
    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}
context.startActivity(intent)
```

### 方案B: Shizuku 写文件 + 广播 ❌ 不可用
1. 写入 `notification_widget.json` — ✅ Shizuku shell 可写
2. 发送 `miui.intent.action.SUB_SCREEN_ON` — ❌ protected broadcast
3. `input keyevent 26` 唤醒屏幕 — ✅ Shizuku shell 可用

### 方案C: Shizuku Shell 直调 — 部分可用
```
✅ settings put system screen_off_timeout 90000   # 设 90s 超时
✅ input -d 1 keyevent KEYCODE_WAKEUP             # 唤醒背屏
❌ am broadcast -a miui.intent.action.SUB_SCREEN_ON  # protected broadcast
✅ service call activity_task 50 i32 <taskId> i32 1  # 移 task 到 display 1
✅ am start -n <pkg>/.service.BackScreenNotificationActivity -f ... --user 0  # 启动 Activity
```

## 12个官方接口实测结果 (2026-07-08)

| # | 接口 | 方式 | 结果 |
|---|------|------|------|
| 1 | PinReceiveActivity | 标准 ACTION_SEND | ✅ 可用 |
| 2 | 写 notification_widget.json | Shizuku shell | ✅ 可用 |
| 3 | 读 notification_widget.json | Shizuku shell | ✅ 可用 |
| 4 | 广播 SUB_SCREEN_ON | Shizuku am broadcast | ❌ protected |
| 5 | 广播 SUB_SCREEN_OFF | Shizuku am broadcast | ❌ protected |
| 6 | input keyevent WAKEUP | Shizuku shell | ✅ 可用 |
| 7 | settings 屏超时 | Shizuku shell | ✅ 可用 |
| 8 | service call task 50 | Shizuku shell | ✅ 可用 |
| 9 | SubScreenAppProvider | ContentProvider | ❌ 需系统权限 |
| 10 | statusbar.notification | ContentProvider | ❌ 需 STATUS_BAR |
| 11 | force-stop 背屏 | Shizuku shell | ✅ 可用 |
| 12 | am start Activity | Shizuku shell | ✅ 可用 |

**结论**: 12 个接口中 8 个可用。不可用的 4 个均为系统级保护接口（protected broadcast / system ContentProvider），第三方无法绕过。
