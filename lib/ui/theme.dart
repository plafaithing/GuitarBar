import 'package:flutter/material.dart';

/// GuitarBar 界面设计语言（achromatic-ledger 色彩账本风）。
///
/// 骨架无彩色：近黑主色、平面、静止零阴影；唯一的数据色 [GuitarBarColors.dataHue]
/// （玫瑰木琥珀）只允许出现在数据元素上（调音检测音名/音分、练习热力图、节拍器当前拍），
/// 严禁用于按钮、导航、标签页等界面骨架。
///
/// 圆角只有两档：卡片 8、控件 6。字重预算 400/500/600（700 留给日后最重要的数字）。
/// 数字类文本（调音 Hz/音分、BPM、计时）一律使用 `FontFeature.tabularFigures()`
/// 等宽数字 —— [GuitarBarTheme] 的 displaySmall/bodyMedium/bodySmall 已内置；
/// 后续页面任务对自己渲染的数字 Text 也要显式应用该特性。
class GuitarBarColors {
  GuitarBarColors._();

  /// 画布底色（云杉暖白）
  static const Color ground = Color(0xFFF7F5F1);

  /// 卡片/面板表面
  static const Color surface = Color(0xFFFFFFFF);

  /// 导航选中灰药丸
  static const Color activePill = Color(0xFFECECEC);

  /// 分隔边框
  static const Color border = Color(0xFFE6E6E6);

  /// 细分隔线（色调阶梯）
  static const Color rule = Color(0xFFF0F0F0);

  /// 控件描边
  static const Color controlBorder = Color(0xFFD4D4D4);

  /// 主文字墨色
  static const Color ink = Color(0xFF0A0A0A);

  /// 弱化文字
  static const Color muted = Color(0xFF6B6B6B);

  /// 主按钮近黑
  static const Color primary = Color(0xFF1D1F20);

  /// 唯一数据色（玫瑰木琥珀）—— 仅限数据元素，不得用于骨架
  static const Color dataHue = Color(0xFF8A5A2B);

  /// 调到位的绿
  static const Color positive = Color(0xFF2E7D32);

  /// 负向红
  static const Color negative = Color(0xFFC4242A);

  /// 正向药丸底色
  static const Color pillPositiveBg = Color(0xFFDCFAE5);

  /// 正向药丸墨色
  static const Color pillPositiveInk = Color(0xFF04250E);

  /// 负向药丸底色（偏差大）
  static const Color pillNegativeBg = Color(0xFFFFEDEA);

  /// 负向药丸墨色
  static const Color pillNegativeInk = Color(0xFF831C1E);
}

class GuitarBarTheme {
  GuitarBarTheme._();

  /// 角色字号（系统字体，Windows 上即 Segoe UI）：
  /// 页面标题 24/600 = titleLarge · 区块标题 16/500 = titleMedium ·
  /// KPI 数值 30/400 = displaySmall · 正文 16/400 = bodyMedium · 小字 12/400 = bodySmall。
  ///
  /// 页面任务只允许使用此处已定义的角色（titleLarge/titleMedium/displaySmall/
  /// bodyMedium/bodySmall）；需要新角色先在 _textTheme 落角色再使用，否则回退
  /// M3 默认（57px 巨字）且无 tabular figures。
  static const TextTheme _textTheme = TextTheme(
    displaySmall: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w400,
      color: GuitarBarColors.ink,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: GuitarBarColors.ink),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: GuitarBarColors.ink),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: GuitarBarColors.ink),
    bodyMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: GuitarBarColors.ink,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: GuitarBarColors.ink,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: GuitarBarColors.primary,
      onPrimary: Colors.white,
      secondary: GuitarBarColors.primary,
      onSecondary: Colors.white,
      surface: GuitarBarColors.surface,
      onSurface: GuitarBarColors.ink,
      error: GuitarBarColors.negative,
      // 中性容器角色补全：未覆写的容器角色会走 M3 种子基线紫色，这里全部指向
      // surface/border 中性色，堵住 SegmentedButton/FilledButton.tonal/ChoiceChip/
      // Card/AlertDialog/bottomSheet/TextField 描边成片漏紫。
      secondaryContainer: GuitarBarColors.activePill,
      onSecondaryContainer: GuitarBarColors.ink,
      surfaceContainerLowest: GuitarBarColors.surface,
      surfaceContainerLow: GuitarBarColors.surface,
      surfaceContainer: GuitarBarColors.surface,
      surfaceContainerHigh: GuitarBarColors.surface,
      surfaceContainerHighest: GuitarBarColors.border,
      outline: GuitarBarColors.controlBorder,
      outlineVariant: GuitarBarColors.border,
      // IconButton/ExpansionTile/DatePicker 等前景走 onSurfaceVariant，
      // 不补则回退 M3 基线微紫灰。
      onSurfaceVariant: GuitarBarColors.muted,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: GuitarBarColors.ground,
      textTheme: _textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: GuitarBarColors.ground,
        foregroundColor: GuitarBarColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 48,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: GuitarBarColors.ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: GuitarBarColors.ground,
        indicatorColor: GuitarBarColors.activePill,
        elevation: 0,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? GuitarBarColors.ink : GuitarBarColors.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: states.contains(WidgetState.selected) ? GuitarBarColors.ink : GuitarBarColors.muted,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: GuitarBarColors.border, thickness: 1, space: 1),
    );
  }
}
