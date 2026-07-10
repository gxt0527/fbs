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

  // ═══════════════ Public API ═══════════════

  static ParsedContent parse(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return ParsedContent(title: '', subtitle: '', body: '');

    final lines = raw
        .split(RegExp(r'\n|\r\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return ParsedContent(title: raw, subtitle: '', body: '');

    final category = _detectCategory(raw);
    final title = _extractTitle(lines, category);
    final subtitle = _extractSubtitle(lines, title, category);
    final keyInfos = _extractKeyInfos(raw);
    final actions = _deriveActions(keyInfos);

    return ParsedContent(
      title: title,
      subtitle: subtitle,
      body: raw,
      category: category,
      keyInfos: keyInfos,
      actions: actions,
    );
  }

  /// Strip emoji from a string.
  static String stripEmoji(String s) => s.replaceAll(_emojiRegex, '').trim();

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

    // Find the first non-empty non-emoji-only line
    String pick(List<String> ls) {
      for (final l in ls) {
        final cleaned = l.replaceAll(_emojiRegex, '').trim();
        if (cleaned.isNotEmpty) return cleaned;
      }
      return '';
    }

    var first = pick(lines);
    if (first.isEmpty) return '';

    // If it has 【】 brackets, keep it
    if (first.contains('【')) return _truncate(first, 60);

    // Category-specific: try to form a meaningful title
    switch (category) {
      case ParsedCategory.express:
        return _match(lines, [
          RegExp(r'【[^】]+】.*?(?:包裹|快递|快件|物流).*'),
          RegExp(r'.*(?:已签收|已到达|派送中|即将派送|待取件).*'),
        ]) ?? first;

      case ParsedCategory.foodDelivery:
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

  static String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max - 3)}...' : s;

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
      // Skip lines that are code/phone/URL/address-only
      if (RegExp(r'^(1[3-9]\d{9}|https?://|[京津沪]|验证码|取件码)\s*').hasMatch(candidate)) continue;
      second = candidate;
      break;
    }
    return _truncate(second, 60);
  }

  // ═══════════════ Key Infos ═══════════════

  static List<KeyInfo> _extractKeyInfos(String text) {
    final infos = <KeyInfo>[];
    final clean = text.replaceAll(_emojiRegex, '');

    void add(KeyInfo v) {
      if (!infos.any((i) => i.label == v.label && i.value == v.value)) {
        infos.add(v);
      }
    }

    // 1. 取件码 / 验证码
    for (final m in RegExp(
      r'(取件码|取餐码|提货码|验证码|核销码|兑换码|校验码|动态码)\s*[:：]?\s*([A-Za-z0-9]{4,12})',
    ).allMatches(clean)) {
      add(KeyInfo(label: m.group(1)!, value: m.group(2)!, type: KeyType.code));
    }

    // 2. 订单号 / 运单号
    for (final m in RegExp(
      r'(订单号|运单号|快递单号|交易单号|流水号|订单编号|商品单号)\s*[:：]?\s*([A-Za-z0-9\-]{8,30})',
    ).allMatches(clean)) {
      add(KeyInfo(label: m.group(1)!, value: m.group(2)!, type: KeyType.order));
    }

    // 3. 金额（有标签）
    for (final m in RegExp(
      r'(金额|消费|支付|收款|转账|退款|支出|收入|到账|费用|合计|共)[：:]?\s*'
      r'(人民币|美元|港币|欧元)?\s*[¥￥]?\s*'
      r'(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?)\s*(元|块|美元|港币|欧元)?',
    ).allMatches(clean)) {
      var amount = m.group(3)!;
      if (m.group(4)?.isNotEmpty == true) amount += m.group(4)!;
      add(KeyInfo(label: m.group(1)!, value: amount, type: KeyType.amount));
    }
    // 金额（¥ 前缀独立）
    for (final m in RegExp(
      r'[¥￥]\s*(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?)\s*(元|块)?',
    ).allMatches(clean)) {
      var amount = '¥${m.group(1)!}';
      if (m.group(2)?.isNotEmpty == true) amount += m.group(2)!;
      add(KeyInfo(label: '金额', value: amount, type: KeyType.amount));
    }

    // 4. 手机号
    for (final m in RegExp(
      r'(?:[电話电话联系方式][：:]?\s*)?(1[3-9]\d{9})',
    ).allMatches(clean)) {
      add(KeyInfo(label: '电话', value: m.group(1)!, type: KeyType.phone));
    }

    // 5. 链接
    for (final m in RegExp(
      r'(https?://[^\s,，；;<>"()（）]{3,150})',
    ).allMatches(clean)) {
      add(KeyInfo(label: '链接', value: m.group(1)!, type: KeyType.link));
    }

    // 6. 邮箱
    for (final m in RegExp(
      r'([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})',
    ).allMatches(clean)) {
      add(KeyInfo(label: '邮箱', value: m.group(1)!, type: KeyType.email));
    }

    // 7. 车牌号
    for (final m in RegExp(
      r'[京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤川青藏琼]'
      r'[A-Z][A-HJ-NP-Z0-9]{4,5}[A-HJ-NP-Z0-9挂学警港澳]',
    ).allMatches(clean)) {
      add(KeyInfo(label: '车牌', value: m.group(0)!, type: KeyType.location));
    }

    // 8. 航班号
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
    // 短时间（HH:mm 范围）
    for (final m in RegExp(
      r'(预计|约)?\s*[:：]?\s*'
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

    // 11. 地址 / 地点
    for (final m in RegExp(
      r'(地址|地点|位置|定位|上车点|下车点|取件地址|收货地址)[：:]\s*(.{4,50})',
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
