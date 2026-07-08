import 'package:flutter/material.dart';
import '../services/native_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  final _nativeService = NativeService();
  bool _shizukuRunning = false;
  bool _shizukuPerm = false;
  bool _postNotifGranted = false;
  bool _promotedPerm = false;
  bool _installedAppsSupported = false;
  bool _installedAppsGranted = false;
  bool _mirrorEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAll();
  }

  Future<void> _refreshAll() async {
    final r = await Future.wait([
      _nativeService.isShizukuRunning(), _nativeService.hasShizukuPermission(),
      _nativeService.isPostNotificationsGranted(), _nativeService.hasPromotedPermission(),
      _nativeService.isInstalledAppsPermissionSupported(), _nativeService.isInstalledAppsPermissionGranted(),
      _nativeService.isMirrorEnabled(),
    ]);
    if (mounted) {
      setState(() {
        _shizukuRunning = r[0] as bool; _shizukuPerm = r[1] as bool;
        _postNotifGranted = r[2] as bool; _promotedPerm = r[3] as bool;
        _installedAppsSupported = r[4] as bool; _installedAppsGranted = r[5] as bool;
        _mirrorEnabled = r[6] as bool;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _buildSection('Shizuku', [
          _statusTile('运行状态', _shizukuRunning),
          _statusTile('授权状态', _shizukuPerm),
        ]),
        const SizedBox(height: 16),
        _buildSection('通知权限', [
          _statusTile('通知显示', _postNotifGranted),
          _actionTile('超级岛权限', _promotedPerm,
            onGrant: () => _nativeService.requestPromotedPermission(),
            onSettings: () => _nativeService.openFocusNotificationSettings(),
          ),
        ]),
        const SizedBox(height: 16),
        _buildSection('背屏镜像', [
          SwitchListTile(
            title: const Text('通知镜像到背屏', style: TextStyle(fontSize: 14)),
            subtitle: const Text('自动将前端通知同步显示到背屏', style: TextStyle(fontSize: 12)),
            value: _mirrorEnabled,
            onChanged: (v) async {
              await _nativeService.setMirrorEnabled(v);
              setState(() => _mirrorEnabled = v);
            },
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ]),
        const SizedBox(height: 16),
        _buildSection('系统权限', [
          if (_installedAppsSupported) _actionTile('应用列表权限', _installedAppsGranted,
            onGrant: () => _nativeService.requestInstalledAppsPermission()),
          _actionTile('自启动', null, onGrant: () => _nativeService.openAutoStartSettings()),
          _actionTile('电池优化', null, onGrant: () => _nativeService.openBatteryOptimizationSettings()),
          _actionTile('应用详情', null, onGrant: () => _nativeService.openAppDetailsSettings()),
        ]),
      ]),
    );
  }

  Widget _buildSection(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title, style: Theme.of(context).textTheme.titleSmall)), ...children],
  );

  Widget _statusTile(String label, bool? status) => ListTile(
    dense: true, contentPadding: EdgeInsets.zero,
    title: Text(label, style: const TextStyle(fontSize: 14)),
    trailing: Icon(status == true ? Icons.check_circle : Icons.cancel, size: 20, color: status == true ? Colors.green : Colors.red.shade300),
  );

  Widget _actionTile(String label, bool? status, {VoidCallback? onGrant, VoidCallback? onSettings}) => ListTile(
    dense: true, contentPadding: EdgeInsets.zero,
    title: Text(label, style: const TextStyle(fontSize: 14)),
    trailing: status == true
        ? const Icon(Icons.check_circle, size: 20, color: Colors.green)
        : TextButton(onPressed: onGrant, child: Text(status == false ? '授权' : '打开', style: const TextStyle(fontSize: 13))),
  );
}
