import 'dart:async';
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
  Stream<bool> get onInstalledAppsPermissionResult => _installedAppsPermissionController.stream;

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
        print('EventChannel error: $error');
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

  // ========== 通知监听 ==========

  Future<bool> isNotificationListenerEnabled() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isNotificationListenerEnabled');
      return result ?? false;
    } catch (e) {
      print('Error checking notification listener: $e');
      return false;
    }
  }

  Future<void> openNotificationListenerSettings() async {
    try {
      await _methodChannel.invokeMethod('openNotificationListenerSettings');
    } catch (e) {
      print('Error opening notification settings: $e');
    }
  }

  // ========== 前台服务 ==========

  Future<void> startForegroundService() async {
    try {
      await _methodChannel.invokeMethod('startForegroundService');
    } catch (e) {
      print('Error starting foreground service: $e');
    }
  }

  Future<void> stopForegroundService() async {
    try {
      await _methodChannel.invokeMethod('stopForegroundService');
    } catch (e) {
      print('Error stopping foreground service: $e');
    }
  }

  // ========== Shizuku ==========

  Future<bool> isShizukuRunning() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isShizukuRunning');
      return result ?? false;
    } catch (e) {
      print('Error checking Shizuku: $e');
      return false;
    }
  }

  Future<bool> hasShizukuPermission() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('hasShizukuPermission');
      return result ?? false;
    } catch (e) {
      print('Error checking Shizuku permission: $e');
      return false;
    }
  }

  Future<void> requestShizukuPermission() async {
    try {
      await _methodChannel.invokeMethod('requestShizukuPermission');
    } catch (e) {
      print('Error requesting Shizuku permission: $e');
    }
  }

  // ========== 应用列表 ==========

  Future<List<Map<String, String>>> getInstalledApps({bool useShizuku = true}) async {
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>('getInstalledApps', {
        'useShizuku': useShizuku,
      });
      if (result == null) return [];
      return result.cast<Map<String, dynamic>>().map((m) => {
        'package': m['package'] as String? ?? '',
        'name': m['name'] as String? ?? m['package'] as String? ?? '',
      }).toList();
    } catch (e) {
      print('Error getting installed apps: $e');
      return [];
    }
  }

  Future<void> requestAppListPermission() async {
    try {
      await _methodChannel.invokeMethod('requestAppListPermission');
    } catch (e) {
      print('Error requesting app list permission: $e');
    }
  }

  // ========== 澎湃 OS 新增权限接口 ==========

  Future<bool> isInstalledAppsPermissionSupported() async {
    try {
      final r = await _methodChannel.invokeMethod<bool>('isInstalledAppsPermissionSupported');
      return r ?? false;
    } catch (e) {
      print('Error checking installed apps permission support: $e');
      return false;
    }
  }

  Future<bool> isInstalledAppsPermissionGranted() async {
    try {
      final r = await _methodChannel.invokeMethod<bool>('isInstalledAppsPermissionGranted');
      return r ?? false;
    } catch (e) {
      print('Error checking installed apps permission: $e');
      return false;
    }
  }

  Future<void> requestInstalledAppsPermission() async {
    try {
      await _methodChannel.invokeMethod('requestInstalledAppsPermission');
    } catch (e) {
      print('Error requesting installed apps permission: $e');
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
      print('Error requesting post notifications: $e');
    }
  }

  // ========== 自启动 / 后台 / 电池 ==========

  Future<bool> openAutoStartSettings() async {
    try {
      final r = await _methodChannel.invokeMethod<bool>('openAutoStartSettings');
      return r ?? false;
    } catch (e) {
      print('Error opening auto start settings: $e');
      return false;
    }
  }

  Future<void> openBatteryOptimizationSettings() async {
    try {
      await _methodChannel.invokeMethod('openBatteryOptimizationSettings');
    } catch (e) {
      print('Error opening battery optimization: $e');
    }
  }

  Future<void> openBackgroundPopSettings() async {
    try {
      await _methodChannel.invokeMethod('openBackgroundPopSettings');
    } catch (e) {
      print('Error opening background pop settings: $e');
    }
  }

  Future<void> openOverlaySettings() async {
    try {
      await _methodChannel.invokeMethod('openOverlaySettings');
    } catch (e) {
      print('Error opening overlay settings: $e');
    }
  }

  Future<void> openAppDetailsSettings() async {
    try {
      await _methodChannel.invokeMethod('openAppDetailsSettings');
    } catch (e) {
      print('Error opening app details: $e');
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
      print('Error displaying on back screen: $e');
    }
  }

  Future<void> wakeUpScreen() async {
    try {
      await _methodChannel.invokeMethod('wakeUpScreen');
    } catch (e) {
      print('Error waking up screen: $e');
    }
  }

  Future<void> setScreenTimeout(int millis) async {
    try {
      await _methodChannel.invokeMethod('setScreenTimeout', {'millis': millis});
    } catch (e) {
      print('Error setting screen timeout: $e');
    }
  }

  Future<void> setBackScreenBrightness(int brightness) async {
    try {
      await _methodChannel.invokeMethod('setBackScreenBrightness', {'brightness': brightness});
    } catch (e) {
      print('Error setting brightness: $e');
    }
  }

  Future<void> sleepBackScreen() async {
    try {
      await _methodChannel.invokeMethod('sleepBackScreen');
    } catch (e) {
      print('Error sleeping back screen: $e');
    }
  }

  Future<void> removePinByNotificationId(int notificationId) async {
    try {
      await _methodChannel.invokeMethod('removePinByNotificationId', {
        'notificationId': notificationId,
      });
    } catch (e) {
      print('Error removing pin: $e');
    }
  }

  Future<void> clearAllPins() async {
    try {
      await _methodChannel.invokeMethod('clearAllPins');
    } catch (e) {
      print('Error clearing all pins: $e');
    }
  }

  /// 请求系统重新绑定通知监听器
  Future<void> rebindNotificationListener() async {
    try {
      await _methodChannel.invokeMethod('rebindNotificationListener');
    } catch (e) {
      print('Error rebinding notification listener: $e');
    }
  }
}
