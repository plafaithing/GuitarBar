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
- 待办：painting 分析完成后反编译 Slur 图元绘制函数 → 抠弧线贝塞尔几何/H/P 字母偏移/L.R.·P.M. 虚线 y/波形参数 → 校准 TabView _paintMarks
- 反编译产出：D:\ghidra_projects\decomp_out（锚点法，部分命中音频效果链为噪声）、decomp_slur（符号法）
