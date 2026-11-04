import 'package:flutter/material.dart';

/// GuitarBar 界面设计语言（v2「aurora-dark」——2026-11-04 设计语言换代，
/// 参考 reactbits.dev；原 achromatic-ledger 骨架规则保留）。
///
/// 骨架无彩：近黑主色、平面；唯一的数据色 dataHue（玫瑰木琥珀）允许出现在
/// 数据元素**与光晕装饰**上（glowA/glowB 均为 dataHue 系派生，不引入新的
/// 彩色家族），严禁把其他彩色用于按钮、导航、标签页等界面骨架。
///
/// reactbits 式落地（全产品统一，单一风格语言）：
/// - 背景统一走 [GbarBackground]（ground 底 + dataHue 径向光晕 ×2），
///   页面 Scaffold 一律透明，光晕随主题明暗调整强度（暗更亮、浅更淡）
/// - 卡片/对话框/菜单圆角 12 + 细边框 + 微光阴影；控件（按钮/输入框/下拉）
///   圆角 10；AppBar 透明融入背景
/// - 字重预算 400/500/600（700 留给日后最重要的数字）。数字类文本一律
///   `FontFeature.tabularFigures()`（主题角色已内置，页面自绘数字也要
///   显式应用该特性）。
///
/// 取色统一走 `context.palette.muted` 等（[GuitarBarPaletteContext]）：
/// 深浅两套色板经 ThemeExtension 随 themeMode 切换。不再提供静态色常量。
/// 与 BuildContext 无关的插画（如琴头固定木色）直接使用字面色。
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
    required this.panel,
    required this.glowA,
    required this.glowB,
    required this.overlay,
  });

  /// 画布底色（浅：云杉暖白 / 暗：暖黑）
  final Color ground;

  /// 面板底色（比 ground 深一档：浅 EDEBE6 暖灰 / 暗 1C1B18 亮一档）
  final Color panel;

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

  /// 唯一数据色（玫瑰木琥珀）—— 仅限数据元素与光晕装饰，不得引入新彩色
  final Color dataHue;

  /// 调到位的绿
  final Color positive;

  /// 负向红
  final Color negative;

  /// 正向药丸底色
  final Color pillPositiveBg;

  /// 正向药丸墨色
  final Color pillPositiveInk;

  /// 主光晕色（dataHue 派生，自带 alpha）——GbarBackground 主光源
  final Color glowA;

  /// 次光晕色（冷调微光，对冲主光晕防大面积同色晕染）
  final Color glowB;

  /// 玻璃面板色（半透明 surface）：悬浮索引条/浮层等叠加在光晕上的元素
  final Color overlay;

  /// 两套色板均为 const 单例，identity 比较即可区分（无需逐字段 ==）。
}

/// 浅色板（云杉暖白；光晕淡——不干扰谱面阅读）
const GuitarBarPalette lightPalette = GuitarBarPalette(
  ground: Color(0xFFF7F5F1),
  panel: Color(0xFFEDEBE6),
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
  glowA: Color(0x1A8A5A2B), // dataHue @ ~10%
  glowB: Color(0x0F5A6B7A), // 冷蓝灰 @ ~6%
  overlay: Color(0xD9FFFFFF), // surface @ 85%
);

