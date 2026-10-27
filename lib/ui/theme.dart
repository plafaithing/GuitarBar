import 'package:flutter/material.dart';

/// GuitarBar 界面设计语言（achromatic-ledger 色彩账本风）。
///
/// 骨架无彩色：近黑主色、平面、静止零阴影；唯一的数据色 dataHue（玫瑰木琥珀）
/// 只允许出现在数据元素上（调音音名/音分、弦钮检测态、琴头插画），
/// 严禁用于按钮、导航、标签页等界面骨架。
///
/// 圆角只有两档：卡片 8、控件 6。字重预算 400/500/600（700 留给日后最重要的数字）。
/// 数字类文本一律 `FontFeature.tabularFigures()`（主题角色已内置，页面自绘
/// 数字也要显式应用该特性）。
///
/// 取色统一走 `context.palette.muted` 等（[GuitarBarPaletteContext]）：
/// 深浅两套色板经 ThemeExtension 随 themeMode 切换。不再提供静态色常量——
/// 静态浅色常量与主题色板并存必然漂移。与 BuildContext 无关的插画
/// （如琴头固定木色）直接使用字面色。
class GuitarBarPalette {
  const GuitarBarPalette({
    required this.ground,
    required this.surface,
    required this.activePill,
    required this.border,
    required this.rule,
    required this.controlBorder,
    required this.ink,
    required this.muted,
    required this.primary,
    required this.dataHue,
    required this.positive,
    required this.negative,
    required this.pillPositiveBg,
    required this.pillPositiveInk,
  });

  /// 画布底色（浅：云杉暖白 / 暗：暖黑）
  final Color ground;

  /// 卡片/面板表面
  final Color surface;

  /// 导航选中灰药丸
  final Color activePill;

  /// 分隔边框
  final Color border;

  /// 细分隔线（色调阶梯）
  final Color rule;

  /// 控件描边
  final Color controlBorder;

  /// 主文字墨色（暗色下反白）
  final Color ink;

  /// 弱化文字
  final Color muted;

  /// 主按钮近黑（暗色下反白）
  final Color primary;

  /// 唯一数据色（玫瑰木琥珀）—— 仅限数据元素，不得用于骨架
  final Color dataHue;

  /// 调到位的绿
  final Color positive;

  /// 负向红
  final Color negative;

  /// 正向药丸底色
  final Color pillPositiveBg;

  /// 正向药丸墨色
  final Color pillPositiveInk;

  /// 两套色板均为 const 单例，identity 比较即可区分（无需逐字段 ==）。
}

/// 浅色板（云杉暖白）
const GuitarBarPalette lightPalette = GuitarBarPalette(
  ground: Color(0xFFF7F5F1),
  surface: Color(0xFFFFFFFF),
  activePill: Color(0xFFECECEC),
  border: Color(0xFFE6E6E6),
  rule: Color(0xFFF0F0F0),
  controlBorder: Color(0xFFD4D4D4),
  ink: Color(0xFF0A0A0A),
  muted: Color(0xFF6B6B6B),
  primary: Color(0xFF1D1F20),
  dataHue: Color(0xFF8A5A2B),
  positive: Color(0xFF2E7D32),
  negative: Color(0xFFC4242A),
  pillPositiveBg: Color(0xFFDCFAE5),
  pillPositiveInk: Color(0xFF04250E),
);

/// 暗色板（暖黑，取自主题材质而非纯黑；琥珀提亮保暗底可读）
const GuitarBarPalette darkPalette = GuitarBarPalette(
  ground: Color(0xFF141311),
  surface: Color(0xFF201F1C),
  activePill: Color(0xFF35342F),
  border: Color(0xFF2E2D2A),
  rule: Color(0xFF232220),
  controlBorder: Color(0xFF454440),
  ink: Color(0xFFF5F2EC),
  muted: Color(0xFFA8A49B),
  primary: Color(0xFFF5F2EC),
  dataHue: Color(0xFFD19A63),
  positive: Color(0xFF3FC07A),
  negative: Color(0xFFE5566F),
  pillPositiveBg: Color(0xFF172A1D),
  pillPositiveInk: Color(0xFF3FC07A),
);

