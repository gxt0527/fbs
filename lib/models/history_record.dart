/// 单条历史转发记录
class HistoryRecord {
  final String id;
  final DateTime timestamp;
  final String category; // express, foodDelivery, payment, etc.
  final String label; // 主标题/标签（如 "取餐码"）
  final String codeValue; // 码值（如 "7656"）
  final String displayContent; // 展示内容
  final String rawText; // 原始文本
  final String storeName; // 店名/地址
  final String items; // 件数
  final String amount; // 金额

  const HistoryRecord({
    required this.id,
    required this.timestamp,
    required this.category,
    required this.label,
    this.codeValue = '',
    this.displayContent = '',
    this.rawText = '',
    this.storeName = '',
    this.items = '',
    this.amount = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'category': category,
        'label': label,
        'codeValue': codeValue,
        'displayContent': displayContent,
        'rawText': rawText,
        'storeName': storeName,
        'items': items,
        'amount': amount,
      };

  factory HistoryRecord.fromJson(Map<String, dynamic> json) => HistoryRecord(
        id: json['id'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            (json['timestamp'] as int?) ?? 0),
        category: json['category'] as String? ?? 'general',
        label: json['label'] as String? ?? '',
        codeValue: json['codeValue'] as String? ?? '',
        displayContent: json['displayContent'] as String? ?? '',
        rawText: json['rawText'] as String? ?? '',
        storeName: json['storeName'] as String? ?? '',
        items: json['items'] as String? ?? '',
        amount: json['amount'] as String? ?? '',
      );
}

/// 按日期分组的记录组
class HistoryGroup {
  final String dateLabel; // "今天", "昨天", "7月17日"
  final DateTime date; // 用于排序
  final List<HistoryRecord> records;

  const HistoryGroup({
    required this.dateLabel,
    required this.date,
    required this.records,
  });
}
