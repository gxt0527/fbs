import 'package:characters/characters.dart';

// ===== Scene Category =====
enum ParsedCategory {
  express,
  foodDelivery,
  payment,
  order,
  meeting,
  travel,
  verification,
  bill,
  system,
  general;

  String get label => switch (this) {
    express => '快递',
    foodDelivery => '外卖',
    payment => '支付',
    order => '订单',
    meeting => '会议',
    travel => '出行',
    verification => '验证',
    bill => '账单',
    system => '系统',
    general => '通用',
  };
}

// ===== Action =====
enum ActionType { copy, call, open, mail, navigate }

class ActionItem {
  final ActionType type;
  final String label;
  final String? data;
  const ActionItem({required this.type, required this.label, this.data});
}

// ===== Key Info =====
enum KeyType {
  code,
  time,
  order,
  location,
  amount,
  phone,
  link,
  email,
  name,
  general;
}

class KeyInfo {
  final String label;
  final String value;
  final KeyType type;
  const KeyInfo({required this.label, required this.value, this.type = KeyType.general});
}

// ===== Parsed Result =====
class ParsedContent {
  final String title;
  final String subtitle;
  final String body;
  final ParsedCategory category;
  final List<KeyInfo> keyInfos;
  final List<ActionItem> actions;

  ParsedContent({
    required this.title,
    required this.subtitle,
    required this.body,
    this.category = ParsedCategory.general,
    this.keyInfos = const [],
    this.actions = const [],
  });
}

// ===== Parser =====
class ContentParser {
  ContentParser._();

