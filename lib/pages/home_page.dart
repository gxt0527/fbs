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
        // 文本：自动解析 → #9 超级岛 + 背屏
        final text = shared.text!.trim();
        final parsed = ContentParser.parse(text);
        final displayContent = _buildDisplayContent(text, parsed);

        await _forwardViaTemplate9(parsed, displayContent, parsed.category.name);
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
      
      // 4. 构建展示内容
      final displayContent = _buildDisplayContent(sanitizedText, parsed);

      // 5. 转发到 #9 超级岛 + 背屏（统一 helper）
      await _forwardViaTemplate9(parsed, displayContent, parsed.category.name);
      
      _nativeService.showToast('已识别并转发: ${parsed.title}');
      
    } catch (e) {
      _nativeService.showToast('处理失败: $e');
    }
  }


  /// 构建统一展示内容（背屏和超级岛共用）
  /// 外卖=产品|店名，快递=取件地址，其他=关键字段组合
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
        return _buildFromKeyInfos(parsed, lines);
    }
  }

  /// 从关键字段构建展示内容，对齐美食取餐码模式
  String _buildFromKeyInfos(ParsedContent parsed, List<String> lines) {
    final parts = <String>[];
    for (final info in parsed.keyInfos) {
      switch (info.type) {
        case KeyType.code:
        case KeyType.order:
          parts.add('${info.label}：${info.value}');
        case KeyType.amount:
          parts.add('金额：¥${info.value}');
        case KeyType.location:
          if (!parts.any((p) => p.contains(info.value))) {
            parts.add(info.value);
          }
        case KeyType.time:
          if (parts.isEmpty) parts.add(info.value);
        default:
          break;
      }
    }
    if (parts.isNotEmpty) return parts.join('  ');
    return lines.isNotEmpty ? lines.first : '';
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


  String _defaultLabel(ParsedCategory category) {
    switch (category) {
      case ParsedCategory.express: return '取件码';
      case ParsedCategory.foodDelivery: return '取餐码';
      case ParsedCategory.payment: return '支付';
      case ParsedCategory.verification: return '验证码';
      case ParsedCategory.meeting: return '会议';
      case ParsedCategory.travel: return '出行';
      case ParsedCategory.bill: return '账单';
      case ParsedCategory.order: return '订单';
      case ParsedCategory.system: return '系统';
      case ParsedCategory.general: return '通知';
    }
  }

  /// 统一转发入口：#9 超级岛 + 背屏同步转发
  /// 由图片OCR、分享文本、按钮三个入口统一调用
  Future<void> _forwardViaTemplate9(ParsedContent parsed, String displayContent, String category) async {
    if (_isBypassing) return;
    setState(() => _isBypassing = true);

    // 标签/主要文本1（按场景取默认值）
    final label = parsed.title.isNotEmpty ? parsed.title : _defaultLabel(parsed.category);
    // 码值/主要文本2（优先 code 类型，回退到 order 类型）
    final codeInfo = parsed.keyInfos
        .where((k) => k.type == KeyType.code)
        .firstOrNull ?? parsed.keyInfos
        .where((k) => k.type == KeyType.order)
        .firstOrNull;
    final codeValue = codeInfo?.value ?? '';
    // 件数
    final itemsInfo = parsed.keyInfos
        .where((k) => k.label == '件数')
        .firstOrNull;
    final items = itemsInfo?.value ?? '';
    // 金额（原始数字，不含 ¥，#9 的 Kotlin 层会加）
    final amountInfo = parsed.keyInfos
        .where((k) => k.type == KeyType.amount)
        .firstOrNull;
    final amount = amountInfo?.value ?? '';
    // 店名/地址/次要文本2
    final locationInfo = parsed.keyInfos
        .where((k) => k.type == KeyType.location)
        .firstOrNull;
    final storeName = locationInfo?.value ?? '';

    debugPrint('[FBS-T9] forwardViaTemplate9:'
        ' label=$label code=$codeValue'
        ' items=$items amount=$amount store=$storeName'
        ' category=$category');
    debugPrint('[FBS-T9] all KeyInfos:${parsed.keyInfos.map((k) => "\n  [${k.label}](${k.type.name}) = ${k.value}").join()}');
    try {
      // 第一步：#9 网络阻断转发（超级岛）
      await _nativeService.sendFocusWithNetworkBypassTemplate9(
        label: label,
        codeValue: codeValue,
        storeName: storeName,
        items: items,
        amount: amount,
        category: category,
      );

      // 第二步：背屏显示（结构化内容，剔除重复字段）
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
      await _nativeService.displayOnBackScreen(
        title: label,
        subtitle: codeValue,
        content: _buildTemplate9BackScreenContent(parsed, displayContent, label, codeValue, items, amount, storeName),
        styleExtras: styleMap,
        category: category,
      );
    } catch (e) {
      debugPrint('[FBS] forwardViaTemplate9 error: $e');
    } finally {
      if (mounted) setState(() => _isBypassing = false);
    }
  }

  /// 构建 #9 转发的背屏正文 — 件数+金额+店名等一行显示，剔除主标题/码值/重复件数金额
  String _buildTemplate9BackScreenContent(
    ParsedContent parsed,
    String displayContent,
    String label,
    String codeValue,
    String items,
    String amount,
    String storeName,
  ) {
    final parts = <String>[];
    if (items.isNotEmpty) parts.add('件数：$items');
    if (amount.isNotEmpty) parts.add('金额：¥$amount');
    if (parts.isNotEmpty && storeName.isNotEmpty) {
      // 如果 storeName 已含件数/金额描述，用 storeName 替代
      if (storeName.contains('件数') || storeName.contains('金额')) {
        // storeName 包含了这些信息，直接用它
        return storeName;
      }
      return '${parts.join('  ')}  $storeName';
    }
    if (storeName.isNotEmpty) return storeName;
    if (parts.isNotEmpty) return parts.join('  ');
    // 兜底：从 displayContent 剔除标题和码值
    var fallback = displayContent;
    if (label.isNotEmpty) fallback = fallback.replaceFirst(label, '').trim();
    if (codeValue.isNotEmpty) fallback = fallback.replaceFirst(codeValue, '').trim();
    fallback = fallback.replaceAll(RegExp(r'\s*金额[：:]\s*[¥￥]?\s*\d+(\.\d+)?'), '')
        .replaceAll(RegExp(r'\s*件数[：:]\s*\S+'), '')
        .replaceAll(RegExp(r'^[：:\s，]+'), '')
        .trim();
    return fallback.isNotEmpty ? fallback : displayContent;
  }

  /// 网络阻断转发 #9 — 按钮入口，调用统一 helper
  Future<void> _sendWithNetworkBypassTemplate9() async {
    if (_parsed == null) return;
    await _forwardViaTemplate9(_parsed!, _filteredContent, _parsed!.category.name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已转发到背屏 + 模板#9超级岛'), duration: Duration(seconds: 2)),
      );
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
            _buildNetworkBypassTemplate9Button(),
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
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '主标题', border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true,
                ),
              ),
              const SizedBox(height: 12),
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

  Widget _buildNetworkBypassTemplate9Button() {
    final canForward = _isShizukuRunning && _hasShizukuPermission && _titleController.text.trim().isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 紫罗兰色渐变 — 与现有的青绿色按钮区分
    return GestureDetector(
      onTap: canForward && !_isBypassing ? _sendWithNetworkBypassTemplate9 : null,
      child: Container(
        width: double.infinity, height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
          gradient: canForward
            ? const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF651FFF)])
            : GlassTokens.glassGradient(Theme.of(context).brightness),
          border: Border.all(
            color: canForward
              ? const Color(0xFF7C4DFF).withValues(alpha: 0.3)
              : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.30)),
            width: 0.5,
          ),
          boxShadow: canForward
            ? [BoxShadow(color: const Color(0xFF7C4DFF).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))]
            : GlassTokens.glassShadow(Theme.of(context).brightness),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(Icons.local_offer_outlined, size: 18,
                  color: canForward ? Colors.white : (isDark ? Colors.white38 : Colors.black38)),
              ),
              Text(
                _isBypassing ? '阻断转发中...' : '网络阻断转发 #9',
                style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: canForward ? Colors.white : (isDark ? Colors.white38 : Colors.black38),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: canForward ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('取餐码', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: canForward ? Colors.white : (isDark ? Colors.white38 : Colors.black38),
                )),
              ),
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
