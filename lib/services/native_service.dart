import 'dart:async';
import 'package:flutter/services.dart';

class NativeService {
  static final NativeService _instance = NativeService._internal();
  factory NativeService() => _instance;
  NativeService._internal();

  final MethodChannel _methodChannel = const MethodChannel('com.example.fbs/native');

  // Shizuku
  Future<bool> isShizukuRunning() async {
    try { return await _methodChannel.invokeMethod<bool>('isShizukuRunning') ?? false; }
    catch (e) { return false; }
  }
  Future<bool> hasShizukuPermission() async {
    try { return await _methodChannel.invokeMethod<bool>('hasShizukuPermission') ?? false; }
    catch (e) { return false; }
  }
  Future<void> requestShizukuPermission() async {
    try { await _methodChannel.invokeMethod('requestShizukuPermission'); } catch (_) {}
  }

  // 背屏转发
  Future<void> displayOnBackScreen({
    required String title, required String subtitle, required String content,
    String appName = 'FBS', Map<String, String>? styleExtras,
  }) async {
    try {
      await _methodChannel.invokeMethod('displayOnBackScreenV2', {
        'title': title, 'subtitle': subtitle, 'content': content,
        'appName': appName, 'packageName': '',
        if (styleExtras != null) 'styleExtras': styleExtras,
      });
    } catch (e) { /* ignore */ }
  }
  Future<void> dismissBackScreen() async {
    try { await _methodChannel.invokeMethod('dismissBackScreen'); } catch (_) {}
  }

  // 超级岛
  Future<void> sendSuperIslandNotification({
    required String title, required String content,
  }) async {
    try {
      await _methodChannel.invokeMethod('sendSuperIslandNotification', {
        'title': title, 'content': content,
      });
    } catch (_) {}
  }
  Future<void> cancelSuperIslandNotification() async {
    try { await _methodChannel.invokeMethod('cancelSuperIslandNotification'); } catch (_) {}
  }
  Future<bool> hasPromotedPermission() async {
    try { return await _methodChannel.invokeMethod<bool>('hasPromotedNotificationPermission') ?? false; }
    catch (e) { return false; }
  }
  Future<void> requestPromotedPermission() async {
    try { await _methodChannel.invokeMethod('requestPromotedNotificationPermission'); } catch (_) {}
  }
  Future<void> openFocusNotificationSettings() async {
    try { await _methodChannel.invokeMethod('openFocusNotificationSettings'); } catch (_) {}
  }

  // 权限
  Future<bool> isPostNotificationsGranted() async {
    try { return await _methodChannel.invokeMethod<bool>('isPostNotificationsGranted') ?? false; }
    catch (e) { return false; }
  }
  Future<void> requestPostNotifications() async {
    try { await _methodChannel.invokeMethod('requestPostNotifications'); } catch (_) {}
  }
  Future<bool> isInstalledAppsPermissionSupported() async {
    try { return await _methodChannel.invokeMethod<bool>('isInstalledAppsPermissionSupported') ?? false; }
    catch (e) { return false; }
  }
  Future<bool> isInstalledAppsPermissionGranted() async {
    try { return await _methodChannel.invokeMethod<bool>('isInstalledAppsPermissionGranted') ?? false; }
    catch (e) { return false; }
  }
  Future<void> requestInstalledAppsPermission() async {
    try { await _methodChannel.invokeMethod('requestInstalledAppsPermission'); } catch (_) {}
  }
  Future<void> openAutoStartSettings() async {
    try { await _methodChannel.invokeMethod('openAutoStartSettings'); } catch (_) {}
  }
  Future<void> openBatteryOptimizationSettings() async {
    try { await _methodChannel.invokeMethod('openBatteryOptimizationSettings'); } catch (_) {}
  }
  Future<void> openAppDetailsSettings() async {
    try { await _methodChannel.invokeMethod('openAppDetailsSettings'); } catch (_) {}
  }
  Future<bool> isMiuiOrHyperOS() async {
    try { return await _methodChannel.invokeMethod<bool>('isMiuiOrHyperOS') ?? false; }
    catch (e) { return false; }
  }
  Future<String> testPinWrite() async {
    try { return await _methodChannel.invokeMethod('testPinWrite') ?? 'failed'; }
    catch (e) { return 'failed'; }
  }
  Future<String> sendImagePin({required String title, required String subtitle, required String content}) async {
    try {
      return await _methodChannel.invokeMethod('sendImagePin', {
        'title': title, 'subtitle': subtitle, 'content': content,
      }) ?? 'failed';
    } catch (e) { return 'failed'; }
  }
}
