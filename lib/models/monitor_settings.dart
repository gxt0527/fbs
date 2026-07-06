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

  /// 判断是否应该监听该通知
  /// 必须显式开启的应用才监听
  bool shouldMonitor(String packageName, bool isFocusNotification,
      {bool isOngoing = false}) {
    // monitorAll 优先
    if (monitorAll) return true;

    // 已开启的应用白名单
    if (enabledApps.contains(packageName)) return true;

    // 焦点通知单独开关
    if (onlyFocusNotifications && isFocusNotification) return true;

    // 实时动态单独开关
    if (monitorOngoingNotifications && isOngoing) return true;

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
