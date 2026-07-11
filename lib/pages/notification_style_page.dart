import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math' as math show pi, sin, cos, atan2;
import 'dart:ui' as ui;
import '../models/notification_style.dart';
import '../main.dart';

/// 背屏通知样式定制页 + 实时预览画布

enum ColorTarget { title, subtitle, content, background }

class NotificationStylePage extends StatefulWidget {
  final NotificationStyle initialStyle;

  const NotificationStylePage({super.key, required this.initialStyle});

  @override
  State<NotificationStylePage> createState() => _NotificationStylePageState();
}

class _NotificationStylePageState extends State<NotificationStylePage> {
  late NotificationStyle _style;
  ColorTarget _selectedColorTarget = ColorTarget.title;

  // 色轮局部状态（跨重建持久化，避免切换目标后坐标错乱）
  double _wheelHue = 0;
  double _wheelSat = 0;
  double _wheelValue = 1.0; // 明度 V，配合亮度滑块选择白/灰/黑
  ColorTarget? _wheelSyncedTarget;

  // 色轮预渲染图片缓存（只算一次，滚动不再重绘）
  static ui.Image? _wheelImageCache;

  // 预览用的模拟数据
  static const _previewTitle = '微信';
  static const _previewSubtitle = '张三';
  static const _previewContent = '晚上一起吃饭吗？';

  /// 当前选中的颜色目标对应的值
  Color get _currentColor {
    switch (_selectedColorTarget) {
      case ColorTarget.title: return _style.titleColor;
      case ColorTarget.subtitle: return _style.subtitleColor;
      case ColorTarget.content: return _style.contentColor;
      case ColorTarget.background: return _style.backgroundColor;
    }
  }

  set _currentColor(Color c) {
    switch (_selectedColorTarget) {
      case ColorTarget.title: _style.titleColor = c;
      case ColorTarget.subtitle: _style.subtitleColor = c;
      case ColorTarget.content: _style.contentColor = c;
      case ColorTarget.background: _style.backgroundColor = c;
    }
  }

