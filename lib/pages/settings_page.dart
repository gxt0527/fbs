import 'dart:async';
import 'package:flutter/material.dart';
import '../models/monitor_settings.dart';
import '../services/native_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  final NativeService _nativeService = NativeService();
  bool _isNotificationListenerEnabled = false;
  bool _isShizukuRunning = false;
  bool _isInstalledAppsPermissionSupported = false;
  bool _isInstalledAppsPermissionGranted = false;
  MonitorSettings _settings = MonitorSettings();
  List<Map<String, String>> _allApps = [];
  bool _isLoadingApps = true;

  StreamSubscription<bool>? _installedAppsPermissionSub;
  StreamSubscription<void>? _screenResumedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nativeService.initialize();

    // 监听权限授予结果 — 用户在弹窗中授权后立即刷新
    _installedAppsPermissionSub = _nativeService.onInstalledAppsPermissionResult
        .listen((granted) {
      if (mounted) _loadPermissionsAndApps();
    });

    // 监听从系统设置页面返回 — 用户手动修改权限后刷新
    _screenResumedSub = _nativeService.onPermissionScreenResumed.listen((_) {
      if (mounted) _loadPermissionsAndApps();
    });

    _loadPermissionsAndApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _installedAppsPermissionSub?.cancel();
    _screenResumedSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台恢复（例如从系统设置页返回）时刷新权限状态
    if (state == AppLifecycleState.resumed && mounted) {
      _loadPermissionsAndApps();
    }
  }

  Future<void> _loadPermissionsAndApps() async {
    final enabled = await _nativeService.isNotificationListenerEnabled();
    final shizukuRunning = await _nativeService.isShizukuRunning();
    final supported = await _nativeService.isInstalledAppsPermissionSupported();
    final granted = await _nativeService.isInstalledAppsPermissionGranted();
    final settings = await MonitorSettings.load();
    setState(() {
      _isNotificationListenerEnabled = enabled;
      _isShizukuRunning = shizukuRunning;
      _isInstalledAppsPermissionSupported = supported;
      _isInstalledAppsPermissionGranted = granted;
      _settings = settings;
    });
    _loadInstalledApps();
  }

  Future<void> _loadInstalledApps() async {
    setState(() => _isLoadingApps = true);
    final apps = await _nativeService.getInstalledApps();
    if (mounted) {
      setState(() {
        _allApps = apps;
        _isLoadingApps = false;
      });
    }
  }

  Future<void> _saveAndRefresh() async {
    await _settings.save();
    setState(() {});
  }

  void _toggleAllApps() {
    if (_allApps.isEmpty) return;
    final allEnabled = _allApps.every(
        (a) => _settings.enabledApps.contains(a['package']));
    setState(() {
      if (allEnabled) {
        _settings.enabledApps.clear();
      } else {
        for (final a in _allApps) {
          _settings.enabledApps.add(a['package']!);
        }
      }
    });
    _saveAndRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          _buildSection(
            '监听设置',
            [
              SwitchListTile(
                title: const Text('全部监听'),
                subtitle: const Text('关闭后可自定义监听应用和焦点通知过滤'),
                value: _settings.monitorAll,
                onChanged: (value) {
                  setState(() => _settings.monitorAll = value);
                  _saveAndRefresh();
                },
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              if (!_settings.monitorAll) ...[
                SwitchListTile(
                  title: const Text('仅监听 HyperOS 焦点通知'),
                  subtitle: const Text(
                    '只显示被系统标记为焦点通知的通知（来电、闹钟、提醒等）',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _settings.onlyFocusNotifications,
                  onChanged: (value) {
                    setState(() => _settings.onlyFocusNotifications = value);
                    _saveAndRefresh();
                  },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                if (_settings.onlyFocusNotifications)
                  SwitchListTile(
                    title: const Text('同时监听实时动态通知'),
                    subtitle: const Text(
                      '音乐播放、外卖配送、赛事比分等持续更新的通知',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _settings.monitorOngoingNotifications,
                    onChanged: (value) {
                      setState(() => _settings.monitorOngoingNotifications = value);
                      _saveAndRefresh();
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      const Text(
                        '已安装应用',
                        style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                      ),
                      const Spacer(),
                      if (_isLoadingApps)
                        const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else ...[
                        Text(
                          '${_allApps.length} 个应用',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        if (_allApps.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _toggleAllApps,
                            icon: Icon(
                              _allApps.every((a) => _settings.enabledApps.contains(a['package']))
                                  ? Icons.deselect
                                  : Icons.select_all,
                              size: 16,
                            ),
                            label: Text(
                              _allApps.every((a) => _settings.enabledApps.contains(a['package']))
                                  ? '全不选'
                                  : '全选',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                if (_isLoadingApps)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('正在加载应用列表...', style: TextStyle(color: Colors.grey))),
                  )
                else if (_allApps.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          _isInstalledAppsPermissionSupported &&
                                  !_isInstalledAppsPermissionGranted
                              ? '澎湃OS 需先授予"应用列表"权限才能读取应用信息'
                              : '无法获取应用列表，请在系统设置中授予权限',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            if (_isInstalledAppsPermissionSupported &&
                                !_isInstalledAppsPermissionGranted) {
                              await _nativeService.requestInstalledAppsPermission();
                            } else {
                              await _nativeService.requestAppListPermission();
                            }
                          },
                          icon: const Icon(Icons.settings, size: 18),
                          label: const Text('前往设置开启'),
                        ),
                      ],
                    ),
                  )
                else
                  ..._buildAppTiles(),
              ],
            ],
          ),
          _buildSection(
            '通知监听',
            [
              ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text('通知监听权限'),
                subtitle: Text(
                  _isNotificationListenerEnabled ? '已开启' : '未开启',
                  style: TextStyle(
                    color: _isNotificationListenerEnabled ? Colors.green : Colors.red,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _nativeService.openNotificationListenerSettings(),
              ),
              if (_isInstalledAppsPermissionSupported)
                ListTile(
                  leading: const Icon(Icons.apps),
                  title: const Text('应用列表权限（澎湃OS）'),
                  subtitle: Text(
                    _isInstalledAppsPermissionGranted ? '已授予' : '未授予',
                    style: TextStyle(
                      color: _isInstalledAppsPermissionGranted
                          ? Colors.green : Colors.red,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    if (!_isInstalledAppsPermissionGranted) {
                      await _nativeService.requestInstalledAppsPermission();
                    } else {
                      await _nativeService.openAppDetailsSettings();
                    }
                    // 自动刷新由 onPermissionScreenResumed stream 触发
                  },
                ),
              ListTile(
                leading: const Icon(Icons.power_settings_new),
                title: const Text('自启动权限'),
                subtitle: const Text(
                  '建议开启，否则息屏后通知监听会被系统杀掉',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _nativeService.openAutoStartSettings(),
              ),
            ],
          ),
          _buildSection(
            'Shizuku',
            [
              ListTile(
                leading: const Icon(Icons.accessibility_new),
                title: const Text('Shizuku 服务'),
                subtitle: Text(
                  _isShizukuRunning ? '运行中' : '未运行',
                  style: TextStyle(
                    color: _isShizukuRunning ? Colors.green : Colors.red,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await _nativeService.requestShizukuPermission();
                  _loadPermissionsAndApps();
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('如何使用 Shizuku'),
                subtitle: const Text('查看 Shizuku 安装和使用指南'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showShizukuGuide(),
              ),
            ],
          ),
          _buildSection(
            '关于',
            [
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('版本'),
                subtitle: Text('1.0.0'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAppTiles() {
    final enabled = _settings.enabledApps;
    final sorted = List<Map<String, String>>.from(_allApps)
      ..sort((a, b) {
        final aOn = enabled.contains(a['package']);
        final bOn = enabled.contains(b['package']);
        if (aOn != bOn) return aOn ? -1 : 1;
        return (a['name'] ?? '').compareTo(b['name'] ?? '');
      });

    return sorted.map((app) {
      final pkg = app['package']!;
      final name = app['name']!;
      final isOn = enabled.contains(pkg);
      return ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: isOn
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.1),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isOn ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
          ),
        ),
        title: Text(name, style: const TextStyle(fontSize: 14)),
        subtitle: Text(pkg, style: const TextStyle(fontSize: 11)),
        trailing: Switch(
          value: isOn,
          onChanged: (v) {
            setState(() {
              if (v) { enabled.add(pkg); } else { enabled.remove(pkg); }
            });
            _saveAndRefresh();
          },
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      );
    }).toList();
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...children,
        const Divider(height: 1),
      ],
    );
  }

  void _showShizukuGuide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Shizuku 使用指南'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Shizuku 是一个 Android 系统权限管理工具，允许应用在不 root 的情况下获得系统级权限。', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              const Text('安装步骤：', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildStep('1', '从 GitHub 下载并安装 Shizuku Manager'),
              _buildStep('2', '打开 Shizuku Manager 应用'),
              _buildStep('3', '选择"通过无线调试启动"（需要开发者选项）'),
              _buildStep('4', '按照提示完成 Shizuku 服务启动'),
              _buildStep('5', '返回本应用，点击"Shizuku 服务"授权'),
              const SizedBox(height: 16),
              const Text('注意：使用前请确保手机已开启开发者选项和 USB 调试。', style: TextStyle(fontSize: 12, color: Colors.orange)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
