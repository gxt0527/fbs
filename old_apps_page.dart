import 'dart:async';
import 'package:flutter/material.dart';
import '../models/monitor_settings.dart';
import '../services/native_service.dart';

class MonitorAppsPage extends StatefulWidget {
  const MonitorAppsPage({super.key});

  @override
  State<MonitorAppsPage> createState() => _MonitorAppsPageState();
}

class _MonitorAppsPageState extends State<MonitorAppsPage> {
  final NativeService _nativeService = NativeService();
  MonitorSettings _settings = MonitorSettings();
  List<Map<String, String>> _allApps = [];
  bool _isLoadingApps = true;
  String _searchQuery = '';
  bool _userAppsExpanded = false;
  bool _systemAppsExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final settings = await MonitorSettings.load();
    final apps = await _nativeService.getInstalledApps();
    if (mounted) {
      setState(() {
        _settings = settings;
        _allApps = apps;
        _isLoadingApps = false;
      });
    }
  }

  Future<void> _save() async {
    await _settings.save();
    _nativeService.updateMonitorSettings(
      monitorAll: _settings.monitorAll,
      enabledApps: _settings.enabledApps.toList(),
    );
  }

  List<Map<String, String>> _getFilteredApps() {
    if (_searchQuery.isEmpty) return _allApps;
    final q = _searchQuery.toLowerCase();
    return _allApps.where((a) {
      final name = (a['name'] ?? '').toLowerCase();
      final pkg = (a['package'] ?? '').toLowerCase();
      return name.contains(q) || pkg.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredApps();
    final userApps = filtered.where((a) => a['isSystem'] != 'true').toList();
    final systemApps = filtered.where((a) => a['isSystem'] == 'true').toList();
    final enabled = _settings.enabledApps;
    final filteredEnabled = filtered.where((a) => enabled.contains(a['package'])).length;

    // 鎶樺彔鏃舵樉绀虹殑鎽樿
    final userEnabledCount = userApps.where((a) => enabled.contains(a['package'])).length;
    final systemEnabledCount = systemApps.where((a) => enabled.contains(a['package'])).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('鐩戝惉搴旂敤鍒楄〃'),
      ),
      body: Column(
        children: [
          // 鎼滅储妗?          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: '鎼滅储搴旂敤鍚嶇О鎴栧寘鍚?..',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // 缁熻
          if (!_isLoadingApps)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '${filtered.length} 涓簲鐢?路 宸查€?$filteredEnabled 涓?,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  if (_searchQuery.isEmpty) ...[
                    TextButton(
                      onPressed: userApps.isEmpty ? null : () {
                        final allOn = userApps.every((a) => enabled.contains(a['package']));
                        setState(() {
                          for (final a in userApps) {
                            if (allOn) { enabled.remove(a['package']); }
                            else { enabled.add(a['package']!); }
                          }
                        });
                        _save();
                      },
                      child: Text(
                        userApps.every((a) => enabled.contains(a['package']))
                            ? '鐢ㄦ埛鍏ㄤ笉閫? : '鐢ㄦ埛鍏ㄩ€?,
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                      ),
                    ),
                    TextButton(
                      onPressed: systemApps.isEmpty ? null : () {
                        final allOn = systemApps.every((a) => enabled.contains(a['package']));
                        setState(() {
                          for (final a in systemApps) {
                            if (allOn) { enabled.remove(a['package']); }
                            else { enabled.add(a['package']!); }
                          }
                        });
                        _save();
                      },
                      child: Text(
                        systemApps.every((a) => enabled.contains(a['package']))
                            ? '绯荤粺鍏ㄤ笉閫? : '绯荤粺鍏ㄩ€?,
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const Divider(height: 1),
          // 鍒楄〃
          Expanded(
            child: _isLoadingApps
                ? const Center(child: Text('姝ｅ湪鍔犺浇搴旂敤鍒楄〃...', style: TextStyle(color: Colors.grey)))
                : filtered.isEmpty
                    ? const Center(child: Text('娌℃湁鎵惧埌鍖归厤鐨勫簲鐢?, style: TextStyle(color: Colors.grey)))
                    : ListView(
                        children: [
                          // 鐢ㄦ埛搴旂敤
                          if (userApps.isNotEmpty)
                            _buildCollapsibleSection(
                              title: '鐢ㄦ埛搴旂敤',
                              count: userApps.length,
                              enabledCount: userEnabledCount,
                              isExpanded: _userAppsExpanded,
                              onToggle: () => setState(() => _userAppsExpanded = !_userAppsExpanded),
                              apps: userApps,
                              enabled: enabled,
                            ),
                          // 绯荤粺搴旂敤
                          if (systemApps.isNotEmpty)
                            _buildCollapsibleSection(
                              title: '绯荤粺搴旂敤',
                              count: systemApps.length,
                              enabledCount: systemEnabledCount,
                              isExpanded: _systemAppsExpanded,
                              onToggle: () => setState(() => _systemAppsExpanded = !_systemAppsExpanded),
                              apps: systemApps,
                              enabled: enabled,
                            ),
                          const SizedBox(height: 48),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsibleSection({
    required String title,
    required int count,
    required int enabledCount,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Map<String, String>> apps,
    required Set<String> enabled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.chevron_right, size: 20, color: Colors.grey[600]),
                ),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$count 涓?,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                if (enabledCount > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '宸查€?$enabledCount',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: Colors.grey[500],
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        if (isExpanded)
          ...apps.map((a) => _buildTile(a, enabled)),
      ],
    );
  }

  Widget _buildTile(Map<String, String> app, Set<String> enabled) {
    final pkg = app['package']!;
    final name = app['name']!;
    final isOn = enabled.contains(pkg);
    final isSystem = app['isSystem'] == 'true';
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: isOn
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.1),
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isOn ? Theme.of(context).colorScheme.primary : Colors.grey,
          ),
        ),
      ),
      title: Text(name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(pkg, style: const TextStyle(fontSize: 11)),
      trailing: Switch(
        value: isOn,
        onChanged: (v) {
          setState(() {
            if (v) { enabled.add(pkg); } else { enabled.remove(pkg); }
          });
          _save();
        },
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
