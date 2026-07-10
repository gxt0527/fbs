import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/native_service.dart';
import '../services/content_parser.dart';
import 'settings_page.dart';
import 'notification_style_page.dart';
import '../models/notification_style.dart';

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

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _listenNotificationEvents();
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
      );
      if (showAnimation) {
        await _nativeService.sendSuperIslandNotification(
          title: title,
          content: subtitle.isNotEmpty ? subtitle : content,
          iconName: _parsed?.category.name ?? 'general',
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
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())).then((_) => _refreshStatus()),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusBar(),
            const SizedBox(height: 16),
            _buildInputArea(),
            const SizedBox(height: 8),
            _buildToolbar(),
            if (_parsed != null) ...[
              const SizedBox(height: 16),
              _buildParsedResult(),
            ],
            const SizedBox(height: 24),
            _buildForwardButtons(),
            const SizedBox(height: 8),
            _buildDismissButton(),
            const SizedBox(height: 8),
            _buildImagePinSingleButton(),
            const SizedBox(height: 8),
            _buildStyleButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final shizukuOk = _isShizukuRunning && _hasShizukuPermission;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: shizukuOk ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: shizukuOk ? Colors.green.shade200 : Colors.orange.shade200),
      ),
      child: Row(children: [
        Icon(shizukuOk ? Icons.check_circle : Icons.warning_amber, size: 18,
            color: shizukuOk ? Colors.green : Colors.orange),
        const SizedBox(width: 8),
        Expanded(child: Text(
          shizukuOk ? 'Shizuku 已连接' : _isShizukuRunning ? 'Shizuku 未授权' : 'Shizuku 未运行',
          style: TextStyle(fontSize: 13, color: shizukuOk ? Colors.green.shade800 : Colors.orange.shade800),
        )),
        if (_isShizukuRunning && !_hasShizukuPermission)
          TextButton(
            onPressed: _requestShizuku,
            child: const Text('授权', style: TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _buildInputArea() {
    return TextField(
      controller: _textController,
      maxLines: 6,
      decoration: InputDecoration(
        hintText: '粘贴内容，自动提取关键信息...',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.all(12),
      ),
      style: const TextStyle(fontSize: 14),
    );
  }

  Widget _buildToolbar() {
    return Row(children: [
      Expanded(child: OutlinedButton.icon(
        icon: const Icon(Icons.content_paste, size: 16),
        label: const Text('从剪贴板粘贴'),
        onPressed: _pasteFromClipboard,
      )),
      const SizedBox(width: 8),
      ElevatedButton.icon(
        icon: const Icon(Icons.auto_fix_high, size: 16),
        label: const Text('解析'),
        onPressed: _parseContent,
      ),
    ]);
  }

  Widget _buildParsedResult() {
    final p = _parsed!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 标题 + 场景标签 ──
          Row(children: [
            Icon(Icons.auto_awesome, size: 16, color: Colors.blue.shade700),
            const SizedBox(width: 6),
            Text('解析结果', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700, fontSize: 13)),
            const Spacer(),
            _buildCategoryChip(p.category),
          ]),
          const SizedBox(height: 10),
          // ── 标题 ──
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '主标题', border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          // ── 副标题 ──
          TextField(
            controller: _subtitleController,
            decoration: const InputDecoration(
              labelText: '副标题', border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
            ),
          ),
          // ── 关键信息 Chips ──
          if (p.keyInfos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: p.keyInfos.map(_buildKeyInfoChip).toList(),
            ),
          ],
          // ── 动作按钮 ──
          if (p.actions.isNotEmpty) ...[
            const Divider(height: 20),
            Text('操作', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
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
    final (color, bg, border, icon) = switch (category) {
      ParsedCategory.express => (const Color(0xFFE65100), const Color(0xFFFFF3E0), const Color(0xFFFFE0B2), Icons.local_shipping),
      ParsedCategory.foodDelivery => (const Color(0xFFE91E63), const Color(0xFFFCE4EC), const Color(0xFFF8BBD0), Icons.restaurant),
      ParsedCategory.payment => (const Color(0xFF2E7D32), const Color(0xFFE8F5E9), const Color(0xFFC8E6C9), Icons.account_balance),
      ParsedCategory.meeting => (const Color(0xFF1565C0), const Color(0xFFE3F2FD), const Color(0xFFBBDEFB), Icons.event),
      ParsedCategory.travel => (const Color(0xFF6A1B9A), const Color(0xFFF3E5F5), const Color(0xFFE1BEE7), Icons.flight_takeoff),
      ParsedCategory.verification => (const Color(0xFFE65100), const Color(0xFFFFF3E0), const Color(0xFFFFE0B2), Icons.enhanced_encryption),
      ParsedCategory.bill => (const Color(0xFF37474F), const Color(0xFFECEFF1), const Color(0xFFCFD8DC), Icons.receipt),
      ParsedCategory.order => (const Color(0xFF00838F), const Color(0xFFE0F7FA), const Color(0xFFB2EBF2), Icons.shopping_cart),
      ParsedCategory.system => (const Color(0xFF546E7A), const Color(0xFFECEFF1), const Color(0xFFCFD8DC), Icons.settings),
      ParsedCategory.general => (const Color(0xFF616161), const Color(0xFFF5F5F5), const Color(0xFFE0E0E0), Icons.notifications),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(category.label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildKeyInfoChip(KeyInfo info) {
    final (color, bg, border, icon) = switch (info.type) {
      KeyType.code => (Colors.orange.shade800, Colors.orange.shade50, Colors.orange.shade200, Icons.qr_code),
      KeyType.time => (Colors.purple.shade700, Colors.purple.shade50, Colors.purple.shade200, Icons.access_time),
      KeyType.order => (Colors.teal.shade800, Colors.teal.shade50, Colors.teal.shade200, Icons.receipt_long),
      KeyType.location => (Colors.indigo.shade800, Colors.indigo.shade50, Colors.indigo.shade200, Icons.location_on),
      KeyType.amount => (Colors.green.shade800, Colors.green.shade50, Colors.green.shade200, Icons.attach_money),
      KeyType.phone => (Colors.blue.shade800, Colors.blue.shade50, Colors.blue.shade200, Icons.phone),
      KeyType.link => (Colors.cyan.shade800, Colors.cyan.shade50, Colors.cyan.shade200, Icons.link),
      KeyType.email => (Colors.red.shade800, Colors.red.shade50, Colors.red.shade200, Icons.email),
      KeyType.name => (Colors.purple.shade800, Colors.purple.shade50, Colors.purple.shade200, Icons.person),
      KeyType.general => (Colors.grey.shade700, Colors.grey.shade50, Colors.grey.shade300, Icons.label),
    };
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text('${info.label}: ${info.value}', style: TextStyle(fontSize: 12, color: color)),
      backgroundColor: bg,
      side: BorderSide(color: border),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildActionButton(ActionItem action) {
    final (icon, bg) = switch (action.type) {
      ActionType.copy => (Icons.content_copy, Colors.orange.shade50),
      ActionType.call => (Icons.phone, Colors.green.shade50),
      ActionType.open => (Icons.open_in_new, Colors.blue.shade50),
      ActionType.mail => (Icons.email, Colors.red.shade50),
      ActionType.navigate => (Icons.directions, Colors.indigo.shade50),
    };
    return ActionChip(
      avatar: Icon(icon, size: 14, color: Colors.grey.shade700),
      label: Text(action.label, style: const TextStyle(fontSize: 12)),
      backgroundColor: bg,
      side: BorderSide(color: Colors.grey.shade300),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      onPressed: () => _handleAction(action),
    );
  }

  Widget _buildForwardButtons() {
    final canForward = _isShizukuRunning && _hasShizukuPermission && _titleController.text.trim().isNotEmpty;
    return SizedBox(width: double.infinity, height: 48,
      child: ElevatedButton.icon(
        icon: _isForwarding
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send),
        label: Text(_isForwarding ? '转发中...' : '转发到背屏 + 超级岛'),
        style: ElevatedButton.styleFrom(
          backgroundColor: canForward ? Colors.blue : Colors.grey,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: canForward && !_isForwarding ? _forwardAll : null,
      ),
    );
  }

  Widget _buildDismissButton() {
    return SizedBox(
      width: double.infinity, height: 40,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.cleaning_services, size: 18),
        label: const Text('清除背屏'),
        onPressed: () async {
          await _nativeService.dismissBackScreen();
          await _nativeService.cancelSuperIslandNotification();
        },
      ),
    );
  }

  Widget _buildTestPinButton() {
    return SizedBox(width: double.infinity, height: 40,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.bug_report, size: 18),
        label: const Text('测试写 pin_info.json'),
        onPressed: () async {
          final r = await _nativeService.testPinWrite();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PinWrite: $r')),
          );
        },
      ),
    );
  }

  Widget _buildImagePinSingleButton() {
    final canForward = _isShizukuRunning && _hasShizukuPermission && _titleController.text.trim().isNotEmpty;
    return SizedBox(width: double.infinity, height: 40,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.image, size: 18),
        label: const Text('图片贴背屏'),
        onPressed: canForward ? () async {
          final r = await _nativeService.sendImagePin(
            title: _titleController.text.trim(),
            subtitle: _subtitleController.text.trim(),
            content: _textController.text.trim(),
          );
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('图片贴背屏: $r')));
        } : null,
      ),
    );
  }

  Widget _buildStyleButton() {
    return SizedBox(width: double.infinity, height: 40,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.palette, size: 18),
        label: const Text('背屏样式'),
        onPressed: () async {
          final style = await NotificationStyle.load();
          if (!mounted) return;
          Navigator.push(context,
            MaterialPageRoute(builder: (_) => NotificationStylePage(initialStyle: style)));
        },
      ),
    );
  }
}
