import 'package:flutter/material.dart';
import '../models/notification_style.dart';

/// 背屏通知样式定制页 + 实时预览画布
class NotificationStylePage extends StatefulWidget {
  final NotificationStyle initialStyle;

  const NotificationStylePage({super.key, required this.initialStyle});

  @override
  State<NotificationStylePage> createState() => _NotificationStylePageState();
}

class _NotificationStylePageState extends State<NotificationStylePage> {
  late NotificationStyle _style;

  // 预览用的模拟数据
  static const _previewTitle = '微信';
  static const _previewSubtitle = '张三';
  static const _previewContent = '晚上一起吃饭吗？';

  @override
  void initState() {
    super.initState();
    _style = widget.initialStyle;
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知样式'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ═══════ 预览画布 ═══════
          _buildPreviewSection(),
          const SizedBox(height: 24),

          // ═══════ 文字字号 ═══════
          _buildSectionTitle('文字字号'),
          _buildSlider(
            label: '大标题',
            value: _style.titleFontSize,
            min: 14,
            max: 56,
            onChanged: (v) => setState(() => _style.titleFontSize = v),
          ),
          _buildSlider(
            label: '副标题',
            value: _style.subtitleFontSize,
            min: 12,
            max: 48,
            onChanged: (v) => setState(() => _style.subtitleFontSize = v),
          ),
          _buildSlider(
            label: '正文',
            value: _style.contentFontSize,
            min: 10,
            max: 40,
            onChanged: (v) => setState(() => _style.contentFontSize = v),
          ),
          const SizedBox(height: 16),

          // ═══════ 文字颜色 ═══════
          _buildSectionTitle('文字颜色'),
          _buildColorPicker(label: '大标题', current: _style.titleColor,
              onChanged: (c) => setState(() => _style.titleColor = c)),
          _buildColorPicker(label: '副标题', current: _style.subtitleColor,
              onChanged: (c) => setState(() => _style.subtitleColor = c)),
          _buildColorPicker(label: '正文', current: _style.contentColor,
              onChanged: (c) => setState(() => _style.contentColor = c)),
          _buildColorPicker(label: '背景', current: _style.backgroundColor,
              onChanged: (c) => setState(() => _style.backgroundColor = c)),
          const SizedBox(height: 16),

          // ═══════ 布局 ═══════
          _buildSectionTitle('布局'),
          _buildSlider(
            label: '内边距',
            value: _style.padding,
            min: 8,
            max: 64,
            divisions: 28,
            onChanged: (v) => setState(() => _style.padding = v),
          ),
          _buildSlider(
            label: '行间距',
            value: _style.spacing,
            min: 2,
            max: 40,
            divisions: 38,
            onChanged: (v) => setState(() => _style.spacing = v),
          ),
          const SizedBox(height: 16),

          // ═══════ 显示选项 ═══════
          _buildSectionTitle('显示选项'),
          SwitchListTile(
            title: const Text('显示应用图标', style: TextStyle(fontSize: 15)),
            value: _style.showAppIcon,
            onChanged: (v) => setState(() => _style.showAppIcon = v),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('显示时间戳', style: TextStyle(fontSize: 15)),
            value: _style.showTimestamp,
            onChanged: (v) => setState(() => _style.showTimestamp = v),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('避开摄像头', style: TextStyle(fontSize: 15)),
            subtitle: Text(
              _style.cameraAvoidanceEnabled
                  ? '内容区域右移 ${NotificationStyle.cameraAvoidanceOffset.toStringAsFixed(0)}dp，背景保持全屏'
                  : '内容全屏显示',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            value: _style.cameraAvoidanceEnabled,
            onChanged: (v) => setState(() => _style.cameraAvoidanceEnabled = v),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          _buildSlider(
            label: '显示时长 (秒)',
            value: (_style.displayDurationMs / 1000).toDouble(),
            min: 3,
            max: 60,
            divisions: 57,
            onChanged: (v) => setState(() =>
                _style.displayDurationMs = (v * 1000).round()),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 预览画布
  // ═══════════════════════════════════════════

  Widget _buildPreviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('预览', style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
            Text(
              '背屏 976×596 (1.64:1)',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 440),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                // 背屏实际比例 976:596 → 244:149
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

    return Container(
      color: bgColor,
      child: Stack(
        children: [
          // 背景全屏
          Positioned.fill(
            child: Container(color: bgColor),
          ),
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
          // ── 应用图标行 ──
          if (_style.showAppIcon)
            Padding(
              padding: EdgeInsets.only(bottom: _style.spacing),
              child: Row(
                children: [
                  Container(
                    width: _style.titleFontSize + 8,
                    height: _style.titleFontSize + 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                          (_style.titleFontSize + 8) * 0.22),
                      color: _style.titleColor.withValues(alpha: 0.2),
                    ),
                    child: Icon(
                      Icons.notifications,
                      size: _style.titleFontSize * 0.6,
                      color: _style.titleColor,
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
  ),
); // Stack + Container end
}

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════
  // 控件构建方法
  // ═══════════════════════════════════════════

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: value.toStringAsFixed(0),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              value.toStringAsFixed(0),
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker({
    required String label,
    required Color current,
    required ValueChanged<Color> onChanged,
  }) {
    // 预设颜色
    const presets = [
      Colors.white,
      Color(0xFFB0B0B0),
      Color(0xFFE0E0E0),
      Color(0xFF1A1A2E),
      Color(0xFF2D2D44),
      Color(0xFF000000),
      Color(0xFFFF6B6B),
      Color(0xFF4ECDC4),
      Color(0xFFFFE66D),
      Color(0xFF7C6FF7),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: presets.map((color) {
                  final isSelected = _colorsSimilar(current, color);
                  return GestureDetector(
                    onTap: () => onChanged(color),
                    child: Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade400,
                          width: isSelected ? 2.5 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Theme.of(context)
                                      .colorScheme.primary.withValues(alpha: 0.4),
                                  blurRadius: 4,
                                )
                              ]
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _colorsSimilar(Color a, Color b) {
    return ((a.r - b.r) * 255).round().abs() < 5 &&
        ((a.g - b.g) * 255).round().abs() < 5 &&
        ((a.b - b.b) * 255).round().abs() < 5;
  }
}