/// 暗色板（暖黑，取自主题材质而非纯黑；琥珀提亮保暗底可读；光晕更明显）
const GuitarBarPalette darkPalette = GuitarBarPalette(
  ground: Color(0xFF141311),
  panel: Color(0xFF1C1B18),
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
  glowA: Color(0x26D19A63), // dataHue @ ~15%
  glowB: Color(0x1A35506B), // 冷蓝 @ ~10%
  overlay: Color(0xD920201C), // surface @ 85%
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

/// 全局界面字体：微软雅黑。
///
/// 放在主题层统一生效（ThemeData.textTheme 应用一次，页面里内联的 TextStyle
/// 不指定 family 时会从 DefaultTextStyle 继承），这样不会出现「某页字对、
/// 另一页字不对」。系统没有该字体时按 [kUiFontFallback] 逐级回退：macOS 用
/// 苹方、iOS 用黑体，最后落到平台默认，不会出现方块字。
const String kUiFontFamily = 'Microsoft YaHei';
const List<String> kUiFontFallback = [
  'PingFang SC',
  'Hiragino Sans GB',
  'Heiti SC',
  'Noto Sans CJK SC',
  'sans-serif',
];

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
            // 全部指向中性色，堵住 FilledButton.tonal/ChoiceChip/Card/
            // AlertDialog/bottomSheet/TextField 描边成片漏紫。
            // 2026-11-04 走查：surfaceContainer 系从 surface(白) 改 panel
            //（暖灰）——DropdownButton 菜单等 M3 浮层底色统一页面暖调，
            // 不可白底。
            secondaryContainer: p.panel,
            onSecondaryContainer: p.ink,
            surfaceContainerLowest: p.ground,
            surfaceContainerLow: p.panel,
            surfaceContainer: p.panel,
            surfaceContainerHigh: p.panel,
            surfaceContainerHighest: p.panel,
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
            secondaryContainer: p.panel,
            onSecondaryContainer: p.ink,
            surfaceContainerLowest: p.ground,
            surfaceContainerLow: p.panel,
            surfaceContainer: p.panel,
            surfaceContainerHigh: p.panel,
            surfaceContainerHighest: p.panel,
            outline: p.controlBorder,
            outlineVariant: p.border,
            onSurfaceVariant: p.muted,
          );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.ground,
      // 全局字体：所有角色统一到微软雅黑（见 kUiFontFamily）。
      textTheme: _textThemeFor(p.ink)
          .apply(fontFamily: kUiFontFamily, fontFamilyFallback: kUiFontFallback),
      // AppBar 底色恢复（2026-11-04 走查：透明 AppBar + 透明 Scaffold
      // 会露出窗口原生黑底成"大黑框"——AppBar 区域不在 GbarBackground
      // 光晕层内，只能实体色；光晕仍在各页 body 内可见）。
      appBarTheme: AppBarTheme(
        backgroundColor: p.ground,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 48,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p.ink),
      ),
      // v2 统一卡片/对话框：圆角 12 + surface 底 + 细边框 + 微光阴影
      //（reactbits 玻璃卡片语言；阴影极淡只作层次提示）。
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: p.border)),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        // 选项框/对话框与下拉浮层统一 panel 暖灰（2026-11-04 走查：白底
        // 浮层与页面风格不符）。
        backgroundColor: p.panel,
        elevation: 8,
        shadowColor: p.dataHue.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: p.border)),
        titleTextStyle: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w600, color: p.ink),
      ),
      // SegmentedButton（吉他模式/输入浏览/主题三选）统一：底 panel、
      // 选中 activePill 药丸、圆角 10——不落 M3 白底默认。
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? p.activePill
                  : p.panel),
          side: WidgetStatePropertyAll(BorderSide(color: p.controlBorder)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10))),
        ),
      ),
      // v2 统一按钮圆角 10（控件档）；FilledButton 保持主色实底。
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              side: BorderSide(color: p.controlBorder))),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)))),
      // v2 统一输入框：填充 panel、圆角 10、聚焦描边 dataHue（唯一数据色
      // 作为焦点信号，替代 M3 默认蓝紫）。
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.panel,
        isDense: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: p.controlBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: p.controlBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: p.dataHue, width: 1.4)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        // 实体底色（2026-11-04 走查：透明会在窄屏露出窗口原生黑底，
        // 与 AppBar 同因——底部栏也不在光晕层内）。
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
      // 菜单浮层样式：M3 DropdownMenu（dropdownMenuTheme）与 MenuAnchor
      //（menuTheme，曲谱库导入菜单）共用 [_menuStyle] 一份视觉；传统
      // DropdownButton 的菜单不受这两个主题控制，由组件自身
      // dropdownColor/elevation/borderRadius 落地同款视觉——见节拍器页。
      // 浮层允许轻阴影（设计系统菜单浮层例外）。
      menuTheme: MenuThemeData(style: _menuStyle(p)),
      dropdownMenuTheme: DropdownMenuThemeData(menuStyle: _menuStyle(p)),
      // 全 app 开关统一：选中 = positive 绿轨 + 白 thumb（调音器「自动」
      // 与个人中心「调试模式」同款；未选轨道用 controlBorder 中性）。
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? p.positive
                : p.controlBorder),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      extensions: [GuitarBarPaletteExtension(p)],
    );
  }

  /// 菜单浮层共享样式：DropdownMenu 与 MenuAnchor（MenuItemButton 菜单）
  /// 同一份视觉，收敛一处防两份主题复制粘贴漂移。v2：圆角 12 + dataHue
  /// 微光阴影（玻璃浮层）；底色 panel 暖灰（2026-11-04 走查：不可白底）。
  static MenuStyle _menuStyle(GuitarBarPalette p) => MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.panel),
        elevation: const WidgetStatePropertyAll(4),
        shadowColor: WidgetStatePropertyAll(p.dataHue.withValues(alpha: 0.15)),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: p.border))),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
      );
}