  static final _emojiRegex = RegExp(
    r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{FE00}-\u{FE0F}\u{200D}]',
    unicode: true,
  );
  static final _isPureChinese = RegExp(r'^[\u4e00-\u9fa5]+$');

  // ═══════════════ Public API ═══════════════

  static ParsedContent parse(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return ParsedContent(title: '', subtitle: '', body: '');

    final lines = _cleanLines(raw);
    if (lines.isEmpty) return ParsedContent(title: raw, subtitle: '', body: '');

    final category = _detectCategory(raw);
    final title = _extractTitle(lines, category);
    final subtitle = _extractSubtitle(lines, title, category);
    final keyInfos = _extractKeyInfos(raw);
    final actions = _deriveActions(keyInfos);

    // Build body from cleaned lines excluding title/subtitle lines, max 200 chars
    final cleanTitle = title.replaceAll(_emojiRegex, '').trim();
    final cleanSubtitle = subtitle.replaceAll(_emojiRegex, '').trim();
    final bodyLines = lines.where((l) {
      final clean = l.replaceAll(_emojiRegex, '').trim();
      if (clean.isEmpty) return false;
      if (clean == cleanTitle) return false;
      if (cleanSubtitle.isNotEmpty && clean == cleanSubtitle) return false;
      return true;
    }).toList();
    final joined = bodyLines.isNotEmpty ? bodyLines.join('\n') : raw;
    // 字符级安全截断：避免 substring(0,197) 在 UTF-16 代理对中间截断产生非法字符串
    final chars = joined.characters;
    final body = chars.length > 200 ? '${chars.take(197)}...' : joined;

    return ParsedContent(
      title: title,
      subtitle: subtitle,
      body: body,
      category: category,
      keyInfos: keyInfos,
      actions: actions,
    );
  }

  /// Strip emoji from a string.
  static String stripEmoji(String s) => s.replaceAll(_emojiRegex, '').trim();

  /// OCR 文本清洗：去除控制字符、非打印字符、规范化换行
  /// 防止 OCR 模型输出的特殊字符导致 Canvas 渲染异常
  static String sanitizeOcrText(String text) {
    if (text.isEmpty) return text;

    var result = text;

    // 1. 规范化换行符: \r\n → \n, 独立 \r → \n
    result = result.replaceAll('\r\n', '\n');
    result = result.replaceAll('\r', '\n');

    // 2. 去除 C0 控制字符 (U+0000-U+001F)，保留 \n \t
    //    去除 C1 控制字符 (U+007F-U+009F)
    result = result.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]'), '');

    // 3. 去除 Unicode 非字符 (Noncharacters)
    result = result.replaceAll(RegExp(r'[\uFFFE\uFFFF\u{FDD0}-\u{FDEF}]', unicode: true), '');

    // 4. 替换不可见零宽字符/方向标记为空白（避免影响文本布局）
    result = result.replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]'), '');

    // 5. 去除行首行尾多余空白，合并连续空行为单个空行
    result = result.split('\n')
        .map((l) => l.trim())
        .join('\n');
    // 合并连续空行
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return result.trim();
  }

  /// 过滤 OCR 文本中的状态栏噪音，用于背屏内容展示
  /// 去除时间、电量、网络状态、版本号等噪音行
  static String filterBackScreenContent(String text) {
    if (text.isEmpty) return text;
    return text.split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !_isStatusBarNoiseLine(l) && !_isMarketingNoiseLine(l))
        .join('\n');
  }

  /// 营销/UI元素噪音行（"进群抽免单""长按识别二维码"等）
  static final _marketingNoisePatterns = [
    // 营销推广
    RegExp(r'进群|加群|扫码|识别二维码|长按识别'),
    RegExp(r'免单|抽奖|领券|领红包|券包|\d+张券|[兑兌]零?食'),
    RegExp(r'支付有礼|支付完成\d*分钟后发放'),
    RegExp(r'请在有效期内使用'),
    RegExp(r'可获得|奖励\d*|甜蜜值'),
    RegExp(r'^详情$'),
    RegExp(r'再来一单'),
    // 页面标题（非通知内容，已由 title 展示）
    RegExp(r'^订单详情$'),
    // UI碎片（OCR误识别）
    RegExp(r'^[新赏优]$'),
    RegExp(r'^[X×xX]\d*$'),
    RegExp(r'^优惠券$'),
  ];

  static bool _isMarketingNoiseLine(String line) {
    return _marketingNoisePatterns.any((p) => p.hasMatch(line));
  }

  /// 判断单行是否为状态栏噪音
  static bool _isStatusBarNoiseLine(String line) {
    // 1. 整行匹配
    if (_statusBarLinePatterns.any((p) => p.hasMatch(line))) return true;
    
    // 2. 拆分令牌匹配：处理合并行如 "20:22 5G 58"
    final tokens = line.split(RegExp(r'\s+'));
    if (tokens.length >= 2 && tokens.every((t) => _isStatusBarToken(t))) return true;
    
    return false;
  }
  
  /// 判断单个令牌是否为状态栏元素
  static bool _isStatusBarToken(String token) {
    if (token.isEmpty) return true;
    return _statusBarLinePatterns.any((p) => p.hasMatch(token));
  }

  // ═══════════════ Scene Detection ═══════════════

  static ParsedCategory _detectCategory(String text) {
    final lc = text.toLowerCase();
    if (_containsAny(lc, [
      '顺丰', '京东物流', '中通', '圆通', '韵达', '申通',
      'ems', '中国邮政', '邮政',
      '菜鸟', '包裹', '快递', '物流', '派送', '派件',
      '签收', '运单', '取件码', '快递柜', '蜂巢', '驿站',
    ])) {
      return ParsedCategory.express;
    }
    if (_containsAny(lc, [
      '美团', '饿了么', '饿了吗', '外卖', '骑手',
      '取餐码', '配送中', '已接单', '已取餐',
    ])) {
      return ParsedCategory.foodDelivery;
    }
    if (_containsAny(lc, [
      '微信支付', '支付宝', '收款', '转账', '消费',
      '支出', '收入', '到账', '退款',
    ])) {
      return ParsedCategory.payment;
    }
    if (_containsAny(lc, [
      '验证码', '校验码', '动态码', '安全码', '核销码', '兑换码',
    ])) {
      return ParsedCategory.verification;
    }
    if (_containsAny(lc, [
      '会议', '腾讯会议', '钉钉', '日程', '预约', '提醒', '待办',
    ])) {
      return ParsedCategory.meeting;
    }
    if (_containsAny(lc, [
      '滴滴', '携程', '同程', '航班', '高铁', '火车',
      '机票', '打车', '行程', '登机', '12306',
    ])) {
      return ParsedCategory.travel;
    }
    if (_containsAny(lc, [
      '账单', '话费', '缴费', '欠费', '月结', '已出账',
    ])) {
      return ParsedCategory.bill;
    }
    if (_containsAny(lc, ['购买', '下单', '已购', '订单号'])) {
      return ParsedCategory.order;
    }
    return ParsedCategory.general;
  }

  static bool _containsAny(String text, List<String> keywords) {
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  // ═══════════════ Title ═══════════════

  static String _extractTitle(List<String> lines, ParsedCategory category) {
    if (lines.isEmpty) return '';

    // Scan all lines and pick the most suitable title, skipping noise
    String pick(List<String> ls) {
      String? bracketLine;
      String? keywordLine;
      String? fallbackLine;

      for (final l in ls) {
        final cleaned = l.replaceAll(_emojiRegex, '').trim();
        if (cleaned.isEmpty) { continue; }

        // Skip noise: short pure-Chinese (button labels) / decimal-only (version)
        final isShortChineseNoise = cleaned.length <= 8 && _isPureChinese.hasMatch(cleaned) &&
            !_containsAny(cleaned, ['取餐码', '取件码', '验证码', '订单号', '运单号', '快递单号']);
        final isNoise = isShortChineseNoise || RegExp(r'^\d+\.\d+$').hasMatch(cleaned);
        if (isNoise) { continue; }

        bracketLine ??= (cleaned.contains('【') ? cleaned : null);
        keywordLine ??= (_containsAny(cleaned, [
          '取餐码', '取件码', '验证码', '订单号', '运单号', '快递单号',
          '快递', '外卖', '包裹', '配送', '已签收', '已送达', '已取餐',
        ]) ? cleaned : null);
        fallbackLine ??= cleaned;
      }

      // keywordLine (通知关键词) 优先于 bracketLine (来源名)，避免整行过长
      return keywordLine ?? bracketLine ?? fallbackLine ?? '';
    }

    var first = pick(lines);
    if (first.isEmpty) return '';

    // Category-specific: try to form a meaningful title
    switch (category) {
      case ParsedCategory.express:
        {
          final label = _extractCodeLabel(lines,
            RegExp(r'(取件码|取货码|提货码)\s*[:：为]?\s*[\d\-]{3,15}'));
          if (label != null) return label;
        }
        return _match(lines, [
          RegExp(r'【[^】]+】.*?(?:包裹|快递|快件|物流).*'),
          RegExp(r'.*(?:已签收|已到达|派送中|即将派送|待取件).*'),
        ]) ?? first;

      case ParsedCategory.foodDelivery:
        {
          final label = _extractCodeLabel(lines,
            RegExp(r'(取餐码|取餐号)\s*[:：]?\s*[A-Za-z0-9]{4,10}'));
          if (label != null) return label;
        }
        return _match(lines, [
          RegExp(r'【[^】]+】.*?(?:外卖|配送).*'),
          RegExp(r'.*(?:已接单|已取餐|配送中|已送达).*'),
        ]) ?? first;

      case ParsedCategory.payment:
        return _match(lines, [
          RegExp(r'(微信支付|支付宝|银联).*'),
          RegExp(r'.*(?:收款|到账|消费|支出).*'),
        ]) ?? first;

      case ParsedCategory.verification:
        {
          final label = _extractCodeLabel(lines,
            RegExp(r'(验证码|校验码|动态码)\s*[:：]?\s*[A-Za-z0-9]{4,12}'));
          if (label != null) return label;
        }
        return _match(lines, [
          RegExp(r'【([^】]+)】.*验证码'),
          RegExp(r'.*验证码.*'),
        ]) ?? '验证码';

      case ParsedCategory.meeting:
        return _match(lines, [
          RegExp(r'【[^】]+】.*(?:会议|日程).*'),
          RegExp(r'.*(?:提醒|预约|即将开始).*'),
        ]) ?? first;

      case ParsedCategory.travel:
        return _match(lines, [
          RegExp(r'【[^】]+】.*(?:出行|行程|打车|航班|火车).*'),
          RegExp(r'.*(?:已接单|已到达|即将出发).*'),
        ]) ?? first;

      default:
        return _truncate(first, 60);
    }
  }

  static String? _match(List<String> lines, List<RegExp> patterns) {
    for (final line in lines) {
      final clean = line.replaceAll(_emojiRegex, '').trim();
      if (clean.isEmpty) continue;
      for (final p in patterns) {
        final m = p.firstMatch(clean);
        if (m != null) return _truncate(m.group(0) ?? clean, 60);
      }
    }
    return null;
  }

  /// 从匹配行中只提取标签（不含码值），如 "取件码 3-2-8188" → "取件码"
  static String? _extractCodeLabel(List<String> lines, RegExp pattern) {
    for (final line in lines) {
      final clean = line.replaceAll(_emojiRegex, '').trim();
      if (clean.isEmpty) continue;
      final m = pattern.firstMatch(clean);
      if (m != null && m.groupCount >= 1) {
        return _truncate(m.group(1)!, 60);  // 只返回 group 1 (标签名)
      }
    }
    return null;
  }

  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    final chars = s.characters;
    return chars.length > max ? '${chars.take(max - 3)}...' : s;
  }

  // ═══════════════ Subtitle ═══════════════

  static String _extractSubtitle(List<String> lines, String title, ParsedCategory category) {
    final body = lines.join(' ');
    // Try regex status patterns (more flexible than exact match)
    final statusPatterns = switch (category) {
      ParsedCategory.express => [
          r'(已签收|已由本人签收|已代签收|已由.*?签收|派送中|已到达|即将派送|运输中|待取件|已揽收|已发货|已取件|已退回)',
        ],
      ParsedCategory.foodDelivery => [
          r'(已接单|制作中|已取餐|配送中|已送达|待支付)',
        ],
      ParsedCategory.payment => [
          r'(收款成功|转账成功|支付成功|消费成功|退款成功|到账)',
        ],
      ParsedCategory.meeting => [
          r'(即将开始|进行中|已取消|已完成|即将开始)',
        ],
      ParsedCategory.travel => [
          r'(已接单|已到达|即将出发|已延误|登机中|已出票)',
        ],
      _ => [r'(进行中|已完成|已取消|即将开始)'],
    };
    final combined = '$title $body';
    for (final pattern in statusPatterns) {
      final m = RegExp(pattern).firstMatch(combined);
      if (m != null) return m.group(1)!;
    }

    // Fall back to second meaningful line
    var second = '';
    for (var i = 1; i < lines.length; i++) {
      final candidate = lines[i].replaceAll(_emojiRegex, '').trim();
      if (candidate.isEmpty || candidate == title) continue;
      // Skip lines that are code/phone/URL/address-only / single-char Chinese (OCR noise)
      if (RegExp(r'^(1[3-9]\d{9}|https?://|[京津沪]|验证码|取件码)\s*').hasMatch(candidate)) continue;
      if (_isPureChinese.hasMatch(candidate) && candidate.length <= 1) continue;
      second = candidate;
      break;
    }
    return _truncate(second, 60);
  }

  // ═══════════════ Key Infos ═══════════════

  /// Lines that are status bar noise (time, battery, network, etc.)
  static final _statusBarLinePatterns = [
    RegExp(r'^\d{1,2}[:：]\d{2}(\s*\d{1,2}%?)?$'),         // 20:22 / 14:25 50%
    RegExp(r'^\d{1,2}%?$'),                                  // 58 / 58%  (battery)
    RegExp(r'^[A-Za-z]{2,3}\s*,?\s*\d{1,2}[:：]\d{2}$'),   // Mon 14:25
    RegExp(r'^(周一|周二|周三|周四|周五|周六|周日)\s*\d{1,2}[:：]\d{2}'),
    RegExp(r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}$'),              // 2026-07-11
    RegExp(r'^[45]G$', caseSensitive: false),                // 5G / 4G
    RegExp(r'^WIFI$', caseSensitive: false),                 // WIFI
    RegExp(r'^\d+\.\d+$'),                                   // 2.0 (version numbers)
  ];

  /// Remove status-bar noise lines from text (used by both title and key info)
  static String _filterStatusBarNoise(String text) {
    final lines = text.split('\n');
    final filtered = lines.where((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return false;
      return !_statusBarLinePatterns.any((p) => p.hasMatch(trimmed));
    }).join('\n');
    return filtered;
  }

  /// Filter noise lines AND return clean lines list for title/subtitle
  static List<String> _cleanLines(String text) {
    return _filterStatusBarNoise(text)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  static List<KeyInfo> _extractKeyInfos(String text) {
    final infos = <KeyInfo>[];
    final clean = _filterStatusBarNoise(text.replaceAll(_emojiRegex, ''));

    void add(KeyInfo v) {
      if (!infos.any((i) => i.label == v.label && i.value == v.value)) {
        infos.add(v);
      }
    }

    // 1. 取件码（驿站/快递柜）- 支持数字+横杠组合，如 3-2-8188 / 取件码为11-4-9476
    for (final m in RegExp(
      r'(取件码|取件号|取货码|提货码|货架号|柜号|箱号)\s*[:：为]?\s*([\d\-]{3,15})',
    ).allMatches(clean)) {
      add(KeyInfo(label: m.group(1)!, value: m.group(2)!, type: KeyType.code));
    }

    // 2. 取餐码（外卖平台）- 字母+数字组合 或 纯数字
    for (final m in RegExp(
      r'(取餐码|取餐号)\s*[:：]?\s*([A-Za-z0-9]{4,10})',
    ).allMatches(clean)) {
      final code = m.group(2)!;
      // 接受: 字母+数字(A7832) 或 纯数字(7656)，拒绝纯字母
      final hasLetter = RegExp(r'[A-Za-z]').hasMatch(code);
      final hasDigit = RegExp(r'[0-9]').hasMatch(code);
      if (hasDigit) {
        add(KeyInfo(label: m.group(1)!, value: code, type: KeyType.code));
      }
    }

    // 3. 验证码/核销码
    for (final m in RegExp(
      r'(验证码|核销码|兑换码|校验码|动态码)\s*[:：]?\s*([A-Za-z0-9]{4,12})',
    ).allMatches(clean)) {
      add(KeyInfo(label: m.group(1)!, value: m.group(2)!, type: KeyType.code));
    }

    // 4. 订单号 / 运单号
    for (final m in RegExp(
      r'(订单号|运单号|快递单号|交易单号|流水号|订单编号|商品单号)\s*[:：]?\s*([A-Za-z0-9\-]{8,30})',
    ).allMatches(clean)) {
      add(KeyInfo(label: m.group(1)!, value: m.group(2)!, type: KeyType.order));
    }

    // 5. 快递单号（智能识别各快递公司）
    final expressPatterns = {
      '中通': RegExp(r'(?:中通|ZTO)\s*[A-Z]?\d{12,15}', caseSensitive: false),
      '圆通': RegExp(r'(?:圆通|YTO)\s*[A-Z]?\d{13,15}', caseSensitive: false),
      '申通': RegExp(r'(?:申通|STO)\s*[A-Z]?\d{12,15}', caseSensitive: false),
      '韵达': RegExp(r'(?:韵达|YUNDA)\s*[A-Z]?\d{13,15}', caseSensitive: false),
      '顺丰': RegExp(r'(?:顺丰|SF)\s*[A-Z0-9]{12,15}', caseSensitive: false),
      '极兔': RegExp(r'(?:极兔|JT|J&T)\s*[A-Z]?\d{12,15}', caseSensitive: false),
    };
    for (final entry in expressPatterns.entries) {
      for (final m in entry.value.allMatches(clean)) {
        final trackingNo = m.group(0)!.replaceAll(RegExp(r'\s+'), '');
        add(KeyInfo(label: '${entry.key}单号', value: trackingNo, type: KeyType.order));
      }
    }

    // 6. 金额（有标签）
    for (final m in RegExp(
      r'(金额|消费|支付|收款|转账|退款|支出|收入|到账|费用|合计|共)[：:]?\s*'
      r'(人民币|美元|港币|欧元)?\s*[¥￥]?\s*'
      r'(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?)\s*(元|块|美元|港币|欧元)?',
    ).allMatches(clean)) {
      var amount = m.group(3)!;
      if (m.group(4)?.isNotEmpty == true) amount += m.group(4)!;
      add(KeyInfo(label: m.group(1)!, value: amount, type: KeyType.amount));
    }
    // 金额（¥ 前缀独立）— 与上一组去重（存储原始数字，不带 ¥，适配 #9 模板）
    for (final m in RegExp(
      r'[¥￥]\s*(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?)\s*(元|块)?',
    ).allMatches(clean)) {
      var amount = m.group(1)!;
      if (m.group(2)?.isNotEmpty == true) amount += m.group(2)!;
      // 移除无 ¥ 的同数值项，以当前项为准（统一存储原始数字）
      infos.removeWhere((i) => i.type == KeyType.amount && i.value == m.group(1)!);
      add(KeyInfo(label: '金额', value: amount, type: KeyType.amount));
    }

    // 门店名称 — 在遇到"金额/件数/消费"等关键词前停止，避免吞掉同行其他字段
    for (final m in RegExp(
      r'(门店|店铺|餐厅|店)[：:]\s*(.+?)(?=\s+(?:金额|消费|支付|件数|共|订单|总计|合计|备注|说明)|$)',
    ).allMatches(clean)) {
      final value = m.group(2)!.trim();
      if (value.isNotEmpty) {
        add(KeyInfo(label: m.group(1)!, value: value, type: KeyType.location));
      }
    }

    // 件数（如 "件数：1杯" "共1件" "1杯"） + 独立数量模式兜底
    for (final m in RegExp(
      r'(?:件数|共)\s*[：:]?\s*(\d+)\s*(杯|件|份|单|箱|袋|瓶|盒|个)',
    ).allMatches(clean)) {
      add(KeyInfo(label: '件数', value: '${m.group(1)!}${m.group(2)!}', type: KeyType.general));
    }
    if (!infos.any((i) => i.label == '件数')) {
      for (final m in RegExp(
        r'\b(\d+)\s*(杯|件|份|单|箱|袋|瓶|盒|个)\b(?!.*[¥￥])',
      ).allMatches(clean)) {
        add(KeyInfo(label: '件数', value: '${m.group(1)!}${m.group(2)!}', type: KeyType.general));
      }
    }

    // 7. 手机号（兼容带空格/横杠）
    for (final m in RegExp(
      r'(?:[电話电话联系方式][：:]?\s*)?(1[3-9]\d[\s\-]?\d[\s\-]?\d[\s\-]?\d[\s\-]?\d[\s\-]?\d[\s\-]?\d[\s\-]?\d)',
    ).allMatches(clean)) {
      final phone = m.group(1)!.replaceAll(RegExp(r'[\s\-]'), '');
      if (phone.length == 11) {
        add(KeyInfo(label: '电话', value: phone, type: KeyType.phone));
      }
    }

    // 8. 姓名（2-4位中文，上下文匹配）
    for (final m in RegExp(
      r'(?:收件人|姓名|联系人|快递员|配送员|收货人)\s*[:：]\s*([^\s,，。]{2,4})',
    ).allMatches(clean)) {
      final name = m.group(1)!.trim();
      if (RegExp(r'^[\u4e00-\u9fa5]{2,4}$').hasMatch(name)) {
        add(KeyInfo(label: '姓名', value: name, type: KeyType.general));
      }
    }

    // 9. 地址（省市区街道小区楼栋单元）
    for (final m in RegExp(
      r'(?:地址|地点|位置|收货地址|配送地址|取件地址|发货地址)\s*[:：]\s*([^\s,，。]{8,60})',
    ).allMatches(clean)) {
      final addr = m.group(1)!.trim();
      if (addr.length >= 8) {
        add(KeyInfo(label: '地址', value: addr, type: KeyType.location));
      }
    }

    // 10. 链接
    for (final m in RegExp(
      r'(https?://[^\s,，；;<>"()（）]{3,150})',
    ).allMatches(clean)) {
      add(KeyInfo(label: '链接', value: m.group(1)!, type: KeyType.link));
    }

    // 11. 邮箱
    for (final m in RegExp(
      r'([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})',
    ).allMatches(clean)) {
      add(KeyInfo(label: '邮箱', value: m.group(1)!, type: KeyType.email));
    }

    // 12. 车牌号
    for (final m in RegExp(
      r'[京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤川青藏琼]'
      r'[A-Z][A-HJ-NP-Z0-9]{4,5}[A-HJ-NP-Z0-9挂学警港澳]',
    ).allMatches(clean)) {
      add(KeyInfo(label: '车牌', value: m.group(0)!, type: KeyType.location));
    }

    // 13. 航班号
    for (final m in RegExp(
      r'\b([A-Z]{2}\d{3,4})\b',
    ).allMatches(clean)) {
      add(KeyInfo(label: '航班', value: m.group(1)!, type: KeyType.code));
    }

    // 9. 火车/高铁车次
    for (final m in RegExp(
      r'\b([GDCZ]\d{1,5})\b',
    ).allMatches(clean)) {
      add(KeyInfo(label: '车次', value: m.group(1)!, type: KeyType.order));
    }

    // 10. 日期时间（完整日期+时间）
    for (final m in RegExp(
      r'(预计|预计送达|提醒|取件|截止|到期|开始|出发|到达)?'
      r'\s*[:：]?\s*'
      r'(\d{4}[-/年]\d{1,2}[-/月]\d{1,2}[日号]?)'
      r'\s*(\d{1,2}[:：]\d{2}(?:[:：]\d{2})?)?',
    ).allMatches(clean)) {
      final full = m.group(0)!.trim();
      if (full.isNotEmpty) {
        add(KeyInfo(label: '时间', value: full, type: KeyType.time));
      }
    }
    // 短时间（HH:mm 范围）- 必须有上下文前缀，排除状态栏独立时间
    for (final m in RegExp(
      r'(预计[送达]?|提醒|取件[时间]?|截止|到期|开始|出发|到达|'
      r'配送[时间]?|送达[时间]?|营业[时间]?|服务[时间]?|'
      r'约)'
      r'\s*[:：]?\s*'
      r'(\d{1,2}[:：]\d{2})'
      r'\s*(?:[~—\-至到]\s*(\d{1,2}[:：]\d{2}))?',
    ).allMatches(clean)) {
      final full = m.group(0)!.trim();
      if (full.isNotEmpty &&
          !full.startsWith('http') &&
          !infos.any((i) => i.value == full)) {
        add(KeyInfo(label: '时间', value: full, type: KeyType.time));
      }
    }

    // 11. 地址 / 地点 — 在遇到"金额/件数"等关键词前停止，或行尾
    for (final m in RegExp(
      r'(地址|地点|位置|定位|上车点|下车点|取件地址|收货地址)[：:]\s*(.+?)(?=\s+(?:金额|消费|件数|共|订单|总计|合计|备注|说明)|$)',
    ).allMatches(clean)) {
      final addr = m.group(2)!.trim();
      if (addr.isNotEmpty &&
          !RegExp(r'^1[3-9]').hasMatch(addr) &&
          !addr.startsWith('http')) {
        add(KeyInfo(label: m.group(1)!, value: addr, type: KeyType.location));
      }
    }

    return infos;
  }

  // ═══════════════ Actions ═══════════════

  static List<ActionItem> _deriveActions(List<KeyInfo> infos) {
    final actions = <ActionItem>[];
    for (final info in infos) {
      switch (info.type) {
        case KeyType.code:
          actions.add(ActionItem(
            type: ActionType.copy,
            label: '复制 ${info.value}',
            data: info.value,
          ));
        case KeyType.order:
          actions.add(ActionItem(
            type: ActionType.copy,
            label: '复制订单号',
            data: info.value,
          ));
        case KeyType.phone:
          actions.add(ActionItem(
            type: ActionType.call,
            label: '拨打 ${info.value}',
            data: info.value,
          ));
        case KeyType.link:
          actions.add(ActionItem(
            type: ActionType.open,
            label: '打开链接',
            data: info.value,
          ));
        case KeyType.email:
          actions.add(ActionItem(
            type: ActionType.mail,
            label: '发送邮件',
            data: info.value,
          ));
        default:
          break;
      }
    }
    return actions;
  }
}
