import 'package:flutter/material.dart';

/// 滑动转场路由 — Android 原生风格 (参考 Pronto/PathInterpolator)
class SlideRoute<T> extends MaterialPageRoute<T> {
  SlideRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => const Duration(milliseconds: 350);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);
}