/// 把当前色板挂进主题（深浅随 themeMode 切换）。
/// ThemeExtension 的类型参数是自界的（`T extends ThemeExtension<T>`），
/// 因此这里包装 palette 而不是直接把 palette 作 extension。
class GuitarBarPaletteExtension
    extends ThemeExtension<GuitarBarPaletteExtension> {
  const GuitarBarPaletteExtension(this.palette);

  final GuitarBarPalette palette;

  // 色板不插值：主题切换是离散事件，直接按 t 中点换板。
  @override
  GuitarBarPaletteExtension lerp(
          covariant GuitarBarPaletteExtension? other, double t) =>
      other == null || t < 0.5 ? this : other;

  @override
  GuitarBarPaletteExtension copyWith({GuitarBarPaletteExtension? palette}) =>
      GuitarBarPaletteExtension(palette?.palette ?? this.palette);

  // palette 为 const 单例，identity 相等即足够。
  @override
  bool operator ==(Object other) =>
      other is GuitarBarPaletteExtension && other.palette == palette;

  @override
  int get hashCode => palette.hashCode;
}

extension GuitarBarPaletteContext on BuildContext {
  /// 当前主题色板（浅/暗随系统切换）。
  GuitarBarPalette get palette =>
      Theme.of(this).extension<GuitarBarPaletteExtension>()!.palette;
}

class GuitarBarTheme {
  GuitarBarTheme._();

  /// 角色字号（系统字体，Windows 上即 Segoe UI）：
  /// 页面标题 24/600 = titleLarge · 区块标题 16/500 = titleMedium ·
  /// KPI 数值 30/400 = displaySmall · 正文 16/400 = bodyMedium · 小字 12/400 = bodySmall。
  ///
  /// 页面任务只允许使用此处已定义的角色；需要新角色先在此落角色再使用，
  /// 否则回退 M3 默认（57px 巨字）且无 tabular figures。
  static TextTheme _textThemeFor(Color ink) => TextTheme(
        displaySmall: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w400,
          color: ink,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: ink),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: ink),
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: ink),
        bodyMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: ink,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: ink,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      );

  static ThemeData light() => _themeFor(lightPalette);

  static ThemeData dark() => _themeFor(darkPalette);

  static ThemeData _themeFor(GuitarBarPalette p) {
    final scheme = identical(p, darkPalette)
        ? ColorScheme.light(
            primary: p.primary,
            onPrimary: p.ground,
            secondary: p.primary,
            onSecondary: p.ground,
            surface: p.surface,
            onSurface: p.ink,
            error: p.negative,
            // 中性容器角色补全：未覆写的容器角色会走 M3 种子基线紫色，这里
            // 全部指向 surface/border 中性色，堵住 SegmentedButton/FilledButton
            // .tonal/ChoiceChip/Card/AlertDialog/bottomSheet/TextField 描边成片漏紫。
            secondaryContainer: p.activePill,
            onSecondaryContainer: p.ink,
            surfaceContainerLowest: p.surface,
            surfaceContainerLow: p.surface,
            surfaceContainer: p.surface,
            surfaceContainerHigh: p.surface,
            surfaceContainerHighest: p.border,
            outline: p.controlBorder,
            outlineVariant: p.border,
            onSurfaceVariant: p.muted,
          )
        : ColorScheme.dark(
            primary: p.primary,
            onPrimary: p.ground,
            secondary: p.primary,
            onSecondary: p.ground,
            surface: p.surface,
            onSurface: p.ink,
            error: p.negative,
            secondaryContainer: p.activePill,
            onSecondaryContainer: p.ink,
            surfaceContainerLowest: p.ground,
            surfaceContainerLow: p.surface,
            surfaceContainer: p.surface,
            surfaceContainerHigh: p.surface,
            surfaceContainerHighest: p.border,
            outline: p.controlBorder,
            outlineVariant: p.border,
            onSurfaceVariant: p.muted,
          );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.ground,
      textTheme: _textThemeFor(p.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: p.ground,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 48,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p.ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.ground,
        indicatorColor: p.activePill,
        elevation: 0,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? p.ink : p.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: states.contains(WidgetState.selected) ? p.ink : p.muted,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      extensions: [GuitarBarPaletteExtension(p)],
    );
  }
}
