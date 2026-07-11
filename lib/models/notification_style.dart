import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 通知背屏渲染样式 — 持久化到 SharedPreferences
class NotificationStyle {
  // ── 文字字号 (sp) ──
  double titleFontSize;
  double subtitleFontSize;
  double contentFontSize;

  // ── 文字颜色 ──
  Color titleColor;
  Color subtitleColor;
  Color contentColor;

  // ── 背景色 ──
  Color backgroundColor;

  // ── 显示选项 ──
  bool showAppIcon;
  bool showTimestamp;
  bool cameraAvoidanceEnabled;
  bool useOfficialBackground;

  // ── 布局 ──
  double padding;
  double spacing;
  int displayDurationMs;

  /// 避开摄像头时左侧保留的不可用区域 (dp/rpx)
  static const double cameraAvoidanceOffset = 85;

  NotificationStyle({
    this.titleFontSize = 28,
    this.subtitleFontSize = 20,
    this.contentFontSize = 16,
    this.titleColor = Colors.white,
    this.subtitleColor = const Color(0xFFB0B0B0),
    this.contentColor = const Color(0xFFE0E0E0),
    this.backgroundColor = const Color(0xFF1A1A2E),
    this.showAppIcon = true,
    this.showTimestamp = true,
    this.cameraAvoidanceEnabled = true,
    this.useOfficialBackground = false,
    this.padding = 24,
    this.spacing = 12,
    this.displayDurationMs = 10000,
  });

  // ═══════════════════════════════════════════
  // 序列化 (SharedPreferences)
  // ═══════════════════════════════════════════

  static const _keyTitleFontSize = 'style_titleFontSize';
  static const _keySubtitleFontSize = 'style_subtitleFontSize';
  static const _keyContentFontSize = 'style_contentFontSize';
  static const _keyTitleColor = 'style_titleColor';
  static const _keySubtitleColor = 'style_subtitleColor';
  static const _keyContentColor = 'style_contentColor';
  static const _keyBackgroundColor = 'style_backgroundColor';
  static const _keyShowAppIcon = 'style_showAppIcon';
  static const _keyShowTimestamp = 'style_showTimestamp';
  static const _keyCameraAvoidance = 'style_cameraAvoidance';
  static const _keyUseOfficialBg = 'style_useOfficialBg';
  static const _keyPadding = 'style_padding';
  static const _keySpacing = 'style_spacing';
  static const _keyDisplayDurationMs = 'style_displayDurationMs';

  Map<String, dynamic> toMap() => {
        _keyTitleFontSize: titleFontSize,
        _keySubtitleFontSize: subtitleFontSize,
        _keyContentFontSize: contentFontSize,
        _keyTitleColor: titleColor.toARGB32(),
        _keySubtitleColor: subtitleColor.toARGB32(),
        _keyContentColor: contentColor.toARGB32(),
        _keyBackgroundColor: backgroundColor.toARGB32(),
        _keyShowAppIcon: showAppIcon,
        _keyShowTimestamp: showTimestamp,
        _keyCameraAvoidance: cameraAvoidanceEnabled,
        _keyUseOfficialBg: useOfficialBackground,
        _keyPadding: padding,
        _keySpacing: spacing,
        _keyDisplayDurationMs: displayDurationMs,
      };