  @override
  void initState() {
    super.initState();
    _style = widget.initialStyle;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.restore_outlined),
            tooltip: '恢复默认',
            onPressed: () {
              setState(() {
                _style = NotificationStyle();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '保存',
            onPressed: () async {
              await _style.save();
              if (mounted) {
                Navigator.of(context).pop(_style);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 预览窗固定，不随设置项上下滑动
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _buildPreviewSection(),
          ),
          const SizedBox(height: GlassTokens.spaceLG),
          // 设置项区域可上下滑动
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
          _buildSectionHeader('文字字号', Icons.format_size, GlassTokens.accent),
          _buildSlider(
            label: '大标题', value: _style.titleFontSize,
            min: 14, max: 56,
            onChanged: (v) => setState(() => _style.titleFontSize = v),
          ),
          _buildSlider(
            label: '副标题', value: _style.subtitleFontSize,
            min: 12, max: 48,
            onChanged: (v) => setState(() => _style.subtitleFontSize = v),
          ),
          _buildSlider(
            label: '正文', value: _style.contentFontSize,
            min: 10, max: 40,
            onChanged: (v) => setState(() => _style.contentFontSize = v),
          ),
          const SizedBox(height: GlassTokens.spaceMD),

          _buildSectionHeader('文本颜色', Icons.palette_outlined, const Color(0xFFAF52DE)),
          _buildColorSegmentedControl(),
          if (_selectedColorTarget == ColorTarget.background) ...[
            const SizedBox(height: GlassTokens.spaceSM),
            _glassSwitchTile(
              title: '使用官方背景',
              subtitle: '背屏渐变底色，关闭后可自定义颜色',
              value: _style.useOfficialBackground,
              onChanged: (v) {
                debugPrint('[FBS-TOGGLE] useOfficialBg=$v');
                setState(() => _style.useOfficialBackground = v);
              },
            ),
          ],
          if (!(_selectedColorTarget == ColorTarget.background && _style.useOfficialBackground)) ...[
            const SizedBox(height: GlassTokens.spaceSM),
            _buildColorWheel(),
          ],
          const SizedBox(height: GlassTokens.spaceMD),

          _buildSectionHeader('布局', Icons.grid_view_rounded, const Color(0xFF34C759)),
          _buildSlider(
            label: '内边距', value: _style.padding,
            min: 8, max: 64, divisions: 28,
            onChanged: (v) => setState(() => _style.padding = v),
          ),
          _buildSlider(
            label: '行间距', value: _style.spacing,
            min: 2, max: 40, divisions: 38,
            onChanged: (v) => setState(() => _style.spacing = v),
          ),
          const SizedBox(height: GlassTokens.spaceMD),

          _buildSectionHeader('显示选项', Icons.tune, const Color(0xFFFF9500)),
          _glassSwitchTile(
            title: '智能场景图标',
            value: _style.showAppIcon,
            onChanged: (v) => setState(() => _style.showAppIcon = v),
          ),
          _glassSwitchTile(
            title: '显示时间戳',
            value: _style.showTimestamp,
            onChanged: (v) => setState(() => _style.showTimestamp = v),
          ),
          _glassSwitchTile(
            title: '避开摄像头',
            value: _style.cameraAvoidanceEnabled,
            onChanged: (v) => setState(() => _style.cameraAvoidanceEnabled = v),
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.spaceSM),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GlassTokens.radiusXS),
            color: color.withValues(alpha: 0.12),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Text(title, style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700, color: color,
        )),
      ]),
    );
  }

  Widget _glassSwitchTile({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.spaceXS),
      child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.30),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.20),
                width: 0.5,
              ),
            ),
            child: SwitchListTile(
              title: Text(title, style: const TextStyle(fontSize: 15)),
              subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)) : null,
              value: value,
              onChanged: onChanged,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
    );
  }

  // ═══════════════════════════════════════════
  // 预览画布
  // ═══════════════════════════════════════════

  Widget _buildPreviewSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('预览', style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
        )),
        const SizedBox(height: 12),
        Center(
          child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 440),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(GlassTokens.radiusLG),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.40),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(GlassTokens.radiusLG - 1),
                  child: AspectRatio(
                    aspectRatio: 244 / 149,
                    child: _buildPreviewCanvas(),
                  ),
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildPreviewCanvas() {
    final bgColor = _style.backgroundColor;
    final leftOffset =
        _style.cameraAvoidanceEnabled ? NotificationStyle.cameraAvoidanceOffset : 0.0;

    debugPrint('[FBS-PREVIEW] useOfficialBg=${_style.useOfficialBackground} bgColor=${bgColor.toARGB32().toRadixString(16)}');

    return Stack(
      children: [
        // 官方背景渐变层
        if (_style.useOfficialBackground) ...[
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: const [
                    Color(0xFFC87018),
                    Color(0xFF8A300F),
                    Color(0xFF7B2007),
                    Color(0xFF571504),
                    Color(0xFF210401),
                    Color(0xFF000000),
                  ],
                  stops: [0.0, 0.30, 0.42, 0.55, 0.75, 1.0],
                ),
              ),
            ),
          ),
        ]
        else
          Positioned.fill(child: Container(color: bgColor)),
        // 摄像头避开区域 — 左侧阴影遮罩
        if (_style.cameraAvoidanceEnabled)
            Positioned(
              left: 0, top: 0, bottom: 0,
              width: NotificationStyle.cameraAvoidanceOffset,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.08),
                  border: Border(
                    right: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 1,
                    ),
                  ),
                ),
                child: const Center(
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Text(
                      '摄像头区域',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // 内容区域（右移 leftOffset）
          Positioned(
            left: _style.padding + leftOffset,
            right: _style.padding,
            top: _style.padding,
            bottom: _style.padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
          // ── 场景图标行 ──
          if (_style.showAppIcon)
            Padding(
              padding: EdgeInsets.only(bottom: _style.spacing),
              child: Row(
                children: [
                  Container(
                    width: _style.titleFontSize + 8,
                    height: _style.titleFontSize + 8,
                    padding: EdgeInsets.all((_style.titleFontSize + 8) * 0.16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: const Color(0xFFFF375F).withValues(alpha: 0.13),
                    ),
                    child: SvgPicture.asset(
                      'assets/icons/ic_beverage_pickup.svg',
                      colorFilter: const ColorFilter.mode(Color(0xFFFF375F), BlendMode.srcIn),
                    ),
                  ),
                  SizedBox(width: _style.spacing * 0.7),
                  Text(
                    _previewTitle,
                    style: TextStyle(
                      fontSize: _style.titleFontSize,
                      fontWeight: FontWeight.w600,
                      color: _style.titleColor,
                    ),
                  ),
                ],
              ),
            ),
          // ── 大标题 (无图标时) ──
          if (!_style.showAppIcon)
            Padding(
              padding: EdgeInsets.only(bottom: _style.spacing),
              child: Text(
                _previewTitle,
                style: TextStyle(
                  fontSize: _style.titleFontSize,
                  fontWeight: FontWeight.w600,
                  color: _style.titleColor,
                ),
              ),
            ),
          // ── 副标题 ──
          if (_previewSubtitle.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: _style.spacing),
              child: Text(
                _previewSubtitle,
                style: TextStyle(
                  fontSize: _style.subtitleFontSize,
                  fontWeight: FontWeight.w500,
                  color: _style.subtitleColor,
                ),
              ),
            ),
          // ── 正文 ──
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                _previewContent,
                style: TextStyle(
                  fontSize: _style.contentFontSize,
                  color: _style.contentColor,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // ── 时间戳 ──
          if (_style.showTimestamp)
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.only(top: _style.spacing),
                child: Text(
                  _formatTime(DateTime.now()),
                  style: TextStyle(
                    fontSize: _style.contentFontSize * 0.65,
                    color: _style.contentColor.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ], // Column children end
        ),
      ), // Positioned end
    ], // Stack children end
  );
}

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════
  // 控件构建方法
  // ═══════════════════════════════════════════

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.30),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.20),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  child: Text(label, style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87)),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: GlassTokens.accent,
                      inactiveTrackColor: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06),
                      thumbColor: Colors.white,
                      overlayColor: GlassTokens.accent.withValues(alpha: 0.12),
                      trackHeight: 5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                    ),
                    child: Slider(
                      value: value, min: min, max: max,
                      divisions: divisions,
                      label: value.toStringAsFixed(0),
                      onChanged: onChanged,
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    value.toStringAsFixed(0),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white54 : Colors.black54),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
    );
  }

  // ═══════════════════════════════════════════
  // 文字颜色：分段选择器 + HSV 色轮
  // ═══════════════════════════════════════════

  static const _colorTargetLabels = [
    ColorTarget.title, '大标题',
    ColorTarget.subtitle, '副标题',
    ColorTarget.content, '正文',
    ColorTarget.background, '背景',
  ];

  Widget _buildColorSegmentedControl() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.30),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.20),
          width: 0.5,
        ),
      ),
      child: Row(
        children: List.generate(_colorTargetLabels.length ~/ 2, (i) {
          final target = _colorTargetLabels[i * 2] as ColorTarget;
          final label = _colorTargetLabels[i * 2 + 1] as String;
          final selected = target == _selectedColorTarget;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedColorTarget = target),
              child: Container(
                margin: const EdgeInsets.all(3),
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(GlassTokens.radiusSM - 1),
                  color: selected
                      ? GlassTokens.accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  border: Border.all(
                    color: selected ? GlassTokens.accent : Colors.transparent,
                    width: 1.2,
                  ),
                ),
                child: Text(label, style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? GlassTokens.accent : (isDark ? Colors.white70 : Colors.black54),
                )),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// RGB → HSV，返回 [hue(0-360), sat(0-1), value(0-1)]
  List<double> _rgbToHsv(Color c) {
    final r = (c.r * 255).round() / 255.0;
    final g = (c.g * 255).round() / 255.0;
    final b = (c.b * 255).round() / 255.0;
    final maxV = [r, g, b].reduce((a, b) => a > b ? a : b);
    final minV = [r, g, b].reduce((a, b) => a < b ? a : b);
    final delta = maxV - minV;
    double h = 0;
    if (delta != 0) {
      if (maxV == r) {
        h = 60 * (((g - b) / delta) % 6);
      } else if (maxV == g) {
        h = 60 * (((b - r) / delta) + 2);
      } else {
        h = 60 * (((r - g) / delta) + 4);
      }
    }
    if (h < 0) h += 360;
    final s = maxV == 0 ? 0.0 : delta / maxV;
    return [h, s, maxV];
  }

  /// 预渲染色轮为图片（仅首次调用时计算，之后复用缓存）
  Future<ui.Image> _getWheelImage() async {
    if (_wheelImageCache != null) return _wheelImageCache!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _HsvWheelPainter().paint(canvas, const Size(240, 240));
    final picture = recorder.endRecording();
    _wheelImageCache = await picture.toImage(240, 240);
    return _wheelImageCache!;
  }

  Widget _buildColorWheel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 切换目标时，将色轮局部状态同步到当前目标颜色
    if (_wheelSyncedTarget != _selectedColorTarget) {
      final hsv = _rgbToHsv(_currentColor);
      _wheelHue = hsv[0];
      _wheelSat = hsv[1];
      _wheelValue = hsv[2];
      _wheelSyncedTarget = _selectedColorTarget;
    }

    return StatefulBuilder(builder: (context, setWheelState) {
      void handle(Offset localPos) {
        final pos = localPos - const Offset(120, 120);
        final dist = pos.distance;
        if (dist > 118) return; // 超出有效半径忽略
        final h = ((math.atan2(pos.dy, pos.dx) * 180 / math.pi) % 360 + 360) % 360;
        final s = (dist / 116).clamp(0.0, 1.0);
        setWheelState(() {
          _wheelHue = h;
          _wheelSat = s;
        });
        setState(() {
          // 用与绘制器相同的 HSV→RGB 转换，保留当前明度 V
          _currentColor = _HsvWheelPainter._hsvToRgb(h, s, _wheelValue);
        });
      }

      final indicatorLeft = 120 + (116 - 10) * _wheelSat * math.cos(_wheelHue * math.pi / 180);
      final indicatorTop = 120 + (116 - 10) * _wheelSat * math.sin(_wheelHue * math.pi / 180);

      // 亮度滑块两端颜色：左=黑，右=当前色相/饱和度的全亮色
      final fullBright = _HsvWheelPainter._hsvToRgb(_wheelHue, _wheelSat, 1.0);

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.30),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.20),
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: (d) => handle(d.localPosition),
                      onPanUpdate: (d) => handle(d.localPosition),
                      onPanEnd: (_) {},
                      child: FutureBuilder<ui.Image>(
                        future: _getWheelImage(),
                        builder: (ctx, snap) => snap.hasData
                            ? RawImage(image: snap.data!, width: 240, height: 240)
                            : const SizedBox.shrink(),
                      ),
                    ),
                    Positioned(
                      left: indicatorLeft - 10,
                      top: indicatorTop - 10,
                      child: IgnorePointer(
                        child: Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _currentColor,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 亮度滑块
            Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text('亮度', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)),
                ),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 渐变背景条：黑 → 全亮色
                      Container(
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
                          gradient: LinearGradient(colors: [Colors.black, fullBright]),
                        ),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.transparent,
                          inactiveTrackColor: Colors.transparent,
                          thumbColor: Colors.white,
                          overlayColor: GlassTokens.accent.withValues(alpha: 0.12),
                          trackHeight: 10,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                        ),
                        child: Slider(
                          value: _wheelValue,
                          min: 0.0, max: 1.0,
                          onChanged: (v) {
                            setWheelState(() => _wheelValue = v);
                            setState(() => _currentColor =
                                _HsvWheelPainter._hsvToRgb(_wheelHue, _wheelSat, v));
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  // ── HSV 色轮绘制器 ──
}

class _HsvWheelPainter extends CustomPainter {
  /// 将 HSV 色彩值转换为 Color（不依赖 HSLColor，直接 RGB 计算）
  static Color _hsvToRgb(double h, double s, double v) {
    h = h % 360;
    if (h < 0) h += 360;
    final c = v * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = v - c;
    double r, g, b;
    if (h < 60) { r = c; g = x; b = 0; }
    else if (h < 120) { r = x; g = c; b = 0; }
    else if (h < 180) { r = 0; g = c; b = x; }
    else if (h < 240) { r = 0; g = x; b = c; }
    else if (h < 300) { r = x; g = 0; b = c; }
    else { r = c; g = 0; b = x; }
    return Color.fromARGB(
      255,
      ((r + m) * 255).round().clamp(0, 255),
      ((g + m) * 255).round().clamp(0, 255),
      ((b + m) * 255).round().clamp(0, 255),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;

    // 预生成色相数组（每 1° 一个颜色，V=1.0 全亮度）
    const totalHues = 360;
    final fullSatHues = List.generate(totalHues, (i) => _hsvToRgb(i.toDouble(), 1.0, 1.0));
    // 闭合：首尾相同确保无缝衔接
    final hueColors = [...fullSatHues, fullSatHues[0]];
    final hueStops = List.generate(hueColors.length, (i) => i / (hueColors.length - 1));

    final rect = Rect.fromCircle(center: center, radius: radius);

    // 第1层：全饱和色相环（HSV V=1.0，所有色相等亮度）
    canvas.drawCircle(center, radius, Paint()
      ..shader = SweepGradient(
        startAngle: 0, endAngle: math.pi * 2,
        colors: hueColors, stops: hueStops,
        tileMode: TileMode.clamp,
      ).createShader(rect)
      ..style = PaintingStyle.fill);

    // 第2层：用 120 圈同心弧精确控制饱和度衰减（避免白色叠加导致的色彩失真）
    const satSteps = 120;
    for (int i = satSteps - 1; i >= 1; i--) {
      final ratio = i / satSteps;       // 0.008 ~ 0.99
      final sat = ratio;                 // 该圈的饱和度
      final r = radius * ratio;          // 该圈半径
      // 当前饱和度下的所有色相
      final ringColors = List.generate(totalHues, (h) => _hsvToRgb(h.toDouble(), sat, 1.0));
      final ringAll = [...ringColors, ringColors[0]];

      canvas.drawCircle(center, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (radius / satSteps) + 0.3
        ..shader = SweepGradient(
          startAngle: 0, endAngle: math.pi * 2,
          colors: ringAll,
          stops: hueStops,
          tileMode: TileMode.clamp,
        ).createShader(rect));
    }

    // 中心白色小圆（sat=0）
    canvas.drawCircle(center, radius * 0.02, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
