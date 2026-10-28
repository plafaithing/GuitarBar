# GuitarBar 设计账本

> 记录设计语言的决策、例外与战役修复。**新代码必须遵守；"有意的不对称/偏离"勿被后续"修正"。**
> 最后更新：2026-10-28（一期功能收官）

## 设计语言：achromatic-ledger（无彩账本）

- 框架无彩：chrome 全灰阶，**颜色只上数据**（<1% 像素预算）
- 数据色唯一：dataHue 琥珀棕 `#8A5A2B`（取自木吉他材料色）；深色板提亮 `#D19A63`
- 状态色：positive 绿（调到位/开关选中）、negative 红（错误）
- 表面分离靠色阶或 1px 线，**静止零阴影**；浮层（菜单/对话框）例外允许轻阴影
- 圆角两档：卡片 8 / 控件 6（对话框浮层 16）
- 字号五档：24 页标题 / 16 节标题 / 30 KPI / 14 正文 / 12 小字；数字一律 tabular figures
- 深色板：暖黑（非纯黑非藏青）`#141311` 系，ink 反白，dataHue 提亮 `#D19A63`

## 主题架构（Task 12/16 深色模式轮确立）

- `GuitarBarPalette`：14+1 令牌（含 panel 深一档面板色）的 ThemeExtension，浅/暗两 const 单例
- 取色唯一途径：`context.palette.*`——**禁止 Colors.\* 硬编码于新增逻辑**（Colors.white 音点字为计划保留项）
- **组件样式一律定义在主题层**（SwitchThemeData/MenuStyle/ColorScheme 映射），页面零覆盖——换主题或调风格只动 theme.dart（用户确立的规则）
- 琴头插画 = 字面木色（不经 palette，插画不受主题影响——有意决策）
- 主题模式：`ThemeMode.system` 随系统；手动切换器留 Task 17+（main.dart 已注释标记）

## 有意的不对称与偏离（勿"修正"）

| 项 | 决策 |
|---|---|
| 底栏（微信式：字形填充+ink）vs 侧栏（药丸+恒 muted） | 有意的强调不对称 |
| 隐藏页 opacity 0 已移出语义树（SDK 实证） | 无需 ExcludeSemantics |
| 调音器音名 52px/600 | 签名元素有意超出 48px 房规 |
| 唱名 Do 基（平行大调回退音名） | scale.dart 注释预留的决策点 |
| Colors.white 音点字 | 计划保留项（彩点上的内容字） |
| 开始练习按钮 positive 绿 | accent 上主行动（GuitarTuna 同款） |

## 战役记录（真金白银换来的教训）

### 1. SST 阵列 44100/1 配置挂死音频驱动线程
- 症状：进程僵尸化（threads=1）无法 taskkill/Stop-Process，exe 锁死阻断构建
- 修复：采集格式轮换 **48k 优先**规避；轮换兜底仍有 44100（仅 48k 系全败才触达）
- 波及：rebuild 必须先清僵尸（音频服务停启解锁驱动调用）或重启

### 2. record 包 chunk 的 offsetInBytes 奇偏移 → Int16List.view RangeError
- 症状：chunks 涨、hex 有数据、rms/窗/音高流全死（异常在 view 创建即抛，Error 子类静默飞走）
- 修复：`ByteData.sublistView` + `getInt16` 逐样本解码（对任意偏移安全）
- 教训：Error 子类不进 Exception catch——回调级裸 try/catch + cberr 上屏是抓这类问题的仪器

### 3. wakelock 平台调用挂起 → 计时冻结 + 落库阻塞
- 修复：wakelock 全部 fire-and-forget（unawaited + catchError），与计时/落库完全解耦

### 4. 音频增强（SST DSP）滤吉他
- 症状：人声能识别、吉他被滤（人声优化 DSP 压制持续音）
- 修复：系统设置关音频增强（用户侧操作）——**设备重新枚举可能重置该设置**，排障时先查

### 5. M3 禁用态 38% 淡出不可覆盖
- 症状：运行中下拉数值几乎看不见（disabledHint 只救 value==null 场景）
- 修复：下拉恒启用态（全色）+ AbsorbPointer 按运行中吸收点击 + onChanged 运行中守卫（纵深防御）

## 组件风格规则（用户确立）

- **开关/按钮/面板样式一律定义在主题层**，页面零覆盖（SwitchThemeData/MenuStyle/ColorScheme）
- 开关：选中 positive 绿轨 + 白 thumb（全 app 统一）
- 面板填充：**palette.panel（比 ground 深一档）**——用户指定"面板要比背景深一点作为区分"
- 工具箱：独立长条按钮（非整块面板），间距 12
- 空数据热力格格：palette.surface 填充 + 1px border（可见化）

## 遗留决策点（已记录，未到期）

- 唱名关系大调（La 基）方案：scale.dart 注释预留
- 音点白字深色对比度：与 palette 收编清单一并处理
- 热力图月份刻度/图例：用户已确认 90 天滚动窗，图例待打磨
- 侧栏底部计时器预留位（Task 17 填充）
