import 'dart:async';
import 'package:flutter/material.dart';
import '../models/monitor_settings.dart';
import '../services/native_service.dart';
import 'monitor_apps_page.dart';

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

  StreamSubscription<bool>? _installedAppsPermissionSub;
  StreamSubscription<void>? _screenResumedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nativeService.initialize();

    // 鐩戝惉鏉冮檺鎺堜簣缁撴灉 鈥?鐢ㄦ埛鍦ㄥ脊绐椾腑鎺堟潈鍚庣珛鍗冲埛鏂?    _installedAppsPermissionSub = _nativeService.onInstalledAppsPermissionResult
        .listen((granted) {
      if (mounted) _loadPermissionsAndApps();
    });

    // 鐩戝惉浠庣郴缁熻缃〉闈㈣繑鍥?鈥?鐢ㄦ埛鎵嬪姩淇敼鏉冮檺鍚庡埛鏂?    _screenResumedSub = _nativeService.onPermissionScreenResumed.listen((_) {
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
    // 浠庡悗鍙版仮澶嶏紙渚嬪浠庣郴缁熻缃〉杩斿洖锛夋椂鍒锋柊鏉冮檺鐘舵€?    if (state == AppLifecycleState.resumed && mounted) {
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
    _nativeService.updateMonitorSettings(
      monitorAll: settings.monitorAll,
      enabledApps: settings.enabledApps.toList(),
    );
  }

  Future<void> _saveAndRefresh() async {
    await _settings.save();
    setState(() {});
    // 鍚屾璁剧疆鍒?native 灞?    _nativeService.updateMonitorSettings(
      monitorAll: _settings.monitorAll,
      enabledApps: _settings.enabledApps.toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('璁剧疆'),
      ),
      body: ListView(
        children: [
          _buildSection(
            '鐩戝惉璁剧疆',
            [
              SwitchListTile(
                title: const Text('鍏ㄩ儴娑堟伅'),
                subtitle: const Text(
                  '寮€鍚? 宸查€夊簲鐢ㄧ殑鎵€鏈夋秷鎭紙鍚櫘閫氭秷鎭級\n鍏抽棴: 浠呯劍鐐瑰拰瀹炴椂鍔ㄦ€侀€氱煡',
                  style: TextStyle(fontSize: 12),
                ),
                value: _settings.monitorAll,
                onChanged: (value) {
                  setState(() => _settings.monitorAll = value);
                  _saveAndRefresh();
                },
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.apps),
                title: const Text('鐩戝惉搴旂敤鍒楄〃'),
                subtitle: Text(
                  _settings.enabledApps.isEmpty
                      ? '鏈€夋嫨浠讳綍搴旂敤'
                      : '宸查€夋嫨 ${_settings.enabledApps.length} 涓簲鐢?,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MonitorAppsPage()),
                  );
                  // 杩斿洖鏃跺埛鏂拌缃?                  final settings = await MonitorSettings.load();
                  if (mounted) {
                    setState(() => _settings = settings);
                  }
                },
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ],
          ),
          _buildSection(
            '閫氱煡鐩戝惉',
            [
              ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text('閫氱煡鐩戝惉鏉冮檺'),
                subtitle: Text(
                  _isNotificationListenerEnabled ? '宸插紑鍚? : '鏈紑鍚?,
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
                  title: const Text('搴旂敤鍒楄〃鏉冮檺锛堟編婀僌S锛?),
                  subtitle: Text(
                    _isInstalledAppsPermissionGranted ? '宸叉巿浜? : '鏈巿浜?,
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
                    // 鑷姩鍒锋柊鐢?onPermissionScreenResumed stream 瑙﹀彂
                  },
                ),
              ListTile(
                leading: const Icon(Icons.power_settings_new),
                title: const Text('鑷惎鍔ㄦ潈闄?),
                subtitle: const Text(
                  '寤鸿寮€鍚紝鍚﹀垯鎭睆鍚庨€氱煡鐩戝惉浼氳绯荤粺鏉€鎺?,
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
                title: const Text('Shizuku 鏈嶅姟'),
                subtitle: Text(
                  _isShizukuRunning ? '杩愯涓? : '鏈繍琛?,
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
                title: const Text('濡備綍浣跨敤 Shizuku'),
                subtitle: const Text('鏌ョ湅 Shizuku 瀹夎鍜屼娇鐢ㄦ寚鍗?),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showShizukuGuide(),
              ),
            ],
          ),
          _buildSection(
            '鍏充簬',
            [
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('鐗堟湰'),
                subtitle: Text('1.0.0'),
              ),
            ],
          ),
        ],
      ),
    );
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
        title: const Text('Shizuku 浣跨敤鎸囧崡'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Shizuku 鏄竴涓?Android 绯荤粺鏉冮檺绠＄悊宸ュ叿锛屽厑璁稿簲鐢ㄥ湪涓?root 鐨勬儏鍐典笅鑾峰緱绯荤粺绾ф潈闄愩€?, style: TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              const Text('瀹夎姝ラ锛?, style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildStep('1', '浠?GitHub 涓嬭浇骞跺畨瑁?Shizuku Manager'),
              _buildStep('2', '鎵撳紑 Shizuku Manager 搴旂敤'),
              _buildStep('3', '閫夋嫨"閫氳繃鏃犵嚎璋冭瘯鍚姩"锛堥渶瑕佸紑鍙戣€呴€夐」锛?),
              _buildStep('4', '鎸夌収鎻愮ず瀹屾垚 Shizuku 鏈嶅姟鍚姩'),
              _buildStep('5', '杩斿洖鏈簲鐢紝鐐瑰嚮"Shizuku 鏈嶅姟"鎺堟潈'),
              const SizedBox(height: 16),
              const Text('娉ㄦ剰锛氫娇鐢ㄥ墠璇风‘淇濇墜鏈哄凡寮€鍚紑鍙戣€呴€夐」鍜?USB 璋冭瘯銆?, style: TextStyle(fontSize: 12, color: Colors.orange)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('鐭ラ亾浜?)),
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
