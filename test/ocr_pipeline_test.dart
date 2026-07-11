// 模拟 PaddleOCR 从三张图片提取的文本（按行合并）
// 测试目标: 找出整张截图 OCR 后转背屏失败的根因

import 'package:characters/characters.dart';
import 'package:fbs/services/content_parser.dart';

void main() {
  // ══════════════ 整张截图1（美团订单详情）模拟 OCR 输出 ══════════════
  // PaddleOCR 对状态栏/二维码/装饰元素的常见识别：
  final screenshot1Ocr = '''
20:22  5G 58
订单详情 2.0
取餐码
7656
订单已完成，祝您用餐愉快
进群天天抽免单
加店长领30元券包
长按识别二维码
支付有礼 支付完成1分钟后发放 3张券
请在有效期内使用哦
本单可获得 68 雪王币 0元兑零食
新乡工商职业学院店-No.954...
直线距离409m 河南省新乡市新乡市平原城乡
一体化示范区祝楼乡闫庄村美食广场1号摊位
薄荷奶绿 大杯/正常冰/七分糖 ¥8
×1
优惠券 -¥1.2 详情
共1件，合计 ¥6.8
奖励68雪王币 +7甜蜜值(1分钟后发放奖励)
再来一单
''';

  // ══════════════ 整张截图2（妈妈驿站）模拟 OCR 输出 ══════════════
  final screenshot2Ocr = '''
10:44
妈妈驿站
106888075205763
6月17日 10:12
【妈妈驿站】取货码 3-2-8188，您有
圆通快递包裹，已到祝楼乡印刷厂闫
庄桥头妈妈驿站
提醒我
查看更多
''';

  // ══════════════ 裁切截图1（取餐码）模拟 OCR 输出 ══════════════
  final cropped1Ocr = '''
取餐码
7656
订单已完成，祝您用餐愉快
''';

  print('═══════════════════════════════════════════════════════════');
  print('1️⃣  整张截图1 - OCR 文本长度: ${screenshot1Ocr.length}');
  print('═══════════════════════════════════════════════════════════');
  _testPipeline(screenshot1Ocr, '整张截图1');

  print('\n═══════════════════════════════════════════════════════════');
  print('2️⃣  整张截图2 - OCR 文本长度: ${screenshot2Ocr.length}');
  print('═══════════════════════════════════════════════════════════');
  _testPipeline(screenshot2Ocr, '整张截图2');

  print('\n═══════════════════════════════════════════════════════════');
  print('3️⃣  裁切截图1 - OCR 文本长度: ${cropped1Ocr.length}');
  print('═══════════════════════════════════════════════════════════');
  _testPipeline(cropped1Ocr, '裁切截图1');
}

void _testPipeline(String ocrText, String label) {
  // ── 步骤 1: 检测控制字符和特殊字符 ──
  final controlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]');
  final specialChars = RegExp(r'[\u200B-\u200F\u202A-\u202E\uFEFF\uFFFE\uFFFF]');
  final hasControl = ocrText.contains(controlChars);
  final hasSpecial = ocrText.contains(specialChars);
  final hasCr = ocrText.contains('\r');
  final hasTab = ocrText.contains('\t');

  print('原始 OCR 文本:');
  print('  长度: ${ocrText.length} 字符 / ${ocrText.split("\n").length} 行');
  print('  控制字符: $hasControl, 零宽/双向: $hasSpecial, \\r: $hasCr, \\t: $hasTab');

  // ── 步骤 2: 用修复前的 ContentParser 截断（模拟旧行为） ──
  print('\n【旧版截断】直接 substring(0, 197):');
  if (ocrText.length > 200) {
    try {
      final oldBody = '${ocrText.substring(0, 197)}...';
      print('  ✅ 截断成功，长度: ${oldBody.length}');
    } catch (e) {
      print('  ❌ 截断异常: $e');
    }
  } else {
    print('  长度 < 200，无需截断');
  }

  // ── 步骤 3: 用修复后的 ContentParser.sanitizeOcrText 清洗 ──
  print('\n【新版清洗】sanitizeOcrText():');
  final sanitized = ContentParser.sanitizeOcrText(ocrText);
  print('  清洗后长度: ${sanitized.length} (原始 ${ocrText.length})');
  if (sanitized.length != ocrText.length) {
    print('  ⚠️  清洗掉 ${ocrText.length - sanitized.length} 个字符');
  }

  // ── 步骤 4: 模拟 Intent extras 传递到大字符串 ──
  print('\n【Intent extras】传递到背屏:');
  print('  清洗后 content 长度: ${sanitized.length} chars');
  print('  preview: ${sanitized.substring(0, sanitized.length.clamp(0, 60))}...');
  print('  预估背屏行数(按 16sp 一行): ~${(sanitized.length / 25).round()}');

  // ── 步骤 5: 模拟 Canvas 渲染关键点 ──
  print('\n【Canvas StaticLayout】关键检查:');
  final hasEmoji = sanitized.contains(RegExp(
    r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{FE00}-\u{FE0F}\u{200D}]',
    unicode: true,
  ));
  print('  含 emoji: $hasEmoji');
  print('  最长行: ${sanitized.split("\n").map((l) => l.length).reduce((a, b) => a > b ? a : b)} chars');
  print('  总行数: ${sanitized.split("\n").length}');

  // ── 步骤 6: 跑 ContentParser.parse 看结果 ──
  print('\n【ContentParser.parse()】解析结果:');
  try {
    final parsed = ContentParser.parse(sanitized);
    print('  title: "${parsed.title}"');
    print('  subtitle: "${parsed.subtitle}"');
    print('  body 长度: ${parsed.body.length} chars');
    print('  body preview: ${parsed.body.substring(0, parsed.body.length.clamp(0, 60))}');
    print('  category: ${parsed.category.name}');
    print('  keyInfos: ${parsed.keyInfos.length} 个');
    for (final ki in parsed.keyInfos) {
      print('    - ${ki.label}: ${ki.value}');
    }
  } catch (e, st) {
    print('  ❌ parse 异常: $e');
    print('  $st');
  }
}
