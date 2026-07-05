import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/native_service.dart';

class PermissionGuidePage extends StatefulWidget {
  const PermissionGuidePage({super.key});

  @override
  State<PermissionGuidePage> createState() => _PermissionGuidePageState();
}

class _PermissionGuidePageState extends State<PermissionGuidePage>
    with WidgetsBindingObserver {
  final NativeService _nativeService = NativeService();

  // 权限状态
  bool _notificationEnabled = false;
  bool _postNotificationsGranted = false;
  bool _installedAppsSupported = false;
  bool _installedAppsGranted = false;
  bool _isChecking = true;

  StreamSubscription<bool>? _installedAppsSub;
  StreamSubscription<bool>? _postNotificationsSub;
  StreamSubscription<void>? _screenResumedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nativeService.initialize();

    _installedAppsSub =
        _nativeService.onInstalledAppsPermissionResult.listen((granted) {
      _checkAllPermissions();
    });

    _postNotificationsSub =
        _nativeService.onPostNotificationsPermissionResult.listen((granted) {
      _checkAllPermissions();
    });

    _screenResumedSub =
        _nativeService.onPermissionScreenResumed.listen((_) {
      _checkAllPermissions();
    });

    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _installedAppsSub?.cancel();
    _postNotificationsSub?.cancel();
    _screenResumedSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _checkAllPermissions();
    }
  }

  Future<void> _checkAllPermissions() async {
    final enabled = await _nativeService.isNotificationListenerEnabled();
    final postGranted = await _nativeService.isPostNotificationsGranted();
    final appSupported = await _nativeService.isInstalledAppsPermissionSupported();
    final appGranted = await _nativeService.isInstalledAppsPermissionGranted();

    if (mounted) {
      setState(() {
        _notificationEnabled = enabled;
        _postNotificationsGranted = postGranted;
        _installedAppsSupported = appSupported;
        _installedAppsGranted = appGranted;
        _isChecking = false;
      });
    }
  }

  // 必选权限：通知监听 + 通知显示
  bool get _requiredPermissionsReady => _notificationEnabled;

  Future<void> _markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permission_guide_completed', true);
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('权限引导'),
        actions: [
          TextButton(
            onPressed: _markCompleted,
            child: const Text('跳过'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 权限总览卡片
          if (!_isChecking)
            _buildProgressCard(),
          const SizedBox(height: 12),

          // 1. 通知监听（必选）
          _buildSection(
            '1. 通知监听权限（必选）',
            Icons.notifications_active,
            Colors.blue,
            'FBS 需要监听通知才能转发到背屏',
            isGranted: _notificationEnabled,
            isRequired: true,
            children: [
              _buildPermissionTile(
                '前往系统设置授权',
                () => _nativeService.openNotificationListenerSettings(),
                isPrimary: !_notificationEnabled,
              ),
              const Padding(
                padding: EdgeInsets.only(left: 4, top: 4),
                child: Text(
                  '系统设置 → 通知访问权限 → 找到 "FBS" 并开启',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. 通知显示权限（必选）
          _buildSection(
            '2. 通知显示权限',
            Icons.notifications,
            Colors.orange,
            'Android 13+ 需要此权限才能在状态栏显示通知',
            isGranted: _postNotificationsGranted,
            children: [
              if (!_postNotificationsGranted)
                _buildPermissionTile(
                  '请求通知显示权限',
                  () => _nativeService.requestPostNotifications(),
                  isPrimary: true,
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. 应用列表权限
          _buildSection(
            '3. 应用列表权限',
            Icons.apps,
            Colors.purple,
            _installedAppsSupported
                ? '澎湃OS 需要此权限才能读取已安装应用列表'
                : '用于读取已安装应用，供白名单过滤使用',
            isGranted: _installedAppsGranted,
            isOptional: !_installedAppsSupported,
            children: [
              if (!_installedAppsGranted)
                _buildPermissionTile(
                  _installedAppsSupported ? '请求应用列表权限' : '前往应用详情页',
                  () => _installedAppsSupported
                      ? _nativeService.requestInstalledAppsPermission()
                      : _nativeService.requestAppListPermission(),
                  isPrimary: true,
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 4. 自启动 / 后台（建议）
          _buildSection(
            '4. 后台保活（建议）',
            Icons.power_settings_new,
            Colors.teal,
            '防止息屏后系统杀掉通知监听服务',
            isOptional: true,
            children: [
              _buildPermissionTile(
                '自启动权限',
                () => _nativeService.openAutoStartSettings(),
              ),
              _buildPermissionTile(
                '后台弹出权限',
                () => _nativeService.openBackgroundPopSettings(),
              ),
              _buildPermissionTile(
                '电池优化（建议关闭）',
                () => _nativeService.openBatteryOptimizationSettings(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 5. Shizuku（可选）
          _buildSection(
            '5. Shizuku（可选）',
            Icons.accessibility_new,
            Colors.cyan,
            '提供系统级能力：背屏唤醒、超时控制等',
            isOptional: true,
            children: [
              _buildPermissionTile(
                '启动 Shizuku 授权',
                () => _nativeService.requestShizukuPermission(),
              ),
            ],
          ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _requiredPermissionsReady ? _markCompleted : null,
            icon: Icon(
              _requiredPermissionsReady ? Icons.check_circle : Icons.warning_amber_rounded,
              size: 20,
            ),
            label: Text(
              _requiredPermissionsReady
                  ? '完成，开始使用 FBS'
                  : '请先授权通知监听权限',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final requiredCount = 1; // 通知监听
    final requiredDone = _notificationEnabled ? 1 : 0;
    final optionalCount = _installedAppsSupported ? 1 : 0; // 应用列表权限
    final optionalDone = _installedAppsGranted ? 1 : 0;

    return Card(
      color: _requiredPermissionsReady
          ? Colors.green.shade50
          : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _requiredPermissionsReady
                  ? Icons.check_circle
                  : Icons.info_outline,
              color: _requiredPermissionsReady ? Colors.green : Colors.orange,
              size: 36,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _requiredPermissionsReady
                        ? '必选权限已就绪！'
                        : '请完成必选权限授权',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: _requiredPermissionsReady
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '必选: $requiredDone/$requiredCount  '
                    '${_installedAppsSupported ? "| 澎湃OS: $optionalDone/$optionalCount" : ""}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    String title,
    IconData icon,
    Color color,
    String description, {
    bool? isGranted,
    bool isRequired = false,
    bool isOptional = false,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                          if (isGranted == true)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check, size: 14,
                                      color: Colors.green.shade700),
                                  const SizedBox(width: 2),
                                  Text('已授权',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            )
                          else if (isGranted == false && isRequired)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade300),
                              ),
                              child: Text('必选',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red.shade700,
                                      fontWeight: FontWeight.w500)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionTile(
    String text,
    VoidCallback onTap, {
    bool isPrimary = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: isPrimary
          ? FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.settings, size: 18),
              label: Text(text, style: const TextStyle(fontSize: 13)),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(text, style: const TextStyle(fontSize: 13)),
            ),
    );
  }
}
