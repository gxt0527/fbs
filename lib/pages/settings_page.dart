import 'package:flutter/material.dart';
import '../services/native_service.dart';
import '../models/notification_style.dart';
import 'notification_style_page.dart';
import '../main.dart';
import '../widgets/slide_route.dart';

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
  bool _listenerEnabled = false;
  bool _installedAppsSupported = false;
  bool _installedAppsGranted = false;

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
      _nativeService.isNotificationListenerEnabled(),
    ]);
    if (mounted) setState(() {
      _shizukuRunning = r[0] as bool; _shizukuPerm = r[1] as bool;
      _postNotifGranted = r[2] as bool; _promotedPerm = r[3] as bool;
      _installedAppsSupported = r[4] as bool; _installedAppsGranted = r[5] as bool;
      _listenerEnabled = r[6] as bool;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        _buildSectionCard('背屏样式', Icons.palette_outlined, GlassTokens.accent, [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
                color: GlassTokens.accent.withValues(alpha: 0.10),
              ),
              child: const Icon(Icons.palette_outlined, color: GlassTokens.accent, size: 20),
            ),
            title: const Text('自定义样式', style: TextStyle(fontSize: 14)),
            subtitle: const Text('字号、颜色、背景、避开摄像头', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () async {
              final style = await NotificationStyle.load();
              if (!context.mounted) return;
              Navigator.push(context,
                SlideRoute(builder: (_) => NotificationStylePage(initialStyle: style)));
            },
          ),
        ]),
        const SizedBox(height: GlassTokens.spaceMD),
        _buildSectionCard('Shizuku', Icons.usb_rounded, const Color(0xFF5856D6), [
          _statusTile('运行状态', _shizukuRunning),
          _statusTile('授权状态', _shizukuPerm),
        ]),
        const SizedBox(height: GlassTokens.spaceMD),
        _buildSectionCard('通知权限', Icons.notifications_active_rounded, const Color(0xFFFF9500), [
          _actionTile('通知显示', _postNotifGranted,
            onGrant: () { _nativeService.requestPostNotifications(); _refreshAll(); },
            onSettings: () => _nativeService.openAppNotificationSettings(),
          ),
          _actionTile('通知监听', _listenerEnabled,
            onGrant: () => _nativeService.openNotificationListenerSettings(),
            onSettings: () => _nativeService.openNotificationListenerSettings(),
          ),
          _actionTile('超级岛权限', _promotedPerm,
            onGrant: () => _nativeService.requestPromotedPermission(),
            onSettings: () => _nativeService.openFocusNotificationSettings(),
          ),
        ]),
        const SizedBox(height: GlassTokens.spaceMD),
        _buildSectionCard('系统权限', Icons.shield_outlined, const Color(0xFF34C759), [
          if (_installedAppsSupported) _actionTile('应用列表权限', _installedAppsGranted,
            onGrant: () => _nativeService.requestInstalledAppsPermission()),
          _actionTile('自启动', null, onGrant: () => _nativeService.openAutoStartSettings()),
          _actionTile('电池优化', null, onGrant: () => _nativeService.openBatteryOptimizationSettings()),
          _actionTile('应用详情', null, onGrant: () => _nativeService.openAppDetailsSettings()),
        ]),
      ]),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, Color color, List<Widget> children) {
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
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(GlassTokens.radiusXS),
                    color: color.withValues(alpha: 0.12),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Text(title, style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                )),
              ]),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
    );
  }

  Widget _statusTile(String label, bool? status) {
    final ok = status == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 36,
      child: Row(children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ok ? const Color(0xFF34C759) : const Color(0xFFFF375F),
            boxShadow: [BoxShadow(
              color: (ok ? const Color(0xFF34C759) : const Color(0xFFFF375F)).withValues(alpha: 0.4),
              blurRadius: 4,
            )],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
            color: ok ? const Color(0xFF34C759).withValues(alpha: 0.10) : const Color(0xFFFF375F).withValues(alpha: 0.10),
          ),
          child: Text(
            ok ? '正常' : '未开启',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: ok ? const Color(0xFF34C759) : const Color(0xFFFF375F),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _actionTile(String label, bool? status, {VoidCallback? onGrant, VoidCallback? onSettings}) {
    final ok = status == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 36,
      child: Row(children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ok ? const Color(0xFF34C759) : const Color(0xFF8E8E93),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87))),
        SizedBox(
          height: 28,
          child: ok
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
                  color: const Color(0xFF34C759).withValues(alpha: 0.10),
                ),
                child: const Center(child: Text('已授权', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF34C759)))),
              )
            : GestureDetector(
                onTap: onGrant,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
                    color: GlassTokens.accent.withValues(alpha: 0.12),
                    border: Border.all(color: GlassTokens.accent.withValues(alpha: 0.25), width: 0.5),
                  ),
                  child: const Center(child: Text('授权', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: GlassTokens.accent))),
                ),
              ),
        ),
      ]),
    );
  }
}
