# 曲谱标注补齐（GP8 逆向侦察后实施）

走查背景：用户截图发现"12 泛音连 2 品实音"两音悬空——击勾弦/连音线弧线系统缺失。
GP8 GPCore.dll strings 侦察确认 gpif 属性名全集（含 LegatoOrigin/Trill），数据语义自明。

## 清单

1. [x] 探针枚举真实 gpif 标注（Hopo 27/Tie 49/LetRing 106/PalmMute 15/Tap 37/Vibrato 1/AntiAccent 3）
2. [x] NoteIr 扩展：tieStart/tieEnd/hopoStart/hopoEnd/legatoStart/legatoEnd/letRing/palmMute/vibrato/tap/ghost/slide（条件序列化，旧 irJson 兼容）
3. [x] gtp_parser 解析：Tie 双端入列表、Hopo、LetRing/Vibrato/AntiAccent（Note 子元素）、PalmMuted/Tapped/LeftHandTapped、Slide Flags 分型（0x01 shift/0x02 legato）
4. [x] 发声层跳过 tieEnd（sample_player + score_renderer）
5. [x] TabView 绘制：tie/hopo/legato 弧线 + H/P 判向字母、shift 箭头、L.R.（同弦段）/P.M.（连续段）行底虚线、vibrato 波浪、ghost 括号、tap 字母；rowGap 26→32 让位行底标注区
6. [x] 测试：tie 契约更新（729→770 全引用入列表）、新标注解析 fixture、全标注渲染冒烟；真实文件对账 hopo 35/35、letRing 606、tie 40/41
7. [x] 删探针、246 全绿、提交

## Review
- GP8 深度逆向边界：GPCore.dll strings 侦察全命中（含 LegatoOrigin/Trill），数据语义层确认无遗漏；渲染几何参数未反汇编（无 Ghidra），画法按 GP 惯例实现，待用户 GP8 对照走查校准
- technique 参数改可选（新标注字段全可选，required 无理据）；gpx 通道不再写 h/p/s 字母（弧线表达），AI 通道 technique 不受影响
- tie 缺口：月下の恋 40 origin vs 41 dest（跨引用链首缺失 1 处），该弧线不画仅显数字，可接受

## GP8 渲染逆向进行中（Ghidra headless，2026-11-01）
- 工具链：Ghidra 12.1.2 装于 D:\software\ghidra_12.1.2_PUBLIC，工程 D:\ghidra_projects\{gpcore,painting}
- GPCore.dll（11MB）已全量分析；**带完整导出符号**（gp::core::view::* 类名/源码路径全可见）
- 架构判定：GPCore = 布局数据层（view protobuf：SlurView/HarmonicView/HoPoSlurView/NoteSlurView/BeatSlurView/ErrorSlurView/TabOctavadoHarmonicView），AMPainting.dll = 绘制执行层（图元协议 am.painting.protobuf.{Point,Line,Slur,Parenthesis,FormattedText,...}）
- 击勾弦弧线 = HoPoSlurView（继承 NoteSlurView→SlurViewBase）；幽灵音括号有专用图元 Parenthesis
- ✅ 弧线模型全解并转写（e630a91）：三次贝塞尔+内缩+弧高系数 0.36/0.426+避让算法（避让未转写，我方弧顶浅不压字）
- ✅ 其余标注逆向结论（2026-11-01 二轮）：
  - L.R./P.M. 确为虚线（letRingLineDashed/palmMuteLineDashed 布尔 getter）——实现已符合
  - shift slide：数字上方斜线+箭头（slideYIntercept/slideHeight/slideThickness 参数族）——已改 y-10
  - vibrato：SMuFL Bravura wiggle 尖峰锯齿（峰高 0.25×弦距、周期 0.5×弦距、2.5 周期）——已改
  - 线宽 tabSlurThickness×scale1.625≈1px——1.2→1.0
  - 幽灵音括号=专用图元 Parenthesis+parenthesisMargin——"(3)" 文字等效（记录在案）
  - 度量表常量（tabSlurHeight/Thickness 具体值）= SmuflFont 运行时从 GPBravura 字体解析，二进制无静态值（setFontName→SmuflFont 构造确证）——到此为止，属视觉微调项
- 反编译产出：D:\ghidra_projects\decomp_out、decomp_slur、decomp_paint（脚本 D:\ghidra_projects\scripts，保留可续挖）

## 曲谱库三件套（2026-11-03 用户需求）

1. [x] 批量导入：importFiles（score_repository）+ openFiles 多选分流 + 进度/汇总 SnackBar
2. [x] 实时搜索 + 类型筛选（GTP/PDF/图片）+ 一键清空（scores_page）
3. [x] 链接备注：Scores.noteUrl 列（schema v3，v2→v3 addColumn 互斥分支）+ 详情页 AppBar 右上角编辑/打开按钮 + url_launcher
4. [x] analyze 0 issue + 262 测试全绿（修复迁移测试 duplicate column）
5. [ ] dsh 交叉复测（后台运行中）
6. [ ] 用户验收后决定提交/推送

## 曲谱库二轮走查（2026-11-04 用户反馈）

1. [x] 删 GTP 行「打开原谱」（与点行同路径冗余）
2. [x] 搜索框最左侧类型下拉（圆角填充样式，默认全部）
3. [x] 首字母分组排序 + 右侧字母索引条（iPhone 通讯录式；中文拼音 lpinyin；同组英文优先）
4. [x] 链接点击无反应：launchUrl 改全捕获（Error 子类不再静默）——待用户重测显形真实错误
5. [x] PDF 渲染 Isolate 化（前一轮"点击导入卡死"根因，已完成）
6. [ ] dsh 交叉复测（后台中）→ 重建 exe → 用户验收
- UI 重设计解读：本轮只做曲谱库页视觉（控件圆角/分组头/索引条），全局主题未动；用户要更激进 reactbits 风格再扩
