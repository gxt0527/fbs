import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/native_service.dart';
import 'home_page.dart';

class PermissionGuidePage extends StatefulWidget {
  const PermissionGuidePage({super.key});

  @override
  State<PermissionGuidePage> createState() => _PermissionGuidePageState();
}

class _PermissionGuidePageState extends State<PermissionGuidePage>
    with WidgetsBindingObserver {
  final _nativeService = NativeService();
  bool _listenerEnabled = false;
  bool _postNotifGranted = false;
  bool _shizukuRunning = false;
  bool _shizukuPerm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final r = await Future.wait([
      _nativeService.isNotificationListenerEnabled(),
      _nativeService.isPostNotificationsGranted(),
      _nativeService.isShizukuRunning(),
      _nativeService.hasShizukuPermission(),
    ]);
    if (!mounted) return;
    setState(() {
      _listenerEnabled = r[0] as bool;
      _postNotifGranted = r[1] as bool;
      _shizukuRunning = r[2] as bool;
      _shizukuPerm = r[3] as bool;
    });
  }

  Future<void> _markCompleted() async {
    if (!_listenerEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先开启通知监听权限，否则清除通知无法关闭背屏')),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permission_guide_completed', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    }
  }

  Future<void> _skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permission_guide_completed', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('权限引导'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            '1. 通知监听权限',
            Icons.notifications_active,
            Colors.blue,
            '清除通知时自动关闭背屏',
            _listenerEnabled,
            [
              _buildPermissionTile(
                '前往系统设置 > 通知使用权',
                () => _nativeService.openNotificationListenerSettings(),
                isPrimary: !_listenerEnabled,
              ),
              if (!_listenerEnabled)
                const Text('找到并开启 "FBS"，开启后返回本页', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            '2. 通知显示权限',
            Icons.notifications,
            Colors.orange,
            'Android 13+ 需要授予',
            _postNotifGranted,
            [
              _buildPermissionTile(
                '请求通知显示权限',
                () => _nativeService.requestPostNotifications(),
                isPrimary: !_postNotifGranted,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            '3. Shizuku',
            Icons.accessibility_new,
            Colors.teal,
            '系统级能力（背屏控制）',
            _shizukuRunning && _shizukuPerm,
            [
              _buildPermissionTile(
                '授权 Shizuku',
                () => _nativeService.requestShizukuPermission(),
              ),
              _buildPermissionTile(
                '自启动权限',
                () => _nativeService.openAutoStartSettings(),
              ),
              _buildPermissionTile(
                '电池优化（建议关闭）',
                () => _nativeService.openBatteryOptimizationSettings(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _markCompleted,
            child: Text(_listenerEnabled ? '完成，开始使用 FBS' : '请先开启通知监听权限'),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _skip,
              child: const Text('跳过引导', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, Color color, String description, bool granted, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(width: 8),
                  Icon(granted ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16, color: granted ? Colors.green : Colors.grey),
                ]),
                const SizedBox(height: 2),
                Text(description, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ])),
            ]),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionTile(String text, VoidCallback onTap, {bool isPrimary = false}) {
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
