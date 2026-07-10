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

  /// 鍘婚噸锛氳褰曟渶杩戝凡杞彂杩囩殑 notificationKey锛屽喎鍗存湡鍐呬笉鍐嶉噸澶嶈浆鍙?  final Set<String> _recentlyForwardedKeys = {};
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
      // 鍚屾璁剧疆鍒?native 灞?      _nativeService.updateMonitorSettings(
        monitorAll: settings.monitorAll,
        enabledApps: settings.enabledApps.toList(),
      );
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
            content: Text('Shizuku 鏉冮檺宸叉巿浜?),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Shizuku 鏉冮檺琚嫆缁?),
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
          content: Text(granted ? '搴旂敤鍒楄〃鏉冮檺宸叉巿浜? : '搴旂敤鍒楄〃鏉冮檺琚嫆缁?),
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
    // 寮哄埗绯荤粺閲嶆柊缁戝畾閫氱煡鐩戝惉鍣紙HyperOS 浼氬洜鏃犺嚜鍚姩鏉冮檺闃绘缁戝畾锛?    await _nativeService.rebindNotificationListener();
    setState(() {
      _isForegroundServiceRunning = true;
    });
  }

  void _onNotificationReceived(NotificationItem notification) {
    // 璋冭瘯鏃ュ織锛氱‘璁ら€氱煡鏄惁鍒拌揪 Flutter
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

  /// 甯﹀幓閲嶇殑杞彂锛氬悓涓€ notificationKey 鍦ㄥ喎鍗存湡鍐呰烦杩囬噸澶嶈浆鍙?  void _forwardToBackScreenWithDedup(NotificationItem notification) {
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
    final content = notification.content.isNotEmpty ? notification.content : '(鏃犲唴瀹?';
    final subtitle = '';

    // V2: MRSS 椋庢牸 鈥?鑷畾涔夋覆鏌?Activity 鐩存帴鎶曞睆鍒?display 1
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
            content: Text('璇锋眰 Shizuku 鏉冮檺澶辫触: $e'),
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
            title: const Text('FBS 鑳屽睆閫氱煡'),
            actions: [
              IconButton(
                icon: const Icon(Icons.palette),
                onPressed: () => _openStylePage(),
                tooltip: '閫氱煡鏍峰紡',
              ),
              IconButton(
                icon: const Icon(Icons.security),
                onPressed: () =>
                    Navigator.pushNamed(context, '/permission_guide'),
                tooltip: '鏉冮檺寮曞',
              ),
              IconButton(
                icon: const Icon(Icons.science),
                onPressed: () => Navigator.pushNamed(context, '/test'),
                tooltip: '鎺ュ彛娴嬭瘯',
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
                      SnackBar(content: Text('璁惧涓嶆敮鎸佽秴绾у矝: $diag')),
                    );
                    return;
                  }

                  if (!hasFocus) {
                    final open = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('鐒︾偣閫氱煡鏉冮檺鏈紑鍚?),
                        content: Text('闇€瑕佸紑鍚劍鐐归€氱煡鏉冮檺鎵嶈兘鏄剧ず瓒呯骇宀涖€俓n\n璇婃柇: $diag'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('鍙栨秷')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('鍘诲紑鍚?)),
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
                      const SnackBar(content: Text('瓒呯骇宀涙祴璇曢€氱煡宸插彂閫?)),
                    );
                  }
                },
                tooltip: '瓒呯骇宀涙祴璇?,
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
                '閫氱煡鍒楄〃 (${_notifications.length})',
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
                      Text('鏆傛棤閫氱煡', style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 8),
                      Text(
                        '寮€鍚€氱煡鐩戝惉鍚庯紝鏂伴€氱煡灏嗘樉绀哄湪杩欓噷',
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

    final label = StringBuffer('杩囨护涓?);
    if (_settings.onlyFocusNotifications) {
      label.write(' 路 浠呯劍鐐归€氱煡');
    }
    label.write(' 路 ${_settings.enabledApps.length} 涓簲鐢?);

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
                  '鏈嶅姟鐘舵€?,
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
                  tooltip: '鍒锋柊鐘舵€?,
                ),
              ],
            ),
            const SizedBox(height: 12),
            StatusIndicator(
              icon: Icons.notifications_active,
              label: '閫氱煡鐩戝惉',
              isEnabled: _isNotificationListenerEnabled,
              onTap: _isNotificationListenerEnabled
                  ? null
                  : () => _nativeService.openNotificationListenerSettings(),
            ),
            const SizedBox(height: 8),
            StatusIndicator(
              icon: Icons.notifications,
              label: '閫氱煡鏄剧ず',
              isEnabled: _isPostNotificationsGranted,
              onTap: _isPostNotificationsGranted
                  ? null
                  : () => _nativeService.requestPostNotifications(),
            ),
            if (_isInstalledAppsPermissionSupported) ...[
              const SizedBox(height: 8),
              StatusIndicator(
                icon: Icons.apps,
                label: '搴旂敤鍒楄〃鏉冮檺',
                isEnabled: _isInstalledAppsPermissionGranted,
                onTap: _isInstalledAppsPermissionGranted
                    ? null
                    : () => _nativeService.requestInstalledAppsPermission(),
              ),
            ],
            const SizedBox(height: 8),
            StatusIndicator(
              icon: Icons.accessibility_new,
              label: _isCheckingShizuku ? 'Shizuku (妫€鏌ヤ腑...)' : 'Shizuku',
              isEnabled: _isShizukuRunning && _hasShizukuPermission,
              onTap: _handleShizukuTap,
            ),
            const SizedBox(height: 8),
            StatusIndicator(
              icon: Icons.desktop_windows,
              label: '鑳屽睆鏄剧ず',
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
                  Text('姝ｅ湪璇锋眰 Shizuku 鏉冮檺...璇峰湪寮瑰嚭鐨勫璇濇涓厑璁?, style: TextStyle(fontSize: 12)),
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
                  label: '鑷惎鍔?,
                  onTap: () => _nativeService.openAutoStartSettings(),
                ),
                _SuggestionChip(
                  icon: Icons.flash_on,
                  label: '鍚庡彴寮瑰嚭',
                  onTap: () => _nativeService.openBackgroundPopSettings(),
                ),
                _SuggestionChip(
                  icon: Icons.battery_saver,
                  label: '鐢垫睜浼樺寲',
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
          content: Text('璇峰厛鍚姩 Shizuku Manager 骞跺紑鍚?Shizuku 鏈嶅姟'),
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
              title: const Text('鑷姩杞彂鍒拌儗灞?),
              subtitle: Text(
                _hasShizukuPermission
                    ? '鏀跺埌閫氱煡鏃惰嚜鍔ㄥ湪鑳屽睆鏄剧ず'
                    : '闇€瑕?Shizuku 鏉冮檺',
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
              title: const Text('鍚庡彴杩愯'),
              subtitle: const Text('淇濇寔鍓嶅彴鏈嶅姟浠ユ寔缁洃鍚€氱煡'),
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
