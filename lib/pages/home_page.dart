import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/native_service.dart';
import '../services/content_parser.dart';
import '../services/scene_icons.dart';
import 'settings_page.dart';
import 'notification_style_page.dart';
import '../models/notification_style.dart';
import '../main.dart';
import '../widgets/slide_route.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _nativeService = NativeService();
  final _textController = TextEditingController();
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();

  bool _isShizukuRunning = false;
  bool _hasShizukuPermission = false;
  bool _isForwarding = false;
  ParsedContent? _parsed;

  String _now() {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _listenNotificationEvents();
    _listenSharedContent();
  }

  /// 监听通知移除事件 — 通知被清除时同步关闭背屏
  void _listenNotificationEvents() {
    _nativeService.eventStream.listen((event) {
      if (event is Map) {
        final type = event['type'] as String?;
        final pkg = event['packageName'] as String?;
        if (type == 'removed' && pkg == 'com.example.fbs') {
          _nativeService.dismissBackScreen();
        }
      }
    });
  }

  /// 监听系统复制菜单 / 分享菜单传入的内容 — 自动解析并转发到背屏+超级岛
  void _listenSharedContent() {
    _nativeService.onSharedContent.listen((shared) async {
      if (!mounted) return;

      if (shared.type == 'image' && shared.imageUri != null) {
        // 新流程：图片分享 → OCR识别 → 解析 → 转发到超级岛+背屏
        await _processSharedImage(shared.imageUri!);
      } else if (shared.text != null && shared.text!.trim().isNotEmpty) {
        // 文本：自动解析 → 转发到背屏 + 超级岛
        final text = shared.text!.trim();
        final parsed = ContentParser.parse(text);
        final style = await NotificationStyle.load();
        final styleMap = {
          'titleFontSize': style.titleFontSize.toString(),
          'subtitleFontSize': style.subtitleFontSize.toString(),
          'contentFontSize': style.contentFontSize.toString(),
          'titleColor': '#${style.titleColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
          'subtitleColor': '#${style.subtitleColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
          'contentColor': '#${style.contentColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
          'backgroundColor': '#${style.backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
          'showAppIcon': style.showAppIcon.toString(),
          'showTimestamp': style.showTimestamp.toString(),
          'cameraAvoidanceEnabled': style.cameraAvoidanceEnabled.toString(),
          'horizontalOffset': NotificationStyle.cameraAvoidanceOffset.toStringAsFixed(0),
          'padding': style.padding.toString(),
          'spacing': style.spacing.toString(),
          'displayDurationMs': style.displayDurationMs.toString(),
        };

        // 转发到背屏
        await _nativeService.displayOnBackScreen(
          title: parsed.title,
          subtitle: parsed.subtitle,
          content: text,
          styleExtras: styleMap,
          category: parsed.category.name,
        );
        // 转发到超级岛 — 取餐码/取件码拼接到标题
        final codeInfo = parsed.keyInfos
            .where((k) => k.type == KeyType.code)
            .firstOrNull;
        final islandTitle = codeInfo != null
            ? '${parsed.title} · ${codeInfo.value}'
            : parsed.title;
        final islandContent = parsed.subtitle.isNotEmpty ? parsed.subtitle : text;
        await _nativeService.sendSuperIslandNotification(
          title: islandTitle,
          content: islandContent,
          category: parsed.category.name,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已转发: ${parsed.title} [${_now()}]'),
            duration: const Duration(seconds: 2),
          ));
        }
      }
    });
  }

  /// 处理分享的图片：OCR识别 → 解析 → 转发到超级岛+背屏
  Future<void> _processSharedImage(String imageUri) async {
    if (!mounted) return;
    
    // 显示加载提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在识别图片文字... [${_now()}]'),
        duration: const Duration(seconds: 3),
      ),
    );
    
    try {
      // 1. 调用原生OCR识别图片文字
      final ocrResult = await _nativeService.recognizeImageText(imageUri);
      
      if (!ocrResult.success || ocrResult.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('识别失败: ${ocrResult.errorMessage} [${_now()}]'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      
      // 2. 使用ContentParser解析识别结果
      final parsed = ContentParser.parse(ocrResult.text);
      
      // 3. 获取背屏样式
      final style = await NotificationStyle.load();
      final styleMap = {
        'titleFontSize': style.titleFontSize.toString(),
        'subtitleFontSize': style.subtitleFontSize.toString(),
        'contentFontSize': style.contentFontSize.toString(),
        'titleColor': '#${style.titleColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'subtitleColor': '#${style.subtitleColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'contentColor': '#${style.contentColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'backgroundColor': '#${style.backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'showAppIcon': style.showAppIcon.toString(),
        'showTimestamp': style.showTimestamp.toString(),
        'cameraAvoidanceEnabled': style.cameraAvoidanceEnabled.toString(),
        'horizontalOffset': NotificationStyle.cameraAvoidanceOffset.toStringAsFixed(0),
        'padding': style.padding.toString(),
        'spacing': style.spacing.toString(),
        'displayDurationMs': style.displayDurationMs.toString(),
      };
      
      // 4. 转发到背屏
      await _nativeService.displayOnBackScreen(
        title: parsed.title,
        subtitle: parsed.subtitle,
        content: parsed.body,
        styleExtras: styleMap,
        category: parsed.category.name,
      );
      
      // 5. 转发到超级岛 — 优先显示提取到的关键码值
      final codeInfo = parsed.keyInfos
          .where((k) => k.type == KeyType.code)
          .firstOrNull;
      final islandTitle = codeInfo != null
          ? '${parsed.title} · ${codeInfo.value}'
          : parsed.title;
      final islandContent = parsed.subtitle.isNotEmpty ? parsed.subtitle : parsed.body;
      await _nativeService.sendSuperIslandNotification(
        title: islandTitle,
        content: islandContent,
        category: parsed.category.name,
      );
      
      // 6. 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已识别并转发: ${parsed.title} [${_now()}]'),
          duration: const Duration(seconds: 2),
        ));
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('处理失败: $e [${_now()}]'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _refreshStatus() async {
    final shizukuRunning = await _nativeService.isShizukuRunning();
    final shizukuPerm = await _nativeService.hasShizukuPermission();
    if (mounted) setState(() { _isShizukuRunning = shizukuRunning; _hasShizukuPermission = shizukuPerm; });
  }

  Future<void> _requestShizuku() async {
    await _nativeService.requestShizukuPermission();
    // 等待授权对话框，延迟后刷新状态
    await Future.delayed(const Duration(seconds: 3));
    _refreshStatus();
  }

  void _parseContent() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final parsed = ContentParser.parse(text);
    _titleController.text = parsed.title;
    _subtitleController.text = parsed.subtitle;
    setState(() => _parsed = parsed);
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      _textController.text = data.text!;
      _parseContent();
    }
  }

  void _clearAll() {
    _textController.clear();
    _titleController.clear();
    _subtitleController.clear();
    setState(() => _parsed = null);
  }

  void _handleAction(ActionItem action) {
    switch (action.type) {
      case ActionType.copy:
        Clipboard.setData(ClipboardData(text: action.data ?? ''));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已复制: ${action.data}'), duration: const Duration(seconds: 2)),
          );
        }
      case ActionType.call:
        Clipboard.setData(ClipboardData(text: action.data ?? ''));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('号码 ${action.data} 已复制到剪贴板'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      case ActionType.open:
        Clipboard.setData(ClipboardData(text: action.data ?? ''));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('链接已复制到剪贴板'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      case ActionType.mail:
        Clipboard.setData(ClipboardData(text: action.data ?? ''));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('邮箱 ${action.data} 已复制到剪贴板'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      default:
        break;
    }
  }

  Future<void> _forwardAll() async => _doForward(true);

  Future<void> _doForward(bool showAnimation) async {
    if (_isForwarding) return;
    setState(() => _isForwarding = true);

    final title = _titleController.text.trim();
    final subtitle = _subtitleController.text.trim();
    final content = _textController.text.trim();
    final style = await NotificationStyle.load();
    // 转成背屏 Activity 期待的 key/value 格式
    final styleMap = {
      'titleFontSize': style.titleFontSize.toString(),
      'subtitleFontSize': style.subtitleFontSize.toString(),
      'contentFontSize': style.contentFontSize.toString(),
      'titleColor': '#${style.titleColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
      'subtitleColor': '#${style.subtitleColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
      'contentColor': '#${style.contentColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
      'backgroundColor': '#${style.backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
      'showAppIcon': style.showAppIcon.toString(),
      'showTimestamp': style.showTimestamp.toString(),
      'cameraAvoidanceEnabled': style.cameraAvoidanceEnabled.toString(),
      'horizontalOffset': NotificationStyle.cameraAvoidanceOffset.toStringAsFixed(0),
      'padding': style.padding.toString(),
      'spacing': style.spacing.toString(),
      'displayDurationMs': style.displayDurationMs.toString(),
    };

    try {
      await _nativeService.displayOnBackScreen(
        title: title, subtitle: subtitle, content: content,
        styleExtras: styleMap,
        category: _parsed?.category.name ?? 'general',
      );
      if (showAnimation) {
        // 超级岛标题拼接取餐码/取件码
        final parsedTitle = _parsed?.title ?? title;
        final codeInfo = _parsed?.keyInfos
            .where((k) => k.type == KeyType.code)
            .firstOrNull;
        final islandTitle = codeInfo != null
            ? '$parsedTitle · ${codeInfo.value}'
            : parsedTitle;
        final islandContent = subtitle.isNotEmpty ? subtitle : content;
        await _nativeService.sendSuperIslandNotification(
          title: islandTitle,
          content: islandContent,
          category: _parsed?.category.name ?? 'general',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(showAnimation ? '已转发到背屏 + 超级岛' : '已静默更新背屏'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('转发失败: $e')));
    } finally {
      if (mounted) setState(() => _isForwarding = false);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    _subtitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FBS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, SlideRoute(builder: (_) => const SettingsPage())).then((_) => _refreshStatus()),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusBar(),
            const SizedBox(height: 12),
            _buildInputArea(),
            const SizedBox(height: 8),
            _buildToolbar(),
            if (_parsed != null) ...[
              const SizedBox(height: 12),
              _buildParsedResult(),
            ],
            const SizedBox(height: 16),
            _buildForwardButtons(),
            const SizedBox(height: 10),
            _buildSecondaryActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final shizukuOk = _isShizukuRunning && _hasShizukuPermission;
    if (shizukuOk) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = isDark ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500);
    final label = _isShizukuRunning ? 'Shizuku 未授权' : 'Shizuku 未运行';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlassTokens.radiusLG),
        color: statusColor.withValues(alpha: isDark ? 0.08 : 0.06),
        border: Border.all(
          color: statusColor.withValues(alpha: isDark ? 0.15 : 0.20),
          width: 0.5,
        ),
      ),
      child: Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
                boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.4), blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: statusColor,
            ))),
            if (_isShizukuRunning)
              _glassTinyButton('授权', _requestShizuku),
          ]),
      );
  }

  Widget _glassTinyButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
          color: GlassTokens.accent.withValues(alpha: 0.15),
          border: Border.all(color: GlassTokens.accent.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: GlassTokens.accent)),
      ),
    );
  }

  Widget _buildInputArea() {
    return TextField(
      controller: _textController,
      maxLines: 6,
      decoration: const InputDecoration(
        hintText: '粘贴内容，自动提取关键信息...',
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(GlassTokens.radiusSM))),
        contentPadding: EdgeInsets.all(14),
      ),
      style: const TextStyle(fontSize: 14),
    );
  }

  Widget _buildToolbar() {
    return Row(children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.clear, size: 16),
        label: const Text('清空'),
        onPressed: _textController.text.isEmpty && _parsed == null ? null : _clearAll,
      ),
      const SizedBox(width: GlassTokens.spaceSM),
      Expanded(child: OutlinedButton.icon(
        icon: const Icon(Icons.content_paste, size: 16),
        label: const Text('从剪贴板粘贴'),
        onPressed: _pasteFromClipboard,
      )),
      const SizedBox(width: GlassTokens.spaceSM),
      ElevatedButton.icon(
        icon: const Icon(Icons.auto_fix_high, size: 16),
        label: const Text('解析'),
        onPressed: _parseContent,
      ),
    ]);
  }

  Widget _buildParsedResult() {
    final p = _parsed!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlassTokens.radiusLG),
        gradient: GlassTokens.glassGradient(Theme.of(context).brightness),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.30),
          width: 0.5,
        ),
        boxShadow: GlassTokens.glassShadow(Theme.of(context).brightness),
      ),
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: GlassTokens.accent.withValues(alpha: 0.12),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 14, color: GlassTokens.accent),
                ),
                const SizedBox(width: 8),
                Text('解析结果', style: TextStyle(
                  fontWeight: FontWeight.w600, color: GlassTokens.accent, fontSize: 13,
                )),
                const Spacer(),
                _buildCategoryChip(p.category),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '主标题', border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
                ),
              ),
              const SizedBox(height: GlassTokens.spaceSM),
              TextField(
                controller: _subtitleController,
                decoration: const InputDecoration(
                  labelText: '副标题', border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
                ),
              ),
              if (p.keyInfos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: p.keyInfos.map(_buildKeyInfoChip).toList(),
                ),
              ],
              if (p.actions.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(height: 0.5, color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
                ),
                const SizedBox(height: 10),
                Text('操作', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600], fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: p.actions.map(_buildActionButton).toList(),
                ),
              ],
            ],
          ),
    );
  }

  Widget _buildCategoryChip(ParsedCategory category) {
    final color = SceneIcons.color(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SceneIcons.icon(category, size: 12, color: color),
          const SizedBox(width: 4),
          Text(category.label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildKeyInfoChip(KeyInfo info) {
    final (color, icon) = switch (info.type) {
      KeyType.code => (const Color(0xFFFF9500), Icons.qr_code),
      KeyType.time => (const Color(0xFFAF52DE), Icons.access_time),
      KeyType.order => (const Color(0xFF5AC8FA), Icons.receipt_long),
      KeyType.location => (const Color(0xFF5856D6), Icons.location_on),
      KeyType.amount => (const Color(0xFF34C759), Icons.attach_money),
      KeyType.phone => (const Color(0xFF0088FF), Icons.phone),
      KeyType.link => (const Color(0xFF32D74B), Icons.link),
      KeyType.email => (const Color(0xFFFF375F), Icons.email),
      KeyType.name => (const Color(0xFFAF52DE), Icons.person),
      KeyType.general => (const Color(0xFF8E8E93), Icons.label),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text('${info.label}: ${info.value}',
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildActionButton(ActionItem action) {
    final (icon, color) = switch (action.type) {
      ActionType.copy => (Icons.content_copy, const Color(0xFFFF9500)),
      ActionType.call => (Icons.phone, const Color(0xFF34C759)),
      ActionType.open => (Icons.open_in_new, const Color(0xFF0088FF)),
      ActionType.mail => (Icons.email, const Color(0xFFFF375F)),
      ActionType.navigate => (Icons.directions, const Color(0xFF5856D6)),
    };
    return GestureDetector(
      onTap: () => _handleAction(action),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
          border: Border.all(color: color.withValues(alpha: 0.15), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(action.label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildForwardButtons() {
    final canForward = _isShizukuRunning && _hasShizukuPermission && _titleController.text.trim().isNotEmpty;
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton.icon(
        icon: _isForwarding
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send_rounded),
        label: Text(_isForwarding ? '转发中...' : '转发到背屏 + 超级岛'),
        onPressed: canForward && !_isForwarding ? _forwardAll : null,
      ),
    );
  }

  Widget _buildSecondaryActions() {
    return Row(children: [
      Expanded(child: _buildGlassAction(
        icon: Icons.cleaning_services,
        label: '清除',
        onTap: () async {
          await _nativeService.dismissBackScreen();
          await _nativeService.cancelSuperIslandNotification();
        },
      )),
      const SizedBox(width: 8),
      Expanded(child: _buildGlassAction(
        icon: Icons.image_outlined,
        label: '图片',
        enabled: _isShizukuRunning && _hasShizukuPermission && _titleController.text.trim().isNotEmpty,
        onTap: () async {
          final r = await _nativeService.sendImagePin(
            title: _titleController.text.trim(),
            subtitle: _subtitleController.text.trim(),
            content: _textController.text.trim(),
          );
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('图片贴背屏: $r')));
        },
      )),
      const SizedBox(width: 8),
      Expanded(child: _buildGlassAction(
        icon: Icons.palette_outlined,
        label: '样式',
        onTap: () async {
          final style = await NotificationStyle.load();
          if (!mounted) return;
          Navigator.push(context,
            SlideRoute(builder: (_) => NotificationStylePage(initialStyle: style)));
        },
      )),
    ]);
  }

  Widget _buildGlassAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
          color: enabled
            ? (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.35))
            : (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white.withValues(alpha: 0.15)),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.22),
            width: 0.5,
          ),
        ),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20,
            color: enabled
              ? (isDark ? Colors.white54 : Colors.black54)
              : (isDark ? Colors.white24 : Colors.black26),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w500,
            color: enabled
              ? (isDark ? Colors.white54 : Colors.black54)
              : (isDark ? Colors.white24 : Colors.black26),
          )),
        ],
      ),
    ),
  );
  }
}
