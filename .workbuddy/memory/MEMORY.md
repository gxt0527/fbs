# FBS 项目长期记忆

## 项目概述
- **名称**: FBS（福帮手）- Flutter 手动转发工具（背屏 + 超级岛）
- **包名**: `com.example.fbs`
- **设备**: Xiaomi 2509FPN0BC（HyperOS, Android 16）
- **基础版本**: `7abf320` (Flutter UI) + `20260705备份` (BackScreenController + BackScreenNotificationActivity)

---

## ⚠️ 重要：当前功能边界（2026-07-09 定稿）

### 🔴 禁止添加的功能
1. **通知监听服务** (`FBSNotificationListenerService`) — 不需要自动监听
2. **前台服务** (`FBSForegroundService`) — 不需要
3. **镜像模式** (mirror) — 不自动镜像通知
4. **窗口类型覆盖** (`TYPE_APPLICATION_OVERLAY`) — 无效
5. **Presentation / 悬浮窗** — 无效
6. **手势滑动切换** → 需要加回会破坏双击手势（`isClickable=true` 拦截点击）

### ✅ 当前实现（已验证 2026-07-09 下午）

#### 背屏 Activity 启动流程 (BackScreenController)
```
1. context.startActivity(BackScreenNotificationActivity)  // display 0 启动
2. Thread.sleep(500)                                      // 等 Activity 初始化
3. dumpsys activity activities → regex "t(\\d+)"          // 获取 taskId
4. service call activity_task 50 i32 $taskId i32 1         // 移到 display 1
5. am force-stop com.xiaomi.subscreencenter                // 杀系统背屏
6. input keyevent KEYCODE_WAKEUP                           // 唤醒背屏
```

#### 双击手势 (BackScreenNotificationActivity.kt)
- **方案**: `renderView?.isClickable = false`
- **原理**: 触摸穿透 View 到系统 TouchInteractionService（系统背屏应用的一部分）
- **效果**: 双击正常切换 AOD/壁纸模式
- **关键**: 不能设置 `isClickable=true`（会拦截触摸破坏双击）

#### 返回手势 (BackScreenNotificationActivity.kt)
- **方案**: `dispatchKeyEvent()` 拦截 `KEYCODE_BACK`
- **原理**: 系统 SubScreenGestureBack（SystemUI 进程，PID 641）处理边缘滑动 → 生成 KEYCODE_BACK → 分发到背屏 Activity
- **效果**: 背屏右边缘向左滑 → KEYCODE_BACK → finish() → Activity 关闭 → 系统自动重启 subscreencenter → 时钟壁纸恢复
- **不需要** Shizuku 参与返回处理

#### 超级岛 (SuperIslandHelper)
- 发一条焦点通知到通知栏（非超级岛系统）
- 控制转发时是否触发动画

#### Shizuku 集成
- 仅用于: 启动 Activity（间接）、获取 taskId、service call 移屏、force-stop 系统背屏、唤醒背屏
- **不用于**: 启动系统背屏、杀其他应用、写文件

#### 手动转发
- 用户粘贴/输入内容 → 按钮触发 → Activity 启动到 display 1
- 样式设置页已保留 (7abf320 UI)

#### 通知清除同步
```
FBSNotificationListenerService → EventChannel → Flutter → dismissBackScreen()
→ Shizuku force-stop subscreencenter → 系统重启背屏 → Activity 被覆盖
```

---

## 文件说明

### Kotlin 文件 (6个)
| 文件 | 行数 | 用途 |
|------|------|------|
| `MainActivity.kt` | ~320 | 方法通道处理 + 生命周期 |
| `BackScreenController.kt` | ~470 | 背屏转发核心 (Activity 启动+移屏+force-stop) |
| `BackScreenNotificationActivity.kt` | ~280 | 背屏渲染 Activity (Canvas 绘制+双击穿透+KEYCODE_BACK) |
| `FBSNotificationListenerService.kt` | — | 通知监听 (保留未启用) |
| `FBSForegroundService.kt` | — | 前台服务 (保留未启用) |
| `PermissionHelper.kt` | ~200 | 澎湃OS 权限辅助 |
| `SuperIslandHelper.kt` | ~120 | 超级岛通知 |

### Flutter
- `lib/` — 全部来自 `7abf320` 提交
- 包含: 首页、设置、样式配置、内容解析、权限引导、超级岛

---

## 已穷尽的方案（不要再试）

| 方案 | 结果 | 原因 |
|------|------|------|
| `am start --display 1` | ❌ | 系统阻止 "should not allow app show on rear display" |
| `TYPE_APPLICATION_OVERLAY` | ❌ | 无法定位 display 1 |
| `setType(OVERLAY)` | ❌ | 系统仍杀死 Activity |
| `Presentation` | ❌ | 窗口层级不够 |
| 悬浮窗 (WindowManager) | ❌ | 显示在正面屏 |
| `miui.rear.param` | ❌ | 系统只路由系统应用 |
| 写 `notification_widget.json` | ❌ | SELinux 权限 |
| 写 `pin/image/` 替换图片 | ❌ | SELinux 权限 |
| Shizuku `am start` | ❌ | 创建的 Activity 无 taskId (t-1) |
| 背屏服务助手 | ❌ | 无第三方接口 |
| 伪装系统应用 | ❌ | 需 platform 签名 |
