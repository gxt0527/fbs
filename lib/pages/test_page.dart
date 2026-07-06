import 'package:flutter/material.dart';
import '../services/native_service.dart';

class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  final _nativeService = NativeService();
  bool _isRunning = false;
  List<Map<String, dynamic>> _results = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _nativeService.initialize();
  }

  Future<void> _runTests() async {
    setState(() {
      _isRunning = true;
      _results = [];
      _error = null;
    });

    try {
      final results = await _nativeService.runAllTests();
      setState(() {
        _results = results;
        _isRunning = false;
      });
      if (results.isEmpty) {
        setState(() => _error = '未返回任何结果');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('背屏接口测试'),
        actions: [
          IconButton(
            icon: _isRunning
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            onPressed: _isRunning ? null : _runTests,
            tooltip: '运行全部测试',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isRunning) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在测试所有接口...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _runTests, child: const Text('重试')),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.science, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('点击右上角按钮开始测试'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _runTests,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始测试'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _buildStats() + _results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildStatsCard();
        }
        if (index <= _results.length) {
          return _buildResultCard(_results[index - 1]);
        }
        return const SizedBox(height: 32);
      },
    );
  }

  int _buildStats() => 1;

  Widget _buildStatsCard() {
    final passed = _results.where((r) => r['passed'] == true).length;
    final failed = _results.where((r) => r['passed'] == false).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: passed == _results.length ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _statChip('总数', '${_results.length}', Colors.blue),
            const SizedBox(width: 24),
            _statChip('通过', '$passed', Colors.green),
            const SizedBox(width: 24),
            _statChip('失败', '$failed', Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildResultCard(Map<String, dynamic> result) {
    final passed = result['passed'] == true;
    final name = result['name'] ?? '';
    final method = result['method'] ?? '';
    final output = result['output'] ?? '';
    final requiresShizuku = result['requiresShizuku'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  passed ? Icons.check_circle : Icons.cancel,
                  color: passed ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: method.contains('Shizuku')
                        ? Colors.purple.shade50
                        : Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    method,
                    style: TextStyle(
                      fontSize: 11,
                      color: method.contains('Shizuku')
                          ? Colors.purple
                          : Colors.teal,
                    ),
                  ),
                ),
                if (requiresShizuku) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.shield, size: 14, color: Colors.orange.shade400),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: passed ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                output,
                style: TextStyle(fontSize: 12, color: passed ? Colors.green.shade800 : Colors.red.shade800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
