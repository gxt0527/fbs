class ParsedContent {
  final String title;
  final String subtitle;
  final String body;
  final List<KeyInfo> keyInfos;
  ParsedContent({required this.title, required this.subtitle, required this.body, this.keyInfos = const []});
}

class KeyInfo {
  final String label;
  final String value;
  final KeyType type;
  const KeyInfo({required this.label, required this.value, this.type = KeyType.general});
}

enum KeyType { code, time, order, location, general }

class ContentParser {
  static ParsedContent parse(String text) {
    if (text.trim().isEmpty) return ParsedContent(title: '', subtitle: '', body: '');
    final lines = text.split(RegExp(r'\n|\r\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return ParsedContent(title: text.trim(), subtitle: '', body: '');
    final title = _extractTitle(lines);
    final subtitle = _extractSubtitle(lines, title);
    final keyInfos = _extractKeyInfos(text);
    return ParsedContent(title: title, subtitle: subtitle, body: text.trim(), keyInfos: keyInfos);
  }

  static String _extractTitle(List<String> lines) {
    if (lines.isEmpty) return '';
    final first = lines.first;
    final patterns = [
      RegExp(r'^(?:【.*?】)?\s*(?:快递|包裹|物流|取件|派件|签收)'),
      RegExp(r'^(?:【.*?】)?\s*(?:外卖|订单|配送|取餐|骑手)'),
      RegExp(r'^(?:【.*?】)?\s*(?:通知|提醒|待办|日程|会议|预约)'),
      RegExp(r'^(?:【.*?】)?\s*(?:支付|收款|转账|消费|退款)'),
      RegExp(r'^【.+】'),
    ];
    for (final p in patterns) { if (p.hasMatch(first)) return first; }
    return first.length > 60 ? '${first.substring(0, 57)}...' : first;
  }

  static String _extractSubtitle(List<String> lines, String title) {
    if (lines.length < 2) {
      for (final p in [RegExp(r'(已取件|派送中|已签收|待取件|运输中|已发货|待发货)'),
        RegExp(r'(已接单|制作中|已取餐|配送中|已送达|待支付)'),
        RegExp(r'(进行中|已完成|已取消|即将开始|已过期)')]) {
        final m = p.firstMatch(lines.first);
        if (m != null) return m.group(0)!;
      }
      return '';
    }
    var second = lines[1];
    if (second == title && lines.length > 2) second = lines[2];
    return second.length > 60 ? '${second.substring(0, 57)}...' : second;
  }

  static List<KeyInfo> _extractKeyInfos(String text) {
    final infos = <KeyInfo>[];
    for (final pattern in [RegExp(r'(取件码|取餐码|提货码|验证码|核销码|兑换码)\s*[:：]?\s*([A-Za-z0-9]{4,12})')]) {
      for (final match in pattern.allMatches(text)) {
        infos.add(KeyInfo(label: match.group(1)!, value: match.group(2)!, type: KeyType.code));
      }
    }
    for (final pattern in [RegExp(r'(订单号|运单号|快递单号|交易单号|流水号)\s*[:：]?\s*([A-Za-z0-9\-]{8,30})')]) {
      for (final match in pattern.allMatches(text)) {
        infos.add(KeyInfo(label: match.group(1)!, value: match.group(2)!, type: KeyType.order));
      }
    }
    for (final pattern in [RegExp(r'(预计|预计送达|提醒|取件|截止|到期|开始)?\s*[:：]?\s*'
        r'(\d{4}[-/年]\d{1,2}[-/月]\d{1,2}[日号]?)\s*(\d{1,2}[:：]\d{2})?'),
        RegExp(r'(预计|约)?\s*[:：]?\s*(\d{1,2}[:：]\d{2})\s*(?:[~—\-~至到]\s*(\d{1,2}[:：]\d{2}))?')]) {
      for (final match in pattern.allMatches(text)) {
        final full = match.group(0)!.trim();
        if (full.isNotEmpty && !infos.any((i) => i.value == full)) {
          infos.add(KeyInfo(label: '时间', value: full, type: KeyType.time));
        }
      }
    }
    return infos;
  }
}
