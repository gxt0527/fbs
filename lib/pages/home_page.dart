import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/native_service.dart';
import '../services/content_parser.dart';
import 'settings_page.dart';

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

  Future<void> _forwardAll() async {
    if (_isForwarding) return;
    setState(() => _isForwarding = true);

    final title = _titleController.text.trim();
    final subtitle = _subtitleController.text.trim();
    final content = _textController.text.trim();

    try {
      await _nativeService.displayOnBackScreen(title: title, subtitle: subtitle, content: content);
      await _nativeService.sendSuperIslandNotification(title: title, content: subtitle.isNotEmpty ? subtitle : content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已转发到背屏 + 超级岛'), duration: Duration(seconds: 2),
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
            _buildForwardButton(),
            const SizedBox(height: 8),
            _buildDismissButton(),
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
          Row(children: [
            Icon(Icons.auto_awesome, size: 16, color: Colors.blue.shade700),
            const SizedBox(width: 6),
            Text('解析结果', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '主标题', border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _subtitleController,
            decoration: const InputDecoration(
              labelText: '副标题', border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
            ),
          ),
          if (p.keyInfos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: p.keyInfos.map((info) {
                final MaterialColor chipColor;
                IconData icon;
                switch (info.type) {
                  case KeyType.code: chipColor = Colors.orange; icon = Icons.qr_code;
                  case KeyType.time: chipColor = Colors.purple; icon = Icons.access_time;
                  case KeyType.order: chipColor = Colors.teal; icon = Icons.receipt_long;
                  case KeyType.location: chipColor = Colors.indigo; icon = Icons.location_on;
                  default: chipColor = Colors.grey; icon = Icons.label;
                }
                return Chip(
                  avatar: Icon(icon, size: 16, color: chipColor),
                  label: Text('${info.label}: ${info.value}', style: TextStyle(fontSize: 12, color: chipColor.shade700)),
                  backgroundColor: chipColor.shade50,
                  side: BorderSide(color: chipColor.shade200),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildForwardButton() {
    final canForward = _isShizukuRunning && _hasShizukuPermission && _titleController.text.trim().isNotEmpty;
    return SizedBox(
      width: double.infinity, height: 48,
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
}
