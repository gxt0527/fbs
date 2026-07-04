import 'package:shared_preferences/shared_preferences.dart';

class MonitorSettings {
  bool monitorAll;
  bool onlyFocusNotifications;
  bool monitorOngoingNotifications;
  Set<String> enabledApps;
  Set<String> discoveredApps;

  MonitorSettings({
    this.monitorAll = false,
    this.onlyFocusNotifications = true,
    this.monitorOngoingNotifications = true,
    Set<String>? enabledApps,
    Set<String>? discoveredApps,
  })  : enabledApps = enabledApps ?? {},
        discoveredApps = discoveredApps ?? {};

  /// 判断是否应该监听该通知
  /// 优先级: monitorAll > 焦点通知 > 实时动态 > 白名单
  bool shouldMonitor(String packageName, bool isFocusNotification,
      {bool isOngoing = false}) {
    if (monitorAll) return true;

    if (onlyFocusNotifications && !isFocusNotification) {
      if (monitorOngoingNotifications && isOngoing) {
        return true;
      }
      return false;
    }

    if (enabledApps.isNotEmpty && !enabledApps.contains(packageName)) {
      return false;
    }

    return true;
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
      onlyFocusNotifications: prefs.getBool('only_focus_notifications') ?? true,
      monitorOngoingNotifications:
          prefs.getBool('monitor_ongoing_notifications') ?? true,
      enabledApps: prefs.getStringList('enabled_apps')?.toSet() ?? {},
      discoveredApps: prefs.getStringList('discovered_apps')?.toSet() ?? {},
    );
  }

  void discoverApp(String packageName) {
    discoveredApps.add(packageName);
  }
}
