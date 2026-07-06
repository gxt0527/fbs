# FBS 背屏转发 — 诊断报告

> 日期: 2026-07-05 | 设备: Xiaomi 2509FPN0BC (HyperOS, Android 16)

---

## 一、现象：新流程两个致命失败

| 步骤 | 操作 | 结果 | 根因 |
|------|------|------|------|
| 1 | 写 `notification_widget.json` | ❌ Permission denied | **SELinux Enforcing 拦截** |
| 2 | 广播 `SUB_SCREEN_ON` | ❌ SecurityException | **Android 16 受保护广播** |
| 3 | `input keyevent 26` | ✅ 成功 | shell 权限够 |
| 4 | `dumpsys deviceidle` | ✅ 成功 | shell 权限够 |
| 5 | `settings screen_off_timeout 90000` | ✅ 成功 | shell 权限够 |

即使步骤 3-5 成功了，它们也**毫无意义**——步骤 1 和 2 的失败意味着：通知内容没写进去、背屏没被唤醒。

---

## 二、为什么 Shizuku 不够？—— 两道安全墙

### 2.1 Shizuku 能给你什么？

Shizuku 将你的应用进程**注入到 `shell` (uid=2000) 域**运行。这个权限等同于 `adb shell` —— 能执行大部分系统命令，但不能突破两个更高层的安全机制：

```
应用进程 (uid=10xxx)
    │
    └── Shizuku 提权 ──→ shell 域 (uid=2000)
                           │
                           ├── ✅ shell 命令: input, settings, dumpsys, pm, am
                           │
                           ├── ❌ SELinux 标签检查
                           └── ❌ Android 权限模型 (protected broadcasts)
```

### 2.2 第一道墙：SELinux Enforcing

```
avc: denied { write } for name="notification_widget.json"
scontext=u:r:shell:s0              ← Shizuku 的 SELinux 上下文
tcontext=u:object_r:theme_data_file:s0  ← 文件标签
permissive=0                       ← Enforcing 模式，硬拦截
```

**关键点**：SELinux 是**比 uid/DAC 更高层级**的强制访问控制 (MAC)。即便你是 root (uid=0)，只要你的 SELinux 域 (`shell`) 没有对目标文件类型 (`theme_data_file`) 的写权限，操作就会被拒绝。

`notification_widget.json` 的 SELinux 类型是 `theme_data_file`，只有以下进程能写入：
- `com.xiaomi.subscreencenter` 自身 (platform 签名系统应用，运行在 `platform_app` 或 `system_app` 域)
- 其他有 `theme_data_file` 写权限的系统进程

**Shizuku shell (shell 域) 不在允许列表中**，所以 Enforcing 模式下 100% 被拦截。

**能否通过 Shizuku 绕过？** 不能。Shizuku 的权限模型只到了 uid=2000 级别，没有触及 SELinux 策略层。要通过 SELinux，需要：
- 修改 SELinux 策略（需要 root + 修改 `/sys/fs/selinux/policy`）
- 或临时切换到 permissive 模式（需要 `setenforce 0`，同样需要 root）
- 或将自己的进程注入到 `platform_app` 域（需要平台签名）

### 2.3 第二道墙：Android 16 受保护广播

```
java.lang.SecurityException: Permission Denial:
not allowed to send broadcast miui.intent.action.SUB_SCREEN_ON
from pid=14855, uid=2000
```

`SUB_SCREEN_ON` 是 MIUI 的**受保护 broadcast**。Android 对系统级广播有严格的发送者限制：

| 保护级别 | 允许发送者 |
|----------|-----------|
| `normal` | 任何应用 |
| `dangerous` | 用户授权后任何应用 |
| `signature` | 仅相同签名的应用 |
| `signature|privileged` | 仅 platform 签名 + privileged 应用 |
| `protected` (Android 14+) | 仅系统应用，连 shell 也不行 |

