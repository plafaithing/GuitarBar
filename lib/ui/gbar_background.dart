import 'package:flutter/material.dart';

import 'theme.dart';

/// 全产品统一背景层（v2「aurora-dark」设计语言，reactbits 式）：
/// ground 底 + 两团 dataHue 系径向光晕（主光右上、次冷光左下）。
///
/// 所有页面的 Scaffold 一律 `backgroundColor: Colors.transparent`，
/// 由根壳（RootPage）与独立路由页（曲谱详情）在 body 外包这一层——
/// 光晕只在这里画一次，任何页面不得自绘背景，保证全产品单一风格。
///
/// 强度由色板 glowA/glowB 的 alpha 决定（暗色 ~15%/10%、浅色 ~10%/6%，
/// 浅色下淡到不干扰谱面阅读）。
class GbarBackground extends StatelessWidget {
  const GbarBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      // ground 先铺满（透明 Scaffold 需要），光晕用 IgnorePointer 的
      // Stack 叠加——不挡任何交互。
      decoration: BoxDecoration(color: p.ground),
      child: Stack(children: [
        // 主光晕：右上，dataHue。
        Positioned(
          top: -140,
          right: -120,
          child: IgnorePointer(
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [p.glowA, p.glowA.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
        // 次光晕：左下，冷调微光。
        Positioned(
          bottom: -180,
          left: -140,
          child: IgnorePointer(
            child: Container(
              width: 560,
              height: 560,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [p.glowB, p.glowB.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ]),
    );
  }
}
