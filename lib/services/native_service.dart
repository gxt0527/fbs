import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import '../models/notification_item.dart';

class NativeService {
  static const _methodChannel = MethodChannel('com.example.fbs/native');
  static const _eventChannel = EventChannel('com.example.fbs/notification_events');

  static final NativeService _instance = NativeService._internal();
  factory NativeService() => _instance;
  NativeService._internal();

  final _notificationController = StreamController<NotificationItem>.broadcast();
  Stream<NotificationItem> get onNotification => _notificationController.stream;

  final _notificationRemovedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onNotificationRemoved =>
      _notificationRemovedController.stream;

  final _shizukuPermissionController = StreamController<bool>.broadcast();
  Stream<bool> get onShizukuPermissionResult => _shizukuPermissionController.stream;

  final _installedAppsPermissionController = StreamController<bool>.broadcast();
  Stream<bool> get onInstalledAppsPermissionResult =>
      _installedAppsPermissionController.stream;

  final _postNotificationsPermissionController = StreamController<bool>.broadcast();
  Stream<bool> get onPostNotificationsPermissionResult =>
      _postNotificationsPermissionController.stream;

  final _screenResumedController = StreamController<void>.broadcast();
  Stream<void> get onPermissionScreenResumed => _screenResumedController.stream;

  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final type = event['type'];
          if (type == 'removed') {
            _notificationRemovedController.add(Map<String, dynamic>.from(event));
          } else {
            final item = NotificationItem.fromMap(event);
            _notificationController.add(item);
          }
        }
      },
      onError: (error) {
        _log('EventChannel error: $error');
      },
    );

    _methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onShizukuPermissionResult':
          final granted = call.arguments is Map &&
                  (call.arguments as Map)['granted'] == true;
          _shizukuPermissionController.add(granted);
          break;
        case 'onInstalledAppsPermissionResult':
          final granted = call.arguments is Map &&
                  (call.arguments as Map)['granted'] == true;
          _installedAppsPermissionController.add(granted);
          break;
        case 'onPostNotificationsPermissionResult':
          final granted = call.arguments is Map &&
                  (call.arguments as Map)['granted'] == true;
          _postNotificationsPermissionController.add(granted);
          break;
        case 'onPermissionScreenResumed':
          _screenResumedController.add(null);
          break;
      }
    });
  }

  void dispose() {
    _notificationController.close();
    _notificationRemovedController.close();
    _shizukuPermissionController.close();
    _installedAppsPermissionController.close();
    _postNotificationsPermissionController.close();
    _screenResumedController.close();
  }

  static void _log(String message) {
    developer.log(message, name: 'FBS.NativeService');
  }

  // ========== 通知监听 ==========

  Future<bool> isNotificationListenerEnabled() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isNotificationListenerEnabled');
      return result ?? false;
    } catch (e) {
      _log('Error checking notification listener: $e');
      return false;
    }
  }

  Future<void> openNotificationListenerSettings() async {
    try {
      await _methodChannel.invokeMethod('openNotificationListenerSettings');
    } catch (e) {
      _log('Error opening notification settings: $e');
    }
  }

  // ========== 前台服务 ==========

  Future<void> startForegroundService() async {
    try {
      await _methodChannel.invokeMethod('startForegroundService');
    } catch (e) {
      _log('Error starting foreground service: $e');
    }
  }

  Future<void> stopForegroundService() async {
    try {
      await _methodChannel.invokeMethod('stopForegroundService');
    } catch (e) {
      _log('Error stopping foreground service: $e');
    }
  }

  // ========== Shizuku ==========

  Future<bool> isShizukuRunning() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isShizukuRunning');
      return result ?? false;
    } catch (e) {
      _log('Error checking Shizuku: $e');
      return false;
    }
  }

  Future<bool> hasShizukuPermission() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('hasShizukuPermission');
      return result ?? false;
    } catch (e) {
      _log('Error checking Shizuku permission: $e');
      return false;
    }
  }

  Future<void> requestShizukuPermission() async {
    try {
      await _methodChannel.invokeMethod('requestShizukuPermission');
    } catch (e) {
      _log('Error requesting Shizuku permission: $e');
    }
  }

  // ========== 应用列表 ==========

  Future<List<Map<String, String>>> getInstalledApps({bool useShizuku = false}) async {
    try {
      final result = await _methodChannel.invokeMethod('getInstalledApps', {
        'useShizuku': useShizuku,
      });
      if (result == null) return [];
      if (result is List) {
        return result.whereType<Map>().map((m) {
          return {
            'package': (m['package'] ?? '').toString(),
            'name': (m['name'] ?? m['package'] ?? '').toString(),
            'isSystem': (m['isSystem'] ?? 'false').toString(),
          };
        }).toList();
      }
      _log('getInstalledApps: unexpected type ${result.runtimeType}');
      return [];
    } catch (e) {
      _log('Error getting installed apps: $e');
      return [];
    }
  }

  Future<void> requestAppListPermission() async {
    try {
      await _methodChannel.invokeMethod('requestAppListPermission');
    } catch (e) {
      _log('Error requesting app list permission: $e');
    }
  }

  // ========== 澎湃 OS 新增权限接口 ==========

  Future<bool> isInstalledAppsPermissionSupported() async {
    try {
      final r = await _methodChannel.invokeMethod<bool>('isInstalledAppsPermissionSupported');
      return r ?? false;
    } catch (e) {
      _log('Error checking installed apps permission support: $e');
      return false;
    }
  }

  Future<bool> isInstalledAppsPermissionGranted() async {
    try {
      final r = await _methodChannel.invokeMethod<bool>('isInstalledAppsPermissionGranted');
      return r ?? false;
    } catch (e) {
      _log('Error checking installed apps permission: $e');
      return false;
    }
  }

  Future<void> requestInstalledAppsPermission() async {
    try {
      await _methodChannel.invokeMethod('requestInstalledAppsPermission');
    } catch (e) {
      _log('Error requesting installed apps permission: $e');
    }
  }

  // ========== 通知运行时权限（Android 13+） ==========

  Future<bool> isPostNotificationsGranted() async {
    try {
      final r = await _methodChannel.invokeMethod<bool>('isPostNotificationsGranted');
      return r ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> requestPostNotifications() async {
    try {
      await _methodChannel.invokeMethod('requestPostNotifications');
    } catch (e) {
      _log('Error requesting post notifications: $e');
    }
  }

  // ========== 自启动 / 后台 / 电池 ==========

  Future<bool> openAutoStartSettings() async {
    try {
      final r = await _methodChannel.invokeMethod<bool>('openAutoStartSettings');
      return r ?? false;
    } catch (e) {
      _log('Error opening auto start settings: $e');
      return false;
    }
  }

  Future<void> openBatteryOptimizationSettings() async {
    try {
      await _methodChannel.invokeMethod('openBatteryOptimizationSettings');
    } catch (e) {
      _log('Error opening battery optimization: $e');
    }
  }

  Future<void> openBackgroundPopSettings() async {
    try {
      await _methodChannel.invokeMethod('openBackgroundPopSettings');
    } catch (e) {
      _log('Error opening background pop settings: $e');
    }
  }

  Future<void> openOverlaySettings() async {
    try {
      await _methodChannel.invokeMethod('openOverlaySettings');
    } catch (e) {
      _log('Error opening overlay settings: $e');
    }
  }

  Future<void> openAppDetailsSettings() async {
    try {
      await _methodChannel.invokeMethod('openAppDetailsSettings');
    } catch (e) {
      _log('Error opening app details: $e');
    }
  }

  // ========== 背屏显示 ==========

  Future<void> displayOnBackScreen(String title, String content) async {
    try {
      await _methodChannel.invokeMethod('displayOnBackScreen', {
        'title': title,
        'content': content,
      });
    } catch (e) {
      _log('Error displaying on back screen: $e');
    }
  }

  /// V2: MRSS 风格 — 自定义渲染 Activity 投屏到 display 1
  Future<void> displayOnBackScreenV2({
    required String title,
    required String subtitle,
    required String content,
    required String appName,
    required String packageName,
    required Map<String, String> styleExtras,
    String notificationKey = '',
  }) async {
    _log('FBS_V2: invoking displayOnBackScreenV2 for $packageName');
    try {
      await _methodChannel.invokeMethod('displayOnBackScreenV2', {
        'title': title,
        'subtitle': subtitle,
        'content': content,
        'appName': appName,
        'packageName': packageName,
        'styleExtras': styleExtras,
        'notificationKey': notificationKey,
      });
      _log('FBS_V2: method channel returned OK');
    } catch (e) {
      _log('FBS_V2: ERROR $e');
    }
  }

  Future<void> wakeUpScreen() async {
    try {
      await _methodChannel.invokeMethod('wakeUpScreen');
    } catch (e) {
      _log('Error waking up screen: $e');
    }
  }

  Future<void> setScreenTimeout(int millis) async {
    try {
      await _methodChannel.invokeMethod('setScreenTimeout', {'millis': millis});
    } catch (e) {
      _log('Error setting screen timeout: $e');
    }
  }

  Future<void> setBackScreenBrightness(int brightness) async {
    try {
      await _methodChannel.invokeMethod('setBackScreenBrightness', {'brightness': brightness});
    } catch (e) {
      _log('Error setting brightness: $e');
    }
  }

  Future<void> sleepBackScreen() async {
    try {
      await _methodChannel.invokeMethod('sleepBackScreen');
    } catch (e) {
      _log('Error sleeping back screen: $e');
    }
  }

  // ========== 接口测试 ==========

  /// 运行所有背屏接口测试，返回测试结果列表
  Future<List<Map<String, dynamic>>> runAllTests() async {
    try {
      final result = await _methodChannel.invokeMethod('runAllTests');
      if (result is List) {
        return result.cast<Map<Object?, Object?>>().map((m) {
          return m.map((k, v) => MapEntry(k.toString(), v));
        }).toList();
      }
      return [];
    } catch (e) {
      _log('Error running tests: $e');
      return [];
    }
  }

  Future<void> removePinByNotificationId(int notificationId) async {
    try {
      await _methodChannel.invokeMethod('removePinByNotificationId', {
        'notificationId': notificationId,
      });
    } catch (e) {
      _log('Error removing pin: $e');
    }
  }

  Future<void> clearAllPins() async {
    try {
      await _methodChannel.invokeMethod('clearAllPins');
    } catch (e) {
      _log('Error clearing all pins: $e');
    }
  }

  /// 请求系统重新绑定通知监听器
  Future<void> rebindNotificationListener() async {
    try {
      await _methodChannel.invokeMethod('rebindNotificationListener');
    } catch (e) {
      _log('Error rebinding notification listener: $e');
    }
  }

  /// 发送小米超级岛测试通知
  Future<void> sendIslandTestNotification() async {
    try {
      await _methodChannel.invokeMethod('sendIslandTestNotification');
    } catch (e) {
      _log('Error sending island test notification: $e');
    }
  }

  /// 获取超级岛诊断信息
  Future<String> getIslandDiagnostics() async {
    try {
      final result = await _methodChannel.invokeMethod<String>('getIslandDiagnostics');
      return result ?? 'unknown';
    } catch (e) {
      return 'error: $e';
    }
  }

  /// 打开焦点通知权限设置
  Future<void> openFocusNotificationSettings() async {
    try {
      await _methodChannel.invokeMethod('openFocusNotificationSettings');
    } catch (e) {
      _log('Error opening focus settings: $e');
    }
  }

  /// 同步监听设置到 native 层（哪些应用需要监听）
  Future<void> updateMonitorSettings({
    required bool monitorAll,
    required List<String> enabledApps,
  }) async {
    try {
      await _methodChannel.invokeMethod('updateMonitorSettings', {
        'monitorAll': monitorAll,
        'enabledApps': enabledApps,
      });
    } catch (e) {
      _log('Error updating monitor settings: $e');
    }
  }
}