在 Android 16 / HyperOS 上，`SUB_SCREEN_ON` 被定义为 `protected` 级别或 `signature|privileged` 级别，这意味着：
- 即使 uid=2000 (shell/adb)，也不能发送
- 只有 `com.xiaomi.subscreencenter` 自身（platform 签名）能发送
- 或在 AndroidManifest 中声明了该 broadcast 的系统应用

**Shizuku 无法绕过**是因为：Android 的 `ActivityManagerService.broadcastIntent()` 会在 framework 层检查发送者的 uid + 包名 + 签名，shell uid 不满足任何允许条件。

---

## 三、背屏的真实控制机制

### 3.1 背屏 ≠ 主屏，背屏 ≠ 电源键

**核心发现**：背屏是一块**独立管理的副屏**，通过 AOD (Always On Display) DreamService 渲染内容，与主屏的电源键 (`keyevent 26`) 完全无关。

```
┌────────────────────────────────────────────────────┐
│                    主屏 (Main Display)               │
│  控制: PowerManager.wakeUp() / goToSleep()          │
│  触发: 电源键 (keyevent 26) / 双击 / 通知            │
├────────────────────────────────────────────────────┤
│                    背屏 (Sub Screen)                 │
│  控制: SubScreenDozeService (DreamService/AOD)      │
│  触发: 双击背屏 / SUB_SCREEN_ON 广播 / 传感器        │
│  内容: AOD 窗口渲染时钟+通知+小部件                   │
│  超时: 90 秒自动关闭                                 │
└────────────────────────────────────────────────────┘
```

### 3.2 官方背屏的屏幕控制方式（来自 APK 逆向）

| 方式 | 机制 | 触发条件 |
|------|------|----------|
| **双击唤醒** | `TouchInteractionService` → `onDoubleTap` → `PowerManager.wakeUp()` 反射 | 用户双击背屏 |
| **大面积触摸休眠** | 触摸传感器 → "large touch area" → `go to sleep` | 手掌覆盖/放入口袋 |
| **光线传感器** | 低光 → 关闭 / 高光 → doze_suspend | 环境光变化 |
| **接近传感器** | 靠近 → 关闭 / 远离 → doze_suspend | 翻转手机/放入口袋 |
| **广播控制** | `SUB_SCREEN_ON` / `SUB_SCREEN_OFF` | 系统内部/应用调用 |
| **AOD 超时** | `SubScreenAlarmTimeout`，90 秒 | 自动定时 |

**背屏不通过 `input keyevent 26` 控制**。`input keyevent 26` 是模拟电源键，它作用于**主屏**，对背屏没有直接影响。官方背屏使用 `PowerManager.wakeUp()` 反射调用（需要 `DEVICE_POWER` 系统权限）来唤醒设备。

### 3.3 背屏 AOD 的完整生命周期

```
用户双击背屏
    │
    ▼
TouchInteractionService.onDoubleTap()
    │
    ▼
PowerManager.wakeUp() [反射, DEVICE_POWER 权限]
    │
    ▼
SubScreenDozeService (DreamService) 启动
    │
    ▼
SubScreenAodController.addAodWindow()
    │  渲染: 时钟 + 通知摘要 + 小部件
    │
    ▼
90 秒后 → SubScreenAlarmTimeout → dismissAodWindow()
    │
    ▼
背屏回到休眠状态
```

---

## 四、FBS 当前策略的 3 个错误

### 错误 1：以为 `input keyevent 26` 能唤醒背屏

`input keyevent 26` 模拟的是**电源键**，它 toggle 的是**主屏**。背屏由独立的 DreamService 管理，不受电源键控制。而且如果主屏本来亮着，`input keyevent 26` 会**把主屏锁掉**（这就是你观察到的 bug）。

### 错误 2：以为 Shizuku 能写 notification_widget.json

Shizuku 只提供 shell (uid=2000) 权限，而 `notification_widget.json` 的 SELinux 标签 `theme_data_file` 不允许 shell 域写入。这是 Enforcing 模式下的硬拦截，与 uid 无关。

