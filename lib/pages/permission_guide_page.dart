import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/native_service.dart';
import 'home_page.dart';
import '../main.dart';
import '../widgets/slide_route.dart';

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
        SlideRoute(builder: (_) => const HomePage()),
      );
    }
  }

  Future<void> _skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permission_guide_completed', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        SlideRoute(builder: (_) => const HomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('权限引导'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 72, 16, 24),
        children: [
          _buildSection(
            '通知监听权限',
            Icons.notifications_active_rounded,
            const Color(0xFF0088FF),
            '清除通知时自动关闭背屏',
            _listenerEnabled,
            [
              _buildPermissionTile(
                '前往系统设置 > 通知使用权',
                () => _nativeService.openNotificationListenerSettings(),
                isPrimary: !_listenerEnabled,
              ),
              if (!_listenerEnabled)
                Text('找到并开启 "FBS"，开启后返回本页',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black45)),
            ],
          ),
          const SizedBox(height: GlassTokens.spaceMD),
          _buildSection(
            '通知显示权限',
            Icons.notifications_rounded,
            const Color(0xFFFF9500),
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
          const SizedBox(height: GlassTokens.spaceMD),
          _buildSection(
            'Shizuku',
            Icons.usb_rounded,
            const Color(0xFF5856D6),
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
          const SizedBox(height: GlassTokens.spaceLG),
          FilledButton(
            onPressed: _markCompleted,
            child: Text(_listenerEnabled ? '完成，开始使用 FBS' : '请先开启通知监听权限'),
          ),
          const SizedBox(height: GlassTokens.spaceSM),
          Center(
            child: TextButton(
              onPressed: _skip,
              child: Text('跳过引导',
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 13,
                )),
            ),
          ),
          const SizedBox(height: GlassTokens.spaceXL),
        ],
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, Color color, String description, bool granted, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
          padding: const EdgeInsets.all(GlassTokens.spaceMD),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GlassTokens.radiusLG),
            gradient: GlassTokens.glassGradient(Theme.of(context).brightness),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.30),
              width: 0.5,
            ),
            boxShadow: GlassTokens.glassShadow(Theme.of(context).brightness),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
                    color: color.withValues(alpha: 0.12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(width: 8),
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: granted ? const Color(0xFF34C759) : const Color(0xFF8E8E93),
                        boxShadow: granted
                          ? [BoxShadow(color: const Color(0xFF34C759).withValues(alpha: 0.4), blurRadius: 4)]
                          : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(description, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
                ])),
              ]),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
    );
  }

  Widget _buildPermissionTile(String text, VoidCallback onTap, {bool isPrimary = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.spaceSM),
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
