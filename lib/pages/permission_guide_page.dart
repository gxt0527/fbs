import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/native_service.dart';

class PermissionGuidePage extends StatefulWidget {
  const PermissionGuidePage({super.key});

  @override
  State<PermissionGuidePage> createState() => _PermissionGuidePageState();
}

class _PermissionGuidePageState extends State<PermissionGuidePage> {
  final NativeService _nativeService = NativeService();

  @override
  void initState() {
    super.initState();
    _nativeService.initialize();
  }

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
          _buildSection(
            '1. 通知监听权限',
            Icons.notifications_active,
            Colors.blue,
            'FBS 需要监听通知才能转发到背屏',
            [
              _buildPermissionTile(
                '前往系统设置 → 通知访问权限',
                () => _nativeService.openNotificationListenerSettings(),
                isPrimary: true,
              ),
              const Text('找到 "FBS" 并开启开关', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const Text('返回后点击 "检查并继续"', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            '2. 通知显示权限',
            Icons.notifications,
            Colors.orange,
            'Android 13+ 需要授予通知显示权限',
            [
              _buildPermissionTile(
                '请求通知显示权限',
                () => _nativeService.requestPostNotifications(),
                isPrimary: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            '3. 应用列表权限（澎湃OS）',
            Icons.apps,
            Colors.purple,
            '澎湃OS 需要获取已安装应用列表以配置白名单',
            [
              _buildPermissionTile(
                '请求应用列表权限',
                () => _nativeService.requestInstalledAppsPermission(),
                isPrimary: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            '4. Shizuku（可选）',
            Icons.accessibility_new,
            Colors.teal,
            'Shizuku 提供系统级能力（背屏唤醒、超时控制等）',
            [
              _buildPermissionTile(
                'Shizuku Manager',
                () => _nativeService.requestShizukuPermission(),
              ),
              _buildPermissionTile(
                '自启动权限（重要）',
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
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _markCompleted,
            child: const Text('完成，开始使用 FBS'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection(
    String title,
    IconData icon,
    Color color,
    String description,
    List<Widget> children,
  ) {
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
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(description, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
