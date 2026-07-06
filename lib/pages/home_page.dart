import 'package:flutter/material.dart';
import '../models/monitor_settings.dart';
import '../models/notification_item.dart';
import '../models/notification_style.dart';
import '../services/native_service.dart';
import '../widgets/notification_card.dart';
import '../widgets/status_indicator.dart';
import 'notification_style_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final NativeService _nativeService = NativeService();
  final List<NotificationItem> _notifications = [];
  bool _isNotificationListenerEnabled = false;
  bool _isShizukuRunning = false;
  bool _hasShizukuPermission = false;
  bool _isForegroundServiceRunning = false;
  bool _autoForwardEnabled = true;
  bool _isCheckingShizuku = false;
  bool _isRequestingPermission = false;
  bool _isInstalledAppsPermissionSupported = false;
  bool _isInstalledAppsPermissionGranted = false;
  bool _isPostNotificationsGranted = false;
  MonitorSettings _settings = MonitorSettings();
  NotificationStyle _notificationStyle = NotificationStyle();

  /// 去重：记录最近已转发过的 notificationKey，冷却期内不再重复转发
  final Set<String> _recentlyForwardedKeys = {};
  static const Duration _forwardCooldown = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      _checkShizukuStatus();
      _checkAppListPermission();
    }
  }

  Future<void> _loadSettings() async {
    final settings = await MonitorSettings.load();
    if (mounted) {
      setState(() {
        _settings = settings;
      });
    }
  }

  Future<void> _loadStyle() async {
    final style = await NotificationStyle.load();
    if (mounted) {
      setState(() {
        _notificationStyle = style;
      });
    }
  }

  Future<void> _initializeServices() async {
    _nativeService.initialize();
    _nativeService.onNotification.listen(_onNotificationReceived);
    _nativeService.onNotificationRemoved.listen(_onNotificationRemoved);
    _nativeService.onShizukuPermissionResult.listen((granted) {
      if (!mounted) return;
      setState(() {
        _hasShizukuPermission = granted;
        _isRequestingPermission = false;
      });
      final messenger = ScaffoldMessenger.of(context);
      if (granted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Shizuku 权限已授予'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Shizuku 权限被拒绝'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
    _nativeService.onInstalledAppsPermissionResult.listen((granted) {
      if (!mounted) return;
      setState(() => _isInstalledAppsPermissionGranted = granted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(granted ? '应用列表权限已授予' : '应用列表权限被拒绝'),
          backgroundColor: granted ? Colors.green : Colors.red,
        ),
      );
    });
    _nativeService.onPermissionScreenResumed.listen((_) {
      _checkPermissions();
      _checkShizukuStatus();
      _checkAppListPermission();
    });

    await _loadSettings();
    await _loadStyle();
    await _checkPermissions();
    await _checkShizukuStatus();
    await _checkAppListPermission();
  }

  Future<void> _checkAppListPermission() async {
    final supported = await _nativeService.isInstalledAppsPermissionSupported();
    final granted = await _nativeService.isInstalledAppsPermissionGranted();
    final postGranted = await _nativeService.isPostNotificationsGranted();
    if (!mounted) return;
    setState(() {
      _isInstalledAppsPermissionSupported = supported;
      _isInstalledAppsPermissionGranted = granted;
      _isPostNotificationsGranted = postGranted;
    });
  }

  Future<void> _checkPermissions() async {
    final enabled = await _nativeService.isNotificationListenerEnabled();
    setState(() {
      _isNotificationListenerEnabled = enabled;
    });

    if (enabled && !_isForegroundServiceRunning) {
      await _startForegroundService();
    }
  }

  Future<void> _checkShizukuStatus() async {
    setState(() {
      _isCheckingShizuku = true;
    });

    try {
      final running = await _nativeService.isShizukuRunning();
      final hasPermission = await _nativeService.hasShizukuPermission();
      setState(() {
        _isShizukuRunning = running;
        _hasShizukuPermission = hasPermission;
        _isCheckingShizuku = false;
      });
    } catch (e) {
      setState(() {
        _isShizukuRunning = false;
        _hasShizukuPermission = false;
        _isCheckingShizuku = false;
      });
    }
  }

  Future<void> _startForegroundService() async {
    await _nativeService.startForegroundService();
    // 强制系统重新绑定通知监听器（HyperOS 会因无自启动权限阻止绑定）
    await _nativeService.rebindNotificationListener();
    setState(() {
      _isForegroundServiceRunning = true;
    });
  }

  void _onNotificationReceived(NotificationItem notification) {
    // 调试日志：确认通知是否到达 Flutter
    debugPrint('FBS_RECV: pkg=${notification.packageName} title=${notification.title} monitorAll=${_settings.monitorAll}');

    if (!_settings.shouldMonitor(notification.packageName, notification.isFocusNotification,
        isOngoing: notification.isOngoing)) {
      return;
    }

    _settings.discoverApp(notification.packageName);
    _settings.save();

    setState(() {
      _notifications.insert(0, notification);
      if (_notifications.length > 100) {
        _notifications.removeLast();
      }
    });

    if (_autoForwardEnabled) {
      _forwardToBackScreenWithDedup(notification);
    }
  }

  /// 带去重的转发：同一 notificationKey 在冷却期内跳过重复转发
  void _forwardToBackScreenWithDedup(NotificationItem notification) {
    final key = notification.notificationKey;
    if (key.isNotEmpty && _recentlyForwardedKeys.contains(key)) {
      return;
    }

    if (key.isNotEmpty) {
      _recentlyForwardedKeys.add(key);
      Future.delayed(_forwardCooldown, () {
        _recentlyForwardedKeys.remove(key);
      });
    }

    _forwardToBackScreen(notification);
  }

  void _onNotificationRemoved(Map<String, dynamic> info) {
    final key = info['notificationKey'] as String? ?? '';
    if (key.isEmpty) return;

    setState(() {
      _notifications.removeWhere((n) => n.notificationKey == key);
    });
  }

  void _forwardToBackScreen(NotificationItem notification) async {
    debugPrint('FBS_FWD: clicking forward for ${notification.packageName}');
    final title = notification.displayTitle;
    final content = notification.content.isNotEmpty ? notification.content : '(无内容)';
    final subtitle = '';

    // V2: MRSS 风格 — 自定义渲染 Activity 直接投屏到 display 1
    await _nativeService.displayOnBackScreenV2(
      title: title,
      subtitle: subtitle,
      content: content,
      appName: notification.appName,
      packageName: notification.packageName,
      styleExtras: _notificationStyle.toIntentExtras(),
    );
  }

  void _openStylePage() async {
    final updated = await Navigator.push<NotificationStyle>(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationStylePage(initialStyle: _notificationStyle),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _notificationStyle = updated;
      });
    }
  }

  void _requestShizukuPermission() async {
    setState(() {
      _isRequestingPermission = true;
    });

    try {
      await _nativeService.requestShizukuPermission();
    } catch (e) {
      setState(() {
        _isRequestingPermission = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('请求 Shizuku 权限失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('FBS 背屏通知'),
            actions: [
              IconButton(
                icon: const Icon(Icons.palette),
                onPressed: () => _openStylePage(),
                tooltip: '通知样式',
              ),
              IconButton(
                icon: const Icon(Icons.security),
                onPressed: () =>
                    Navigator.pushNamed(context, '/permission_guide'),
                tooltip: '权限引导',
              ),
              IconButton(
                icon: const Icon(Icons.science),
                onPressed: () => Navigator.pushNamed(context, '/test'),
                tooltip: '接口测试',
              ),
              IconButton(
                icon: const Icon(Icons.notifications_active),
                onPressed: () async {
                  final diag = await _nativeService.getIslandDiagnostics();
                  if (!mounted) return;

                  final hasFocus = diag.contains('focus=true');
                  final isIsland = diag.contains('island=true');

                  if (!isIsland) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('设备不支持超级岛: $diag')),
                    );
                    return;
                  }

                  if (!hasFocus) {
                    final open = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('焦点通知权限未开启'),
                        content: Text('需要开启焦点通知权限才能显示超级岛。\n\n诊断: $diag'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('去开启')),
                        ],
                      ),
                    );
                    if (open == true) {
                      await _nativeService.openFocusNotificationSettings();
                    }
                    return;
                  }

                  await _nativeService.sendIslandTestNotification();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('超级岛测试通知已发送')),
                    );
                  }
                },
                tooltip: '超级岛测试',
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () =>
                    Navigator.pushNamed(context, '/settings').then((_) => _loadSettings()),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: _buildStatusSection(),
          ),
          SliverToBoxAdapter(
            child: _buildControlSection(),
          ),
          SliverToBoxAdapter(
            child: _buildFilterInfo(),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '通知列表 (${_notifications.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          if (_notifications.isEmpty)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.notifications_off, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('暂无通知', style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 8),
                      Text(
                        '开启通知监听后，新通知将显示在这里',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final notification = _notifications[index];
                  return NotificationCard(
                    notification: notification,
                    onForward: () => _forwardToBackScreen(notification),
                    onDelete: () {
                      setState(() {
                        _notifications.removeAt(index);
                      });
                    },
                  );
                },
                childCount: _notifications.length,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterInfo() {
    if (_settings.monitorAll) return const SizedBox.shrink();

    final label = StringBuffer('过滤中');
    if (_settings.onlyFocusNotifications) {
      label.write(' · 仅焦点通知');
    }
    label.write(' · ${_settings.enabledApps.length} 个应用');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Chip(
        avatar: const Icon(Icons.filter_list, size: 16),
        label: Text(
          label.toString(),
          style: const TextStyle(fontSize: 12),
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildStatusSection() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '服务状态',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    _checkPermissions();
                    _checkShizukuStatus();
                    _checkAppListPermission();
                  },
                  tooltip: '刷新状态',
                ),
              ],
            ),
            const SizedBox(height: 12),
            StatusIndicator(
              icon: Icons.notifications_active,
              label: '通知监听',
              isEnabled: _isNotificationListenerEnabled,
              onTap: _isNotificationListenerEnabled
                  ? null
                  : () => _nativeService.openNotificationListenerSettings(),
            ),
            const SizedBox(height: 8),
            StatusIndicator(
              icon: Icons.notifications,
              label: '通知显示',
              isEnabled: _isPostNotificationsGranted,
              onTap: _isPostNotificationsGranted
                  ? null
                  : () => _nativeService.requestPostNotifications(),
            ),
            if (_isInstalledAppsPermissionSupported) ...[
              const SizedBox(height: 8),
              StatusIndicator(
                icon: Icons.apps,
                label: '应用列表权限',
                isEnabled: _isInstalledAppsPermissionGranted,
                onTap: _isInstalledAppsPermissionGranted
                    ? null
                    : () => _nativeService.requestInstalledAppsPermission(),
              ),
            ],
            const SizedBox(height: 8),
            StatusIndicator(
              icon: Icons.accessibility_new,
              label: _isCheckingShizuku ? 'Shizuku (检查中...)' : 'Shizuku',
              isEnabled: _isShizukuRunning && _hasShizukuPermission,
              onTap: _handleShizukuTap,
            ),
            const SizedBox(height: 8),
            StatusIndicator(
              icon: Icons.desktop_windows,
              label: '背屏显示',
              isEnabled: _hasShizukuPermission,
            ),
            if (_isRequestingPermission) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('正在请求 Shizuku 权限...请在弹出的对话框中允许', style: TextStyle(fontSize: 12)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _SuggestionChip(
                  icon: Icons.power_settings_new,
                  label: '自启动',
                  onTap: () => _nativeService.openAutoStartSettings(),
                ),
                _SuggestionChip(
                  icon: Icons.flash_on,
                  label: '后台弹出',
                  onTap: () => _nativeService.openBackgroundPopSettings(),
                ),
                _SuggestionChip(
                  icon: Icons.battery_saver,
                  label: '电池优化',
                  onTap: () => _nativeService.openBatteryOptimizationSettings(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleShizukuTap() async {
    if (_isCheckingShizuku || _isRequestingPermission) return;

    if (!_isShizukuRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先启动 Shizuku Manager 并开启 Shizuku 服务'),
          duration: Duration(seconds: 3),
        ),
      );
      await _checkShizukuStatus();
      return;
    }

    if (!_hasShizukuPermission) {
      _requestShizukuPermission();
    }
  }

  Widget _buildControlSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('自动转发到背屏'),
              subtitle: Text(
                _hasShizukuPermission
                    ? '收到通知时自动在背屏显示'
                    : '需要 Shizuku 权限',
                style: TextStyle(
                  color: _hasShizukuPermission ? null : Colors.grey,
                ),
              ),
              value: _autoForwardEnabled && _hasShizukuPermission,
              onChanged: _hasShizukuPermission
                  ? (value) {
                      setState(() {
                        _autoForwardEnabled = value;
                      });
                    }
                  : null,
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('后台运行'),
              subtitle: const Text('保持前台服务以持续监听通知'),
              value: _isForegroundServiceRunning,
              onChanged: (value) async {
                if (value) {
                  await _startForegroundService();
                } else {
                  await _nativeService.stopForegroundService();
                  setState(() {
                    _isForegroundServiceRunning = false;
                  });
                }
              },
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}
