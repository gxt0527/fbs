import 'package:shared_preferences/shared_preferences.dart';

class MonitorSettings {
  bool monitorAll;
  bool onlyFocusNotifications;
  bool monitorOngoingNotifications;
  Set<String> enabledApps;
  Set<String> discoveredApps;

  MonitorSettings({
    this.monitorAll = false,
    this.onlyFocusNotifications = false,
    this.monitorOngoingNotifications = false,
    Set<String>? enabledApps,
    Set<String>? discoveredApps,
  })  : enabledApps = enabledApps ?? {},
        discoveredApps = discoveredApps ?? {};

  /// 鍒ゆ柇鏄惁搴旇鐩戝惉璇ラ€氱煡
  /// 搴旂敤鍒楄〃寮€鍏冲缁堢敓鏁堬紱鍏ㄩ儴鐩戝惉鎺у埗鏄惁鍖呭惈鏅€氭秷鎭?  bool shouldMonitor(String packageName, bool isFocusNotification,
      {bool isOngoing = false}) {
    // 搴旂敤鍒楄〃杩囨护 鈥?鏈紑鍚殑搴旂敤濮嬬粓璺宠繃
    if (!enabledApps.contains(packageName)) return false;

    // 鍏ㄩ儴鐩戝惉 = 宸插紑鍚簲鐢ㄧ殑鎵€鏈夌被鍨嬫秷鎭紙鍚櫘閫氭秷鎭級
    if (monitorAll) return true;

    // 鍏抽棴鍏ㄩ儴鐩戝惉鏃讹紝鍙斁琛岀壒娈婄被鍨?    if (isFocusNotification) return true;
    if (isOngoing) return true;

    return false;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('monitor_all', monitorAll);
    await prefs.setBool('only_focus_notifications', onlyFocusNotifications);
    await prefs.setBool('monitor_ongoing_notifications', monitorOngoingNotifications);
    await prefs.setStringList('enabled_apps', enabledApps.toList());
    await prefs.setStringList('discovered_apps', discoveredApps.toList());
  }

  static Future<MonitorSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return MonitorSettings(
      monitorAll: prefs.getBool('monitor_all') ?? false,
      onlyFocusNotifications: prefs.getBool('only_focus_notifications') ?? false,
      monitorOngoingNotifications:
          prefs.getBool('monitor_ongoing_notifications') ?? false,
      enabledApps: prefs.getStringList('enabled_apps')?.toSet() ?? {},
      discoveredApps: prefs.getStringList('discovered_apps')?.toSet() ?? {},
    );
  }

  void discoverApp(String packageName) {
    discoveredApps.add(packageName);
  }
}
