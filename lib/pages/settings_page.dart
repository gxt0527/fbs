import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    final prefs = await SharedPreferences.getInstance();
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
      appBar: AppBar(
        title: Text('设置', style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white : const Color(0xFF1A1A2E),
          letterSpacing: -0.3,
        )),
      ),
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
        const SizedBox(height: GlassTokens.spaceMD),
        _buildSectionCard('超级岛功能测试', Icons.flash_on_rounded, const Color(0xFF7C4DFF), [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.10),
              ),
              child: const Icon(Icons.flash_on_rounded, color: Color(0xFF7C4DFF), size: 20),
            ),
            title: const Text('发送测试通知', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => _sendTestNotification(),
          ),
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

  /// 发送超级岛测试通知（网络阻断 #9 模板）
  Future<void> _sendTestNotification() async {
    try {
      await _nativeService.sendFocusWithNetworkBypassTemplate9(
        label: '测试通知',
        codeValue: '8866',
        storeName: 'FBS超级岛功能测试',
        items: '1条',
        amount: '0',
        category: 'general',
      );

      // 同时显示到背屏
      final style = await NotificationStyle.load();
      final styleMap = {
        'titleFontSize': style.titleFontSize.toString(),
        'subtitleFontSize': style.subtitleFontSize.toString(),
        'contentFontSize': style.contentFontSize.toString(),
        'titleColor': '#${style.titleColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'subtitleColor': '#${style.subtitleColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'contentColor': '#${style.contentColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'backgroundColor': '#${style.backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'showAppIcon': style.showAppIcon.toString(),
        'showTimestamp': style.showTimestamp.toString(),
        'cameraAvoidanceEnabled': style.cameraAvoidanceEnabled.toString(),
        'horizontalOffset': NotificationStyle.cameraAvoidanceOffset.toStringAsFixed(0),
        'padding': style.padding.toString(),
        'spacing': style.spacing.toString(),
        'displayDurationMs': style.displayDurationMs.toString(),
        'useOfficialBackground': style.useOfficialBackground.toString(),
      };
      await _nativeService.displayOnBackScreen(
        title: '测试通知',
        subtitle: '8866',
        content: 'FBS超级岛功能测试\n件数：1条  金额：¥0',
        styleExtras: styleMap,
        category: 'general',
      );

      if (mounted) {
        _nativeService.showToast('超级岛测试通知已发送');
      }
    } catch (e) {
      if (mounted) {
        _nativeService.showToast('发送失败: $e');
      }
    }
  }

  Widget _actionTile(String label, bool? status, {VoidCallback? onGrant, VoidCallback? onSettings}) {
    final ok = status == true;
    final canCheck = status != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 36,
      child: Row(children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ok ? const Color(0xFF34C759) : (canCheck ? const Color(0xFF8E8E93) : const Color(0xFFFF9500)),
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
                    color: canCheck ? GlassTokens.accent.withValues(alpha: 0.12) : const Color(0xFFFF9500).withValues(alpha: 0.10),
                    border: Border.all(
                      color: canCheck ? GlassTokens.accent.withValues(alpha: 0.25) : const Color(0xFFFF9500).withValues(alpha: 0.2),
                      width: 0.5,
                    ),
                  ),
                  child: Center(child: Text(
                    canCheck ? '授权' : '前往',
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: canCheck ? GlassTokens.accent : const Color(0xFFFF9500),
                    ),
                  )),
                ),
              ),
        ),
      ]),
    );
  }
}
