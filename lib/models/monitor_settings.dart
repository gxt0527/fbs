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
  /// 应用列表开关始终生效；全部监听控制是否包含普通消息
  bool shouldMonitor(String packageName, bool isFocusNotification,
      {bool isOngoing = false}) {
    // 应用列表过滤 — 未开启的应用始终跳过
    if (!enabledApps.contains(packageName)) return false;

    // 全部监听 = 已开启应用的所有类型消息（含普通消息）
    if (monitorAll) return true;

    // 关闭全部监听时，只放行特殊类型
    if (isFocusNotification) return true;
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
