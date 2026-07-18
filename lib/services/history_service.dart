import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_record.dart';

/// 历史记录持久化服务（单例）
class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  static const _key = 'fbs_history_records';
  static const _maxRecords = 200; // 最多保留200条

  List<HistoryRecord>? _cache;

  /// 获取所有记录（按时间倒序）
  Future<List<HistoryRecord>> getAll() async {
    if (_cache != null) return List.unmodifiable(_cache!);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    _cache = raw
        .map((s) => HistoryRecord.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List.unmodifiable(_cache!);
  }

  /// 添加记录
  Future<void> add(HistoryRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.insert(0, jsonEncode(record.toJson()));
    // 限制最大条数
    while (raw.length > _maxRecords) {
      raw.removeLast();
    }
    await prefs.setStringList(_key, raw);
    // 更新缓存
    _cache = null;
  }

  /// 删除单条记录
  Future<void> remove(String id) async {
    final records = await getAll();
    final updated = records.where((r) => r.id != id).toList();
    await _saveAll(updated);
  }

  /// 批量删除
  Future<void> removeAll(List<String> ids) async {
    final records = await getAll();
    final idSet = ids.toSet();
    final updated = records.where((r) => !idSet.contains(r.id)).toList();
    await _saveAll(updated);
  }

  /// 清空所有记录
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _cache = null;
  }

  Future<void> _saveAll(List<HistoryRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = records.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList(_key, raw);
    _cache = records;
  }
}
