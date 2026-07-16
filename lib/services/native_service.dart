import 'dart:async';
import 'package:flutter/services.dart';

/// 分享内容类型
class SharedContent {
  final String type; // 'text' or 'image'
  final String? text;
  final String? imageUri;
  const SharedContent({required this.type, this.text, this.imageUri});
}

/// OCR识别结果数据类
class OcrRecognizeResult {
  final bool success;
  final String text;
  final int lineCount;
  final int detectionTimeMs;
  final int recognitionTimeMs;
  final int totalTimeMs;
  final String errorMessage;
  
  const OcrRecognizeResult({
    required this.success,
    this.text = '',
    this.lineCount = 0,
    this.detectionTimeMs = 0,
    this.recognitionTimeMs = 0,
    this.totalTimeMs = 0,
    this.errorMessage = '',
  });
}

class NativeService {
  static final NativeService _instance = NativeService._internal();
  factory NativeService() => _instance;
  NativeService._internal();

  final MethodChannel _methodChannel = const MethodChannel('com.example.fbs/native');
  final EventChannel _eventChannel = const EventChannel('com.example.fbs/notification_events');
  Stream<dynamic>? _eventStream;

  /// 分享内容回调流 — 处理 PROCESS_TEXT / SEND intent
  final _sharedContentController = StreamController<SharedContent>.broadcast();
  Stream<SharedContent> get onSharedContent => _sharedContentController.stream;

  /// 获取通知事件流（监听清除通知）
  Stream<dynamic> get eventStream {
    _eventStream ??= _eventChannel.receiveBroadcastStream();
    return _eventStream!;
  }

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
    String category = 'general',
  }) async {
    try {
      await _methodChannel.invokeMethod('displayOnBackScreenV2', {
        'title': title, 'subtitle': subtitle, 'content': content,
        'appName': appName, 'packageName': '',
        'category': category,
        if (styleExtras != null) 'styleExtras': styleExtras,
      });
    } catch (e) { /* ignore */ }
  }
  Future<void> dismissBackScreen() async {
    try { await _methodChannel.invokeMethod('dismissBackScreen'); } catch (_) {}
  }

  // 超级岛 (HyperIsland-ToolKit)
  Future<void> sendSuperIslandNotification({
    required String title,
    required String content,
    String category = 'general',
  }) async {
    try {
      await _methodChannel.invokeMethod('sendSuperIslandNotification', {
        'title': title,
        'content': content,
        'iconName': category,
      });
    } catch (e) {
      print('[FBS] sendSuperIslandNotification error: $e');
    }
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

  // HyperIsland 测试工具
  Future<void> launchHyperIslandTest() async {
    try { await _methodChannel.invokeMethod('launchHyperIslandTest'); } catch (_) {}
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
  Future<void> openAppNotificationSettings() async {
    try { await _methodChannel.invokeMethod('openAppNotificationSettings'); } catch (_) {}
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

  // 通知监听
  Future<bool> isNotificationListenerEnabled() async {
    try { return await _methodChannel.invokeMethod<bool>('isNotificationListenerEnabled') ?? false; }
    catch (e) { return false; }
  }
  Future<void> openNotificationListenerSettings() async {
    try { await _methodChannel.invokeMethod('openNotificationListenerSettings'); } catch (_) {}
  }

  // === 分享/复制菜单相关 ===

  /// 初始化 — 注册 Native→Dart 回调监听
  void initShareListener() {
    _methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onSharedContent':
          final type = call.arguments['type'] as String? ?? 'text';
          final text = call.arguments['text'] as String?;
          final imageUri = call.arguments['imageUri'] as String?;
          _sharedContentController.add(SharedContent(
            type: type, text: text, imageUri: imageUri,
          ));
        default:
          throw MissingPluginException('Unknown method: ${call.method}');
      }
    });
  }

  /// 将分享的图片 URI 转发到背屏
  Future<String> forwardSharedImage(String imageUri) async {
    try {
      return await _methodChannel.invokeMethod('forwardSharedImage', {
        'imageUri': imageUri,
      }) ?? 'failed';
    } catch (e) { return 'failed: $e'; }
  }

  // === OCR相关 ===
  
  /// 调用原生OCR识别图片文字
  /// @param imageUri 图片URI字符串 (content://...)
  /// @return OcrRecognizeResult 识别结果
  Future<OcrRecognizeResult> recognizeImageText(String imageUri) async {
    try {
      final result = await _methodChannel.invokeMapMethod<String, dynamic>(
        'recognizeImageText',
        {'imageUri': imageUri},
      );
      
      if (result != null) {
        return OcrRecognizeResult(
          success: result['success'] as bool? ?? false,
          text: result['text'] as String? ?? '',
          lineCount: result['lineCount'] as int? ?? 0,
          detectionTimeMs: result['detectionTimeMs'] as int? ?? 0,
          recognitionTimeMs: result['recognitionTimeMs'] as int? ?? 0,
          totalTimeMs: result['totalTimeMs'] as int? ?? 0,
          errorMessage: result['errorMessage'] as String? ?? '',
        );
      }
      
      return const OcrRecognizeResult(
        success: false,
        errorMessage: '返回结果为空',
      );
    } catch (e) {
      return OcrRecognizeResult(
        success: false,
        errorMessage: '$e',
      );
    }
  }

  /// 显示原生 Android Toast
  Future<void> showToast(String message) async {
    try {
      await _methodChannel.invokeMethod('showToast', {'message': message});
    } catch (_) {}
  }

  void dispose() {
    _sharedContentController.close();
  }
}
