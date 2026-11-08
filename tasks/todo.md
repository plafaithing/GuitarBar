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

## 二轮走查三件（2026-11-04 用户指令：2/5/6）

1. [x] tab_view 614 处 U+FFFD 乱码注释：Dart 脚本截尾 130 行，0 残留（脚本用完即删）
2. [x] 文件选择器记住上次导入目录：settings lastImportDir + openFiles/getDirectoryPath initialDirectory
3. [x] Bend/Whammy 解析+播放（gp8 补完）：IR BendPointIr/whammy、gpif 解析（x/60、y/4 半音；双 0 占位过滤）、播放 PitchShift ramp 铺满时值。**样本缺口**：曲库三 gpx+三 gp5 无 Bend、Like A Star 1257 处 Whammy 全 0.0 占位——合成 fixture 验证，系数待真实谱校准
- 启动 5s 卡顿：用户反馈未再现，挂起
- 274 测试全绿

## gp8 三链逆向对照报告（2026-11-07，AMAudio/GPCore 证据 + 全要素样本扫描）

### 链1 解析（gp8: BCFZ/zip → gpif → libxml2 → Document）
样本全要素扫描（三谱）结果 vs 我们 gtp_parser：
- ✅ 已覆盖：Bars/Voices/Beats/Notes、Automation Tempo（首段）、Capo（FreeText 兜底）、
  全部技法标注族（含 Brush/PickStroke 的 Direction 子元素——Like A Star 397 个
  `<Direction>` 命中即此，非跳转记号误报）
- ⏳ **Fermata 延长记号**：月下之恋 **8 处真值**——gp8 播放延长该拍（AMAudio
  TempoManager 有 Fermata 通道）。未解析未播放。**下一个实现项**
- ⏳ **DS/Coda 跳转**：Bluebird Coda=2；expandMeasures 只有 Repeat/endings，
  Segno/DS al Coda 跳转未实现（跳转记号结构待精确采样）
- ⏳ 曲中变速：三谱 TempoAuto 均 1 段（无样本）；_readTempo 只取首段 BPM；
  gp8 AMAudio TempoManager.tempo(tick) 逐 tick 支持多段
- ⏳ Ottavia 8va/歌词/和弦图：三谱均 0，待真实谱
- GPCore 无 "MixTableChange" 字符串（gp8 内部不用该词处理音量变化）

### 链2 播放（gp8: TempoManager ticks + AudioTrack 预渲染 + RubberBand 变速 + RtAudio/WASAPI）
AMAudio.dll 证据（ev_fdf2ea0d）：
- TempoManager：buildTempoLines/buildTickSlices/makeTicksAtTempo/tempo(tick)/
  Fermata 通道/Min-MaxTempo 钳制——**tick 切片架构**
- **ProgressiveTempo**：渐变变速（startRatio→endRatio+step+repeatCount——
  accelerando/ritardando 自动化）
- **变速 = RubberBand time-stretch 保音调**（RubberBandAudioTrackController；
  rubberband.dll setTimeRatio/setPitchScale）——我们采样变速 rate 缩放=变调
- RtAudio WASAPI 输出；SharedTemporaryFile 预渲染缓冲（RSE 合成需要，我们
  采样级实时调度无劣势）

### 链3 渲染（gp8: GPCore view 层 + AMPainting）
已逆向对齐（弧线几何/Bravura 字体/图元）；剩余显示缺口同解析（Ottavia/歌词/和弦图）。

### 本应用优化清单（按价值排序）
1. **Fermata**：解析 gpif Fermata + 播放延长 + 显示——月下之恋 8 处真值可对账
2. **变速保调**：采样路径 rate 变速加 PitchShift 反向补偿（近似 gp8 RubberBand）
3. **DS/Segno/Coda 跳转**：expandMeasures 补跳转语义（结构采样后）
4. **曲中变速**：事件轴按 tick 分段 tempo（等真实多段样本）
5. Ottavia/歌词/和弦图显示（等真实谱）
