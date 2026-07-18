import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/content_parser.dart';

/// 智能识别场景线性图标
/// 用于超级岛和背屏的取餐码等场景
///
/// ⚠️ 修改图标时需要同步更新：
///   1. 本文件（Flutter 侧 SVG 图标，assets/icons/）
///   2. FocusForwarder.kt（Android 侧 drawable XML 图标）
///   两者必须一一对应，只改一处会导致超级岛或背屏图标不一致。
class SceneIcons {
  SceneIcons._();

  /// 根据解析分类获取对应场景图标
  /// ⚠️ 同步参考 FocusForwarder.kt 的 sceneIconRes()，两处必须一致
  static String assetPath(ParsedCategory category) {
    return switch (category) {
      ParsedCategory.foodDelivery => 'assets/icons/ic_beverage_pickup.svg',
      ParsedCategory.express => 'assets/icons/ic_express.svg',
      ParsedCategory.verification => 'assets/icons/ic_verification.svg',
      ParsedCategory.payment => 'assets/icons/ic_payment.svg',
      ParsedCategory.travel => 'assets/icons/ic_travel.svg',
      ParsedCategory.meeting => 'assets/icons/ic_meeting.svg',
      ParsedCategory.order => 'assets/icons/ic_order.svg',
      ParsedCategory.bill => 'assets/icons/ic_bill.svg',
      ParsedCategory.system => 'assets/icons/ic_smart_scan.svg',
      ParsedCategory.general => 'assets/icons/ic_smart_scan.svg',
    };
  }

  /// 场景色 — 与现有 UI 配色保持一致
  static Color color(ParsedCategory category) {
    return switch (category) {
      ParsedCategory.express => const Color(0xFFFF9500),
      ParsedCategory.foodDelivery => const Color(0xFFFF375F),
      ParsedCategory.payment => const Color(0xFF34C759),
      ParsedCategory.meeting => const Color(0xFF0088FF),
      ParsedCategory.travel => const Color(0xFFAF52DE),
      ParsedCategory.verification => const Color(0xFFFF9500),
      ParsedCategory.bill => const Color(0xFF8E8E93),
      ParsedCategory.order => const Color(0xFF5AC8FA),
      ParsedCategory.system => const Color(0xFF8E8E93),
      ParsedCategory.general => const Color(0xFF8E8E93),
    };
  }

  /// 场景图标 Widget — 自适应 colorFilter
  static Widget icon(ParsedCategory category, {double size = 24, Color? color}) {
    final c = color ?? SceneIcons.color(category);
    return SvgPicture.asset(
      assetPath(category),
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
    );
  }
}
