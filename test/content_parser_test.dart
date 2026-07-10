import 'package:flutter_test/flutter_test.dart';
import 'package:fbs/services/content_parser.dart';

void main() {
  group('ContentParser.parse', () {
    // ═══════════════════════════════════════════════
    // 快递场景
    // ═══════════════════════════════════════════════
    test('快递 — 顺丰取件码', () {
      final text = '【顺丰快递】您的包裹已到达小区菜鸟驿站\n'
          '取件码: 1234, 请及时取件\n'
          '预计营业时间: 08:00-22:00';
      final result = ContentParser.parse(text);
      expect(result.title, contains('顺丰'));
      expect(result.category, ParsedCategory.express);
      expect(result.keyInfos.any((k) => k.label == '取件码' && k.value == '1234'), true);
      expect(result.keyInfos.any((k) => k.type == KeyType.time), true);
      expect(result.actions.any((a) => a.type == ActionType.copy && a.data == '1234'), true);
    });

    test('快递 — 京东签收', () {
      final text = '【京东物流】订单已由本人签收，感谢使用京东物流';
      final result = ContentParser.parse(text);
      expect(result.title, contains('签收'));
      expect(result.subtitle, '已由本人签收');
    });

    test('快递 — 菜鸟裹裹', () {
      final text = '📦 【菜鸟裹裹】您的快递已到菜鸟驿站\n取件码: 567890';
      final result = ContentParser.parse(text);
      expect(result.title, contains('菜鸟'));
      expect(result.title, isNot(contains('📦'))); // emoji stripped
      expect(result.category, ParsedCategory.express);
      expect(result.keyInfos.any((k) => k.label == '取件码' && k.value == '567890'), true);
    });

    test('快递 — 物流派送中', () {
      final text = '【中通快递】您的包裹正在派送中\n派送员: 张师傅 13800138000';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.express);
      expect(result.subtitle, '派送中');
      expect(result.keyInfos.any((k) => k.type == KeyType.phone), true);
    });

    // ═══════════════════════════════════════════════
    // 外卖场景
    // ═══════════════════════════════════════════════
    test('外卖 — 美团配送中', () {
      final text = '【美团外卖】骑手已取餐，正在向您飞奔\n预计送达时间: 12:30';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.foodDelivery);
      expect(result.title, contains('美团'));
      expect(result.keyInfos.any((k) => k.type == KeyType.time), true);
    });

    test('外卖 — 饿了么已送达', () {
      final text = '【饿了么】您的订单已送达，请及时取餐';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.foodDelivery);
    });

    test('外卖 — 骑手取餐', () {
      final text = '【美团】骑手已取餐，预计15分钟送达\n取餐码: 8866';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.foodDelivery);
      expect(result.keyInfos.any((k) => k.type == KeyType.code && k.value == '8866'), true);
      expect(result.actions.any((a) => a.type == ActionType.copy && a.data == '8866'), true);
    });

    // ═══════════════════════════════════════════════
    // 支付场景
    // ═══════════════════════════════════════════════
    test('支付 — 微信收款', () {
      final text = '微信支付收款0.01元\n收款方: 张三便利店';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.payment);
      expect(result.keyInfos.any((k) => k.type == KeyType.amount), true);
    });

    test('支付 — 支付宝到账', () {
      final text = '【支付宝】成功向李四转账100.00元\n转账成功';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.payment);
      expect(result.keyInfos.any((k) => k.type == KeyType.amount), true);
    });

    test('支付 — 银行支出', () {
      final text = '尾号8888的储蓄卡支出人民币1,000.00元';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.payment);
      expect(result.keyInfos.any((k) => k.type == KeyType.amount), true);
    });

    // ═══════════════════════════════════════════════
    // 验证码场景
    // ═══════════════════════════════════════════════
    test('验证码 — 通用', () {
      final text = '【XX应用】验证码 123456，5分钟内有效，请勿泄露';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.verification);
      expect(result.keyInfos.any((k) => k.type == KeyType.code && k.value == '123456'), true);
    });

    test('验证码 — 含兑换码', () {
      final text = '您的兑换码: ABC12345，请在24小时内使用';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.verification);
      expect(result.keyInfos.any((k) => k.type == KeyType.code), true);
    });

    // ═══════════════════════════════════════════════
    // 会议场景
    // ═══════════════════════════════════════════════
    test('会议 — 腾讯会议', () {
      final text = '【腾讯会议】您有一个会议即将开始\n会议主题: 周会\n会议时间: 2026-07-09 15:00';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.meeting);
      expect(result.keyInfos.any((k) => k.type == KeyType.time), true);
    });

    test('会议 — 日程提醒', () {
      final text = '🔔 日程提醒: 项目评审会\n时间: 今天 15:00-16:00';
      final result = ContentParser.parse(text);
      expect(result.title, isNot(contains('🔔')));
      expect(result.category, ParsedCategory.meeting);
    });

    // ═══════════════════════════════════════════════
    // 出行场景
    // ═══════════════════════════════════════════════
    test('出行 — 滴滴打车', () {
      final text = '【滴滴出行】快车 (京A88888) 已到达上车点\n司机: 王师傅';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.travel);
      expect(result.keyInfos.any((k) => k.type == KeyType.location && k.value.contains('京A')), true);
    });

    test('出行 — 航班提醒', () {
      final text = '【航旅纵横】您乘坐的CA1234航班登机口已变更为A12';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.travel);
      expect(result.keyInfos.any((k) => k.label == '航班' && k.value == 'CA1234'), true);
    });

    test('出行 — 高铁车次', () {
      final text = '【携程】您已预订明日G1234次列车，北京南-上海虹桥';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.travel);
      expect(result.keyInfos.any((k) => k.label == '车次' && k.value == 'G1234'), true);
    });

    // ═══════════════════════════════════════════════
    // 通用关键信息提取
    // ═══════════════════════════════════════════════
    test('通用 — 电话号码', () {
      final text = '联系人: 李经理\n联系电话: 13912345678';
      final result = ContentParser.parse(text);
      expect(result.keyInfos.any((k) => k.type == KeyType.phone), true);
    });

    test('通用 — 链接', () {
      final text = '详情请查看: https://example.com/order/123';
      final result = ContentParser.parse(text);
      expect(result.keyInfos.any((k) => k.type == KeyType.link), true);
      expect(result.actions.any((a) => a.type == ActionType.open), true);
    });

    test('通用 — 邮箱', () {
      final text = '客服邮箱: support@example.com';
      final result = ContentParser.parse(text);
      expect(result.keyInfos.any((k) => k.type == KeyType.email), true);
    });

    test('通用 — 订单号', () {
      final text = '订单号: SF1234567890，预计明天送达';
      final result = ContentParser.parse(text);
      expect(result.keyInfos.any((k) => k.type == KeyType.order && k.value == 'SF1234567890'), true);
    });

    test('通用 — 地址', () {
      final text = '收货地址: 北京市朝阳区望京街道100号';
      final result = ContentParser.parse(text);
      expect(result.keyInfos.any((k) => k.type == KeyType.location), true);
    });

    // ═══════════════════════════════════════════════
    // 边界情况
    // ═══════════════════════════════════════════════
    test('边界 — 空文本', () {
      final result = ContentParser.parse('');
      expect(result.title, '');
      expect(result.subtitle, '');
      expect(result.body, '');
      expect(result.category, ParsedCategory.general);
      expect(result.keyInfos, isEmpty);
      expect(result.actions, isEmpty);
    });

    test('边界 — 纯空格', () {
      final result = ContentParser.parse('   \n  \n  ');
      expect(result.title, '');
    });

    test('边界 — 单行无格式', () {
      final result = ContentParser.parse('普通通知内容');
      expect(result.title, '普通通知内容');
      expect(result.category, ParsedCategory.general);
    });

    test('边界 — 非常长的标题截断', () {
      final long = 'A' * 100;
      final result = ContentParser.parse(long);
      expect(result.title.length, 60);
      expect(result.title.endsWith('...'), true);
    });

    test('边界 — emoji 清理', () {
      final text = '📱🎉【测试】新消息来了 ✅';
      final result = ContentParser.parse(text);
      expect(result.title, isNot(contains('📱')));
      expect(result.title, isNot(contains('🎉')));
      expect(result.title, isNot(contains('✅')));
      expect(result.title, contains('【测试】新消息来了'));
    });

    // ═══════════════════════════════════════════════
    // 动作推导
    // ═══════════════════════════════════════════════
    test('动作 — code 生成 copy', () {
      final text = '取件码: 8888';
      final result = ContentParser.parse(text);
      expect(result.actions.any((a) => a.type == ActionType.copy && a.data == '8888'), true);
    });

    test('动作 — phone 生成 call', () {
      final text = '电话: 13800138000';
      final result = ContentParser.parse(text);
      expect(result.actions.any((a) => a.type == ActionType.call), true);
    });

    test('动作 — link 生成 open', () {
      final text = '链接: https://example.com';
      final result = ContentParser.parse(text);
      expect(result.actions.any((a) => a.type == ActionType.open), true);
    });

    test('动作 — email 生成 mail', () {
      final text = '邮箱: test@example.com';
      final result = ContentParser.parse(text);
      expect(result.actions.any((a) => a.type == ActionType.mail), true);
    });

    // ═══════════════════════════════════════════════
    // 账单场景
    // ═══════════════════════════════════════════════
    test('账单 — 话费', () {
      final text = '【中国移动】您的话费账单已出，本月费用45.00元';
      final result = ContentParser.parse(text);
      expect(result.category, ParsedCategory.bill);
      expect(result.keyInfos.any((k) => k.type == KeyType.amount), true);
    });
  });

  group('ContentParser.stripEmoji', () {
    test('移除前缀 emoji', () {
      expect(ContentParser.stripEmoji('📦 包裹已到'), '包裹已到');
    });
    test('移除中间 emoji', () {
      expect(ContentParser.stripEmoji('您的包裹 ✅ 已签收'), '您的包裹  已签收');
    });
    test('无 emoji 不变', () {
      expect(ContentParser.stripEmoji('正常文本'), '正常文本');
    });
  });

  group('ParsedCategory.label', () {
    test('中文字段映射', () {
      expect(ParsedCategory.express.label, '快递');
      expect(ParsedCategory.foodDelivery.label, '外卖');
      expect(ParsedCategory.payment.label, '支付');
      expect(ParsedCategory.order.label, '订单');
      expect(ParsedCategory.meeting.label, '会议');
      expect(ParsedCategory.travel.label, '出行');
      expect(ParsedCategory.verification.label, '验证');
      expect(ParsedCategory.bill.label, '账单');
      expect(ParsedCategory.system.label, '系统');
      expect(ParsedCategory.general.label, '通用');
    });
  });
}
