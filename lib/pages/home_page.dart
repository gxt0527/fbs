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
  bool _isBypassing = false;
  ParsedContent? _parsed;
  String _filteredContent = '';

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
          'useOfficialBackground': style.useOfficialBackground.toString(),
        };
        final displayContent = _buildDisplayContent(text, parsed);
        final codeInfo = parsed.keyInfos
            .where((k) => k.type == KeyType.code)
            .firstOrNull;
        final codeValue = codeInfo?.value ?? parsed.subtitle;
        final islandTitle = codeInfo != null
            ? '${parsed.title} ${codeInfo.value}'
            : parsed.title;

        // 先发超级岛
        await _nativeService.sendSuperIslandNotification(
          title: islandTitle,
          content: displayContent,
          category: parsed.category.name,
        );

        // 延迟100ms再发背屏 — 内容与超级岛一致，subtitle用码值
        await Future.delayed(const Duration(milliseconds: 100));
        await _nativeService.displayOnBackScreen(
          title: parsed.title,
          subtitle: codeValue,
          content: displayContent,
          styleExtras: styleMap,
          category: parsed.category.name,
        );

        _nativeService.showToast('已转发: ${parsed.title}');
      }
    });
  }

  /// 处理分享的图片：OCR识别 → 解析 → 转发到超级岛+背屏
  Future<void> _processSharedImage(String imageUri) async {
    if (!mounted) return;
    
    _nativeService.showToast('正在识别图片文字...');
    
    try {
      // 1. 调用原生OCR识别图片文字
      final ocrResult = await _nativeService.recognizeImageText(imageUri);
      
      if (!ocrResult.success || ocrResult.text.trim().isEmpty) {
        _nativeService.showToast('识别失败: ${ocrResult.errorMessage}');
        return;
      }
      
      // 2. 清洗 OCR 原始文本：去除控制字符、非打印字符、规范化换行
      //    防止 OCR 模型输出的特殊字符导致背屏 Canvas 渲染异常
      final sanitizedText = ContentParser.sanitizeOcrText(ocrResult.text);
      
      // 调试日志：记录 OCR 文本与清洗后的对比
      debugPrint('[FBS-OCR] raw=${ocrResult.text.length}chars/${ocrResult.lineCount}lines, '
          'sanitized=${sanitizedText.length}chars');
      // 检测是否包含特殊字符
      final controlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]');
      final specialChars = RegExp(r'[\u200B-\u200F\u202A-\u202E\uFEFF\uFFFE\uFFFF]');
      final rawHasControl = ocrResult.text.contains(controlChars);
      final rawHasSpecial = ocrResult.text.contains(specialChars);
      if (rawHasControl || rawHasSpecial) {
        debugPrint('[FBS-OCR] WARNING: raw text has control=$rawHasControl special=$rawHasSpecial');
      }
      
      // 3. 使用 ContentParser 解析清洗后的文本
      final parsed = ContentParser.parse(sanitizedText);
      
      // 4. 获取背屏样式
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
        'useOfficialBackground': style.useOfficialBackground.toString(),
      };
      
      // 5. 构建展示内容 — 背屏和超级岛共用
      final displayContent = _buildDisplayContent(sanitizedText, parsed);
      final codeInfo = parsed.keyInfos
          .where((k) => k.type == KeyType.code)
          .firstOrNull;
      final codeValue = codeInfo?.value ?? parsed.subtitle;
      final islandTitle = codeInfo != null
          ? '${parsed.title} ${codeInfo.value}'
          : parsed.title;

      // 6. 先发超级岛
      await _nativeService.sendSuperIslandNotification(
        title: islandTitle,
        content: displayContent,
        category: parsed.category.name,
      );

      // 7. 延迟100ms再发背屏 — 内容与超级岛一致，subtitle用码值
      await Future.delayed(const Duration(milliseconds: 100));
      await _nativeService.displayOnBackScreen(
        title: parsed.title,
        subtitle: codeValue,
        content: displayContent,
        styleExtras: styleMap,
        category: parsed.category.name,
      );
      
      // 8. 显示成功提示
      _nativeService.showToast('已识别并转发: ${parsed.title}');
      
    } catch (e) {
      _nativeService.showToast('处理失败: $e');
    }
  }


  /// 构建统一展示内容（背屏和超级岛共用）
  /// 外卖=产品|店名，快递=取件地址，其他=首行
  String _buildDisplayContent(String sourceText, ParsedContent parsed) {
    final filtered = ContentParser.filterBackScreenContent(sourceText);
    final lines = filtered.split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.trim())
        .toList();
    switch (parsed.category) {
      case ParsedCategory.express:
        return _extractExpressAddress(lines);
      case ParsedCategory.foodDelivery:
        return _extractProductAndShop(lines);
      default:
        return lines.isNotEmpty ? lines.first : '';
    }
  }

  /// 快递场景: 提取 快递品牌 | 取件点
  String _extractExpressAddress(List<String> lines) {
    final expressBrands = {'菜鸟驿站', '菜鸟', '妈妈驿站', '丰巢', '京东快递',
      '圆通', '中通', '韵达', '申通', '顺丰', '极兔', '邮政'};
    
    // 找快递品牌
    String? brand;
    for (final l in lines) {
      for (final b in expressBrands) {
        if (l.contains(b)) { brand = b == '菜鸟' ? '菜鸟驿站' : b; break; }
      }
      if (brand != null) break;
    }
    
    // ── 策略1: "已到"/"已到达" 拼接多行地址（妈妈驿站场景） ──
    String? address;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains('已到') || lines[i].contains('已到达') || lines[i].contains('请到')) {
        final buf = StringBuffer(lines[i]);
        for (var j = i + 1; j < lines.length; j++) {
          final next = lines[j];
          if (next.isEmpty || next.length <= 1) break;
          if (RegExp(r'^(提醒|查看|更多|详情|电话|订单)').hasMatch(next)) break;
          buf.write(next);
        }
        address = buf.toString();
        break;
      }
    }
    if (address != null) {
      final addr = address.length > 24 ? '${address.characters.take(22)}...' : address;
      return brand != null ? '$brand | $addr' : addr;
    }
    
    // ── 策略2: 品牌 + 干净位置行（菜鸟驿站场景） ──
    String? cleanLocation;
    for (final l in lines) {
      // 必须是位置行: 含"店"/"柜"/"驿站"
      if (!l.contains('店') && !l.contains('柜') && !l.contains('驿站')) continue;
      // 跳过非位置行: 含手机号、标题标记、取件码
      if (RegExp(r'1[3-9]\d{9}').hasMatch(l)) continue;
      if (l.contains('【') || l.contains('】')) continue;
      if (l.contains('取件码') || l.contains('取货码')) continue;
      if (l.contains('送达') || l.contains('签收') || l.contains('已取')) continue;
      if (cleanLocation == null || l.length > cleanLocation.length) cleanLocation = l;
    }
    if (brand != null && cleanLocation != null) {
      final loc = cleanLocation.length > 16 ? '${cleanLocation.characters.take(14)}...' : cleanLocation;
      return '$brand | $loc';
    }
    
    // ── 策略3: 兜底 ──
    if (address != null) return address;
    if (brand != null && cleanLocation != null) return '$brand | $cleanLocation';
    var longest = '';
    for (final l in lines) { if (l.length > longest.length && l.length > 4) longest = l; }
    return longest.length > 24 ? '${longest.characters.take(22)}...' : longest;
  }

  /// 外卖场景: 产品名 | 店名
  String _extractProductAndShop(List<String> lines) {
    final brands = {'蜜雪冰城', '美团', '饿了么', '饿了吗', '星巴克', '瑞幸', '肯德基', '麦当劳'};
    
    // 产品名: 2-12字中文/字母，不由品牌名组成，优先选择后面跟价格的行
    String? product;
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.length < 2 || t.length > 12) continue;
      if (!RegExp(r'^[\u4e00-\u9fff\w\s]+$').hasMatch(t)) continue;
      if (t.contains('店') || t.contains('详情')) continue;
      if (brands.contains(t)) continue;  // 跳过品牌名
      
      // 检查下一行是否为价格（优先选）
      if (i + 1 < lines.length) {
        final next = lines[i + 1].trim();
        if (RegExp(r'^[¥￥]\s*\d').hasMatch(next)) {
          product = t;
          break;  // 找到产品+价格组合，直接确定
        }
      }
      product ??= t;  // 兜底: 第一个符合条件的行
    }
    
    // 店名: 包含"店"字的最长行（截取20字），排除营销文案
    String? shop;
    for (final l in lines) {
      if (l.contains('店') && !l.contains('免单') && !l.contains('抽奖')) {
        if (shop == null || l.length > shop.length) {
          shop = l.length > 20 ? '${l.characters.take(18)}...' : l;
        }
      }
    }
    
    if (product != null && shop != null) return '$product | $shop';
    if (product != null) return product;
    if (shop != null) return shop;
    return lines.isNotEmpty ? lines.first : '';
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
    // 计算与OCR路径一致的过滤展示内容
    _filteredContent = _buildDisplayContent(text, parsed);
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
    _filteredContent = '';
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

  /// 网络阻断转发（已验证稳定）
  Future<void> _sendWithNetworkBypass() async {
    if (_isBypassing) return;
    setState(() => _isBypassing = true);
    final category = _parsed?.category.name ?? 'general';
    // 提取结构化字段
    final codeInfo = _parsed?.keyInfos
        .where((k) => k.type == KeyType.code)
        .firstOrNull;
    final codeValue = codeInfo?.value ?? '';
    final amountInfo = _parsed?.keyInfos
        .where((k) => k.type == KeyType.amount)
        .firstOrNull;
    final itemsInfo = _parsed?.keyInfos
        .where((k) => k.label == '件数')
        .firstOrNull;
    final locationInfo = _parsed?.keyInfos
        .where((k) => k.type == KeyType.location)
        .firstOrNull;
    // 展开岛标题：只显示"取餐码: 7656"（标签+码值）
    final label = _parsed?.title.isNotEmpty == true ? _parsed!.title : '';
    final title = '$label: $codeValue';
    // 展开岛内容：只传门店/地址（不做拼接，避免重复）
    final content = locationInfo?.value ?? _subtitleController.text.trim();
    // 副标题：留空
    const subtitle = '';
    try {
      await _nativeService.sendFocusWithNetworkBypass(
        title: title,
        content: content,
        subtitle: subtitle,
        codeValue: codeValue,
        category: category,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已发送网络阻断转发'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('转发失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBypassing = false);
    }
  }

  Future<void> _doForward(bool showAnimation) async {
    if (_isForwarding) return;
    setState(() => _isForwarding = true);

    final title = _titleController.text.trim();
    final subtitle = _subtitleController.text.trim();
    final category = _parsed?.category.name ?? 'general';
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
      'useOfficialBackground': style.useOfficialBackground.toString(),
    };

    // 获取码值用于 subtitle 和超级岛标题
    final codeInfo = _parsed?.keyInfos
        .where((k) => k.type == KeyType.code)
        .firstOrNull;
    final codeValue = codeInfo?.value ?? subtitle;

    try {
      // 背屏和超级岛都用过滤后的统一内容
      await _nativeService.displayOnBackScreen(
        title: title,
        subtitle: codeValue,
        content: _filteredContent,
        styleExtras: styleMap,
        category: category,
      );
      if (showAnimation) {
        final parsedTitle = _parsed?.title ?? title;
        final islandTitle = codeInfo != null
            ? '$parsedTitle ${codeInfo.value}'
            : parsedTitle;
        await _nativeService.sendSuperIslandNotification(
          title: islandTitle,
          content: _filteredContent,
          category: category,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text('FBS', style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          letterSpacing: -0.3,
        )),
        actions: [
          // HyperIsland 测试工具入口
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: () => _nativeService.launchHyperIslandTest(),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: GlassTokens.glassGradient(Theme.of(context).brightness),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.30),
                    width: 0.5,
                  ),
                  boxShadow: GlassTokens.glassShadow(Theme.of(context).brightness),
                ),
                child: Center(child: Icon(Icons.science_outlined, size: 18,
                  color: isDark ? Colors.white70 : const Color(0xFF6200EE))),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => Navigator.push(context, SlideRoute(builder: (_) => const SettingsPage())).then((_) => _refreshStatus()),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: GlassTokens.glassGradient(Theme.of(context).brightness),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.30),
                    width: 0.5,
                  ),
                  boxShadow: GlassTokens.glassShadow(Theme.of(context).brightness),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _dot(isDark),
                      const SizedBox(height: 3.5),
                      _dot(isDark),
                      const SizedBox(height: 3.5),
                      _dot(isDark),
                    ],
                  ),
                ),
              ),
            ),
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
            const SizedBox(height: 8),
            _buildNetworkBypassButton(),
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

  Widget _dot(bool isDark) {
    return Container(
      width: 3, height: 3,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? Colors.white70 : Colors.black54,
      ),
    );
  }

  Widget _buildInputArea() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
        gradient: GlassTokens.glassGradient(Theme.of(context).brightness),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.30),
          width: 0.5,
        ),
        boxShadow: GlassTokens.glassShadow(Theme.of(context).brightness),
      ),
      child: TextField(
        controller: _textController,
        maxLines: 6,
        decoration: const InputDecoration(
          hintText: '粘贴内容，自动提取关键信息...',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.all(14),
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _buildToolbar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassDeco = BoxDecoration(
      borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
      gradient: GlassTokens.glassGradient(Theme.of(context).brightness),
      border: Border.all(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.30),
        width: 0.5,
      ),
      boxShadow: GlassTokens.glassShadow(Theme.of(context).brightness),
    );
    return Row(children: [
      GestureDetector(
        onTap: _textController.text.isEmpty && _parsed == null ? null : _clearAll,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: glassDeco,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.clear, size: 16, color: isDark ? Colors.white54 : Colors.black54),
            const SizedBox(width: 4),
            Text('清空', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
      const SizedBox(width: GlassTokens.spaceSM),
      Expanded(
        child: GestureDetector(
          onTap: _pasteFromClipboard,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: glassDeco,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.content_paste, size: 16, color: isDark ? Colors.white54 : Colors.black54),
              const SizedBox(width: 4),
              Text('从剪贴板粘贴', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      ),
      const SizedBox(width: GlassTokens.spaceSM),
      GestureDetector(
        onTap: _parseContent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
            color: GlassTokens.accent,
            boxShadow: [BoxShadow(color: GlassTokens.accent.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.auto_fix_high, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            const Text('解析', style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
          ]),
        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: canForward && !_isForwarding ? _forwardAll : null,
      child: Container(
        width: double.infinity, height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
          gradient: canForward
            ? const LinearGradient(colors: [GlassTokens.accent, GlassTokens.accentDark])
            : GlassTokens.glassGradient(Theme.of(context).brightness),
          border: Border.all(
            color: canForward
              ? GlassTokens.accent.withValues(alpha: 0.3)
              : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.30)),
            width: 0.5,
          ),
          boxShadow: canForward
            ? [BoxShadow(color: GlassTokens.accent.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))]
            : GlassTokens.glassShadow(Theme.of(context).brightness),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isForwarding)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.send_rounded, size: 20,
                    color: canForward ? Colors.white : (isDark ? Colors.white38 : Colors.black38)),
                ),
              Text(
                _isForwarding ? '转发中...' : '转发到背屏 + 超级岛',
                style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600,
                  color: canForward ? Colors.white : (isDark ? Colors.white38 : Colors.black38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkBypassButton() {
    final canForward = _isShizukuRunning && _hasShizukuPermission && _titleController.text.trim().isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: canForward && !_isBypassing ? _sendWithNetworkBypass : null,
      child: Container(
        width: double.infinity, height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
          gradient: canForward
            ? const LinearGradient(colors: [Color(0xFF00BCD4), Color(0xFF0097A7)])
            : GlassTokens.glassGradient(Theme.of(context).brightness),
          border: Border.all(
            color: canForward
              ? const Color(0xFF00BCD4).withValues(alpha: 0.3)
              : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.30)),
            width: 0.5,
          ),
          boxShadow: canForward
            ? [BoxShadow(color: const Color(0xFF00BCD4).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))]
            : GlassTokens.glassShadow(Theme.of(context).brightness),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isBypassing)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.shield_outlined, size: 18,
                    color: canForward ? Colors.white : (isDark ? Colors.white38 : Colors.black38)),
                ),
              Text(
                _isBypassing ? '阻断转发中...' : '网络阻断转发',
                style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: canForward ? Colors.white : (isDark ? Colors.white38 : Colors.black38),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.bolt, size: 14,
                color: canForward ? const Color(0xFFFFD700) : (isDark ? Colors.white24 : Colors.black26)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryActions() {
    return Column(children: [
      Row(children: [
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
          label: '图片贴背屏',
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
      ]),
    ]);
  }

  Widget _buildGlassAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
    Color? color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
          gradient: GlassTokens.glassGradient(Theme.of(context).brightness),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.30),
            width: 0.5,
          ),
          boxShadow: GlassTokens.glassShadow(Theme.of(context).brightness),
        ),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20,
            color: color ?? (enabled
              ? (isDark ? Colors.white54 : Colors.black54)
              : (isDark ? Colors.white24 : Colors.black26)),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w500,
            color: color ?? (enabled
              ? (isDark ? Colors.white54 : Colors.black54)
              : (isDark ? Colors.white24 : Colors.black26)),
          )),
        ],
      ),
    ),
  );
  }
}