### 错误 3：以为 Shizuku 能发 SUB_SCREEN_ON 广播

Android 16 将此广播定义为受保护级别，连 shell (uid=2000) 也不允许发送。只有 platform 签名的系统应用有权发送。

---

## 五、可行的方案

### 方案 A：PinReceiveActivity（当前唯一可行，无需 Shizuku）

```kotlin
// com.xiaomi.subscreencenter.pin.PinReceiveActivity
// 支持 ACTION_SEND + text/* + image/*
val intent = Intent().apply {
    component = ComponentName(
        "com.xiaomi.subscreencenter",
        "com.xiaomi.subscreencenter.pin.PinReceiveActivity"
    )
    action = Intent.ACTION_SEND
    type = "text/plain"
    putExtra(Intent.EXTRA_TEXT, "$title\n$content")
    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}
context.startActivity(intent)
```

**优点**：不需要任何权限，是官方公开的第三方接口
**缺点**：投屏内容格式限制（仅 text/image），且需要用户手动双击背屏才能看到

### 方案 B：修改 SELinux 策略（需要 Root）

如果设备已 root，可以用 Magisk/KernelSU 安装 SELinux 策略模块，允许 shell 域写入 `theme_data_file`：

```
allow shell theme_data_file:file { write create setattr };
```

但这**不推荐**，因为：
- 需要 root，普通用户不可用
- 修改 SELinux 策略降低系统安全性
- 依然无法解决广播权限问题

### 方案 C：使用 AccessibilityService 模拟双击背屏（理论可行）

如果能通过 AccessibilityService 向背屏区域发送双击手势事件，可以模拟用户双击唤醒背屏。但需要：
- AccessibilityService 权限
- 准确定位背屏的坐标区域
- 绕过 Android 的安全限制（跨 display 注入事件）

### 方案 D：Platform 签名（几乎不可行）

如果能获得小米的 platform 签名，给 FBS 签上 platform 证书，就能：
- 以 `platform_app` SELinux 域运行，可以写 `theme_data_file`
- 发送 `SUB_SCREEN_ON` 等受保护广播
- 调用 `PowerManager.wakeUp()` 反射

但这几乎不可能——platform 签名是小米的核心安全凭据。

### 方案 E：保持现状，优化 PinReceiveActivity 体验

在现有条件下，最务实的方案是：
1. **通知转发**：使用 `PinReceiveActivity` 投屏 text/image 到背屏
2. **提示用户**：在投屏后 Toast 提示"请双击背屏查看"
3. **辅助监控**：如果 Shizuku 可用，用 `dumpsys` 监控背屏 AOD 状态（只读）
4. **去除无效操作**：删除 `input keyevent 26`（会误锁主屏）、`SUB_SCREEN_ON` 广播（100% 失败）、写 JSON（100% 失败）

---

## 六、总结

| 问题 | 根因 | 可解？ |
|------|------|--------|
| 写 notification_widget.json 失败 | SELinux theme_data_file 不允许 shell 域写入 | ❌ 需要 root 或 platform 签名 |
| 发 SUB_SCREEN_ON 失败 | Android 16 受保护广播，shell 无权发送 | ❌ 需要 platform 签名 |
| input keyevent 26 误锁屏 | 电源键作用于主屏，不是背屏 | ✅ 直接删除此步骤 |
| 背屏亮屏/灭屏 | 通过双击/触摸/传感器/广播控制，与电源键无关 | ✅ 理解正确后不再误操作 |

**结论**：在当前设备上（无 root、无 platform 签名），唯一可靠的背屏交互方式是 `PinReceiveActivity`。Shizuku 虽然能提权到 shell 级别，但无法穿透 SELinux 和 Android 16 的受保护广播限制。`input keyevent 26` 对背屏无效且会误锁主屏，应该删除。
