import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/history_record.dart';
import '../services/history_service.dart';
import '../services/native_service.dart';
import '../services/scene_icons.dart';
import '../services/content_parser.dart';
import '../models/notification_style.dart';
import '../main.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  final _historyService = HistoryService();
  final _nativeService = NativeService();

  List<HistoryGroup> _groups = [];
  bool _loading = true;
  bool _selectMode = false;
  final Set<String> _selectedIds = {};
  bool _isForwarding = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  /// 外部可调用刷新（从底部导航切换时触发）
  void refresh() {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final records = await _historyService.getAll();
    final groups = _groupByDate(records);
    if (mounted) {
      setState(() {
        _groups = groups;
        _loading = false;
      });
    }
  }

  List<HistoryGroup> _groupByDate(List<HistoryRecord> records) {
    if (records.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final map = <DateTime, List<HistoryRecord>>{};
    for (final r in records) {
      final day = DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day);
      map.putIfAbsent(day, () => []).add(r);
    }

    final groups = <HistoryGroup>[];
    final sortedDays = map.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final day in sortedDays) {
      String label;
      if (day == today) {
        label = '今天';
      } else if (day == yesterday) {
        label = '昨天';
      } else {
        label = '${day.month}月${day.day}日';
      }
      groups.add(HistoryGroup(
        dateLabel: label,
        date: day,
        records: map[day]!,
      ));
    }
    return groups;
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      final allIds = _groups.expand((g) => g.records).map((r) => r.id).toSet();
      if (_selectedIds.length == allIds.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(allIds);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 ${_selectedIds.length} 条记录吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _historyService.removeAll(_selectedIds.toList());
      _selectedIds.clear();
      _toggleSelectMode();
      _loadHistory();
    }
  }

  Future<void> _deleteOne(String id) async {
    await _historyService.remove(id);
    _loadHistory();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _reForward(HistoryRecord record) async {
    if (_isForwarding) return;
    setState(() => _isForwarding = true);

    try {
      // Re-forward to super island (template 9)
      await _nativeService.sendFocusWithNetworkBypassTemplate9(
        label: record.label,
        codeValue: record.codeValue,
        storeName: record.storeName,
        items: record.items,
        amount: record.amount,
        category: record.category,
      );

      // Re-forward to back screen
      // 延迟 400ms 再转背屏，避免和超级岛同步渲染时卡顿
      await Future.delayed(const Duration(milliseconds: 400));
      final style = await NotificationStyle.load();
      final styleMap = {
        'titleFontSize': style.titleFontSize.toString(),
        'subtitleFontSize': style.subtitleFontSize.toString(),
        'contentFontSize': style.contentFontSize.toString(),
        'titleColor':
            '#${style.titleColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'subtitleColor':
            '#${style.subtitleColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'contentColor':
            '#${style.contentColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'backgroundColor':
            '#${style.backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'showAppIcon': style.showAppIcon.toString(),
        'showTimestamp': style.showTimestamp.toString(),
        'cameraAvoidanceEnabled': style.cameraAvoidanceEnabled.toString(),
        'horizontalOffset':
            NotificationStyle.cameraAvoidanceOffset.toStringAsFixed(0),
        'padding': style.padding.toString(),
        'spacing': style.spacing.toString(),
        'displayDurationMs': style.displayDurationMs.toString(),
        'useOfficialBackground': style.useOfficialBackground.toString(),
      };

      await _nativeService.displayOnBackScreen(
        title: record.label,
        subtitle: record.codeValue,
        content: record.displayContent,
        styleExtras: styleMap,
        category: record.category,
      );

      if (mounted) {
        _nativeService.showToast('已再次转发: ${record.label}');
      }
    } catch (e) {
      if (mounted) {
        _nativeService.showToast('转发失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isForwarding = false);
    }
  }

  ParsedCategory _toCategory(String category) {
    try {
      return ParsedCategory.values.firstWhere((c) => c.name == category);
    } catch (_) {
      return ParsedCategory.general;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: _selectMode ? _buildSelectAppBar() : _buildNormalAppBar(isDark),
      body: _buildBody(isDark),
      bottomNavigationBar:
          _selectMode ? _buildSelectBottomBar(isDark) : null,
    );
  }

  AppBar _buildNormalAppBar(bool isDark) {
    return AppBar(
      title: Text(
        '记录',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          letterSpacing: -0.3,
        ),
      ),
      actions: [
        if (_groups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _toggleSelectMode,
              child: const Text('选择', style: TextStyle(fontSize: 14)),
            ),
          ),
      ],
    );
  }

  AppBar _buildSelectAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _toggleSelectMode,
      ),
      title: Text(
        '已选 ${_selectedIds.length} 项',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextButton(
            onPressed: _selectAll,
            child: Text(
              _selectedIds.length ==
                      _groups.expand((g) => g.records).length
                  ? '取消全选'
                  : '全选',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectBottomBar(bool isDark) {
    final hasSelection = _selectedIds.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF8F8F8),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: hasSelection ? _deleteSelected : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(
                    color: hasSelection
                        ? Colors.red.withValues(alpha: 0.5)
                        : Colors.grey.withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
                  ),
                ),
                child: Text(
                  hasSelection ? '删除(${_selectedIds.length})' : '删除',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 56,
                color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 12),
            Text(
              '暂无转发记录',
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '转发内容后将自动记录在此',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _groups.length,
      itemBuilder: (context, groupIndex) {
        final group = _groups[groupIndex];
        return _buildGroup(group, isDark);
      },
    );
  }

  Widget _buildGroup(HistoryGroup group, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Text(
            group.dateLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ),
        // Records
        ...group.records.asMap().entries.map((entry) {
          final idx = entry.key;
          final record = entry.value;
          final isLast = idx == group.records.length - 1;
          return _buildRecordItem(record, isLast, isDark);
        }),
      ],
    );
  }

  Widget _buildRecordItem(HistoryRecord record, bool isLast, bool isDark) {
    final categoryColor = SceneIcons.color(_toCategory(record.category));
    final isSelected = _selectedIds.contains(record.id);

    return GestureDetector(
      onLongPress: () {
        if (!_selectMode) {
          setState(() {
            _selectMode = true;
            _selectedIds.add(record.id);
          });
        }
      },
      onTap: _selectMode ? () => _toggleSelect(record.id) : null,
      child: Dismissible(
        key: Key(record.id),
        direction: _selectMode
            ? DismissDirection.none
            : DismissDirection.endToStart,
        confirmDismiss: (direction) async {
          return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('确认删除'),
              content: const Text('确定要删除这条记录吗？'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('删除', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
        },
        onDismissed: (_) => _deleteOne(record.id),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: Colors.red.withValues(alpha: 0.85),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        child: Container(
          margin: EdgeInsets.fromLTRB(
              12, 0, 12, isLast ? 0 : 1),
          decoration: BoxDecoration(
            color: isSelected
                ? GlassTokens.accent.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                // Checkbox in select mode
                if (_selectMode) ...[
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelect(record.id),
                    activeColor: GlassTokens.accent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
                // Time
                SizedBox(
                  width: 42,
                  child: Text(
                    '${record.timestamp.hour.toString().padLeft(2, '0')}:${record.timestamp.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Category icon
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: categoryColor.withValues(alpha: 0.1),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      SceneIcons.assetPath(_toCategory(record.category)),
                      width: 14,
                      height: 14,
                      colorFilter:
                          ColorFilter.mode(categoryColor, BlendMode.srcIn),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            record.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color:
                                  isDark ? Colors.white : const Color(0xFF1A1A2E),
                            ),
                          ),
                          if (record.codeValue.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: categoryColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                record.codeValue,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: categoryColor,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (record.displayContent.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          record.displayContent,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white38 : Colors.black45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Forward button
                if (!_selectMode)
                  _buildActionButton(
                    icon: Icons.send_rounded,
                    color: GlassTokens.accent,
                    onTap: () => _reForward(record),
                  ),
                if (!_selectMode)
                  _buildActionButton(
                    icon: Icons.delete_outline,
                    color: Colors.red.withValues(alpha: 0.6),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('确认删除'),
                          content: const Text('确定要删除这条记录吗？'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消')),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('删除',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        _deleteOne(record.id);
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
        onTap: _isForwarding ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