  factory NotificationStyle.fromMap(Map<String, dynamic> map) {
    return NotificationStyle(
      titleFontSize: (map[_keyTitleFontSize] as num?)?.toDouble() ?? 28,
      subtitleFontSize: (map[_keySubtitleFontSize] as num?)?.toDouble() ?? 20,
      contentFontSize: (map[_keyContentFontSize] as num?)?.toDouble() ?? 16,
      titleColor: Color(map[_keyTitleColor] as int? ?? 0xFFFFFFFF),
      subtitleColor: Color(map[_keySubtitleColor] as int? ?? 0xFFB0B0B0),
      contentColor: Color(map[_keyContentColor] as int? ?? 0xFFE0E0E0),
      backgroundColor: Color(map[_keyBackgroundColor] as int? ?? 0xFF1A1A2E),
      showAppIcon: map[_keyShowAppIcon] as bool? ?? true,
      showTimestamp: map[_keyShowTimestamp] as bool? ?? true,
      cameraAvoidanceEnabled: map[_keyCameraAvoidance] as bool? ?? true,
      useOfficialBackground: map[_keyUseOfficialBg] as bool? ?? false,
      padding: (map[_keyPadding] as num?)?.toDouble() ?? 24,
      spacing: (map[_keySpacing] as num?)?.toDouble() ?? 12,
      displayDurationMs: map[_keyDisplayDurationMs] as int? ?? 10000,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final map = toMap();
    map.forEach((key, value) {
      if (value is double) {
        prefs.setDouble(key, value);
      } else if (value is int) {
        prefs.setInt(key, value);
      } else if (value is bool) {
        prefs.setBool(key, value);
      }
    });
  }

  static Future<NotificationStyle> load() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final key in [
      _keyTitleFontSize,
      _keySubtitleFontSize,
      _keyContentFontSize,
      _keyPadding,
      _keySpacing,
    ]) {
      map[key] = prefs.getDouble(key);
    }
    for (final key in [
      _keyTitleColor,
      _keySubtitleColor,
      _keyContentColor,
      _keyBackgroundColor,
    ]) {
      map[key] = prefs.getInt(key);
    }
    for (final key in [_keyShowAppIcon, _keyShowTimestamp, _keyCameraAvoidance, _keyUseOfficialBg]) {
      map[key] = prefs.getBool(key);
    }
    map[_keyDisplayDurationMs] = prefs.getInt(_keyDisplayDurationMs);
    return NotificationStyle.fromMap(map);
  }

  /// 生成传给 Native BackScreenNotificationActivity 的 Intent extras（仅样式，不含内容字段）
  Map<String, String> toIntentExtras() {
    return {
      'titleFontSize': titleFontSize.toStringAsFixed(1),
      'subtitleFontSize': subtitleFontSize.toStringAsFixed(1),
      'contentFontSize': contentFontSize.toStringAsFixed(1),
      'titleColor': titleColor.toARGB32().toRadixString(16),
      'subtitleColor': subtitleColor.toARGB32().toRadixString(16),
      'contentColor': contentColor.toARGB32().toRadixString(16),
      'backgroundColor': backgroundColor.toARGB32().toRadixString(16),
      'showAppIcon': showAppIcon.toString(),
      'showTimestamp': showTimestamp.toString(),
      'cameraAvoidanceEnabled': cameraAvoidanceEnabled.toString(),
      'horizontalOffset': cameraAvoidanceOffset.toStringAsFixed(0),
      'padding': padding.toStringAsFixed(0),
      'spacing': spacing.toStringAsFixed(0),
      'displayDurationMs': displayDurationMs.toString(),
      'useOfficialBackground': useOfficialBackground.toString(),
    };
  }

  NotificationStyle copyWith({
    double? titleFontSize,
    double? subtitleFontSize,
    double? contentFontSize,
    Color? titleColor,
    Color? subtitleColor,
    Color? contentColor,
    Color? backgroundColor,
    bool? showAppIcon,
    bool? showTimestamp,
    bool? cameraAvoidanceEnabled,
    bool? useOfficialBackground,
    double? padding,
    double? spacing,
    int? displayDurationMs,
  }) {
    return NotificationStyle(
      titleFontSize: titleFontSize ?? this.titleFontSize,
      subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
      contentFontSize: contentFontSize ?? this.contentFontSize,
      titleColor: titleColor ?? this.titleColor,
      subtitleColor: subtitleColor ?? this.subtitleColor,
      contentColor: contentColor ?? this.contentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      showAppIcon: showAppIcon ?? this.showAppIcon,
      showTimestamp: showTimestamp ?? this.showTimestamp,
      cameraAvoidanceEnabled: cameraAvoidanceEnabled ?? this.cameraAvoidanceEnabled,
      useOfficialBackground: useOfficialBackground ?? this.useOfficialBackground,
      padding: padding ?? this.padding,
      spacing: spacing ?? this.spacing,
      displayDurationMs: displayDurationMs ?? this.displayDurationMs,
    );
  }
}
