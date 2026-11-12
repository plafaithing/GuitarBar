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
- ✅ **Fermata 延长记号**（2026-11-07 已实现）：月下之恋 4 处真值（前值 8 为
  探针正则把容器误报）——解析（MasterBar Fermatas，分数拍位 0/1、2/1…）
  + 播放顺延（Length 0.46 拍，事件轴顺延实现）+ 合成 fixture 测试；
  显示弧线符号待画（渲染自检轮）
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
1. **Fermata**：解析 gpif Fermata + 播放延长 + 显示——月下之恋 4 处真值已对账（解析 4/4）
2. **变速保调**：采样路径 rate 变速加 PitchShift 反向补偿（近似 gp8 RubberBand）
3. **DS/Segno/Coda 跳转**：expandMeasures 补跳转语义（结构采样后）
4. **曲中变速**：事件轴按 tick 分段 tempo（等真实多段样本）
5. Ottavia/歌词/和弦图显示（等真实谱）

## 全量解析自测（2026-11-09，D:\Guitar 7 份文件）

- 6 份 gpx/gp5 **解析全过零炸点**，tie 配对全健康（Bluebird 851 规模最大、
  unmatched=0）；通用能力（Fermata/泛音/tap/回收站）在 6 文件验证通过
- fermata 分布：月下之恋 4 处（独有）；tap：Like A Star 186 + 月下之恋 2；
  泛音：Like A Star 209 + Bluebird 23 + 月下之恋 3；bend 全部 0（无样本）
- ⏳ **GP4（.gp）未支持**：Distance.gp 抛"GP4 未支持"——PyGuitarPro 有
  gp4 移植路径，中等工作量，待用户排期

## 批量样本扫描（2026-11-09，139 份指弹独奏谱）

- ✅ 55 份解析全过（48 gp5 + 6 gpx + 1 Distance.gp——zip 容器按魔数路由，
  gp8 保存的 .gp 已支持）；要素覆盖 tap 188 / 泛音 238 / Fermata 4，零炸点
- ⏳ **老格式缺口**：35 份 .gtp（GP1.04/2.21/4.06）+ 41 .gp4 + 15 .GP3 =
  谱集 65%——PyGuitarPro 支持全系列，扩 gp3/gp4 解析为中大型轮次，待排期
- 解析路由已改**魔数判定**（PK=zip / BCFZ=GP6 / 其他=gp5 二进制），不再按
  扩展名误判（Distance.gp 实为 gp8 zip 容器）

## 折行规则收敛（2026-11-10，用户三轮回馈）

- 最终规则：**简化三档**——音列 >12 → 2/行、>8 → 3/行、≤8 → 6/行；
  保底 2（超密小节如 Like A Star 后半 55-67 音列不再降到 1/行——
  宽度校验删掉，碎行根因）；密度档四档+宽度校验叠加产生过多 3-5 碎行
- **窗口比例定案：iPad Pro 11 寸竖屏 834×1194**（用户定标准），
  min 700×900——宽窄布局阈值 root.dart 900 需同步复核（竖屏恒窄布局）
- 排版宽 1300 上限居中保留（横向拉宽时谱面仍居中不无限拉行）

## GP5 pickup 小节拍号根因（2026-11-10，用户"gp5 识别完全错误"定案）

- **根因**：Flower-标调.gp5 首小节是 **1/4 拍号（pickup 前奏）**——我们按全局
  4/4 处理，首小节两音音位/时轴全部错位，连带后续小节在 gp8 对照中"错位"
- 三重验证：PyGuitarPro 原库输出逐音一致（弦/品/拍/时值全对）+ 像素级
  gp8 截图对照（bar2/bar3 逐音吻合，bar1 差异即 pickup）+ 原库 m0
  timeSignature=1/4 实锤
- 修复：MeasureIr.timeSignature（小节级，null 继承全曲；条件序列化）；
  gp5 解析逐 header 填入；全局拍号取首个 ≥4 拍小节（pickup 不代表全曲）；
  TabLayout.beatsOfBar（noteX 按小节拍数均分）+ 播放层 orderStarts 逐
  小节累计（sample_player/score_renderer/fermata 顺延全改）
- 该能力通用（任何带 pickup/变拍号的 gp5/gpx 生效）

## 渲染"打开只有一行"根因（2026-11-10，老 bug 定案）

- **根因**：`_paintMarks` 两处 `x1.clamp(f.x + 8, endX)`——行末音 f.x+8 超过
  行右缘时 clamp(min>max) 抛 ArgumentError，CustomPaint 吞异常 → row1 起
  全部不画（谱面"只显示第一行+下方空白+时长 0.0s"同源；窗口拉宽 endX 变大
  不抛 → "横向拉宽才显示曲谱"老 bug 同根因）
- 修复：保序 clamp（先 `min(f.x+8, endX)` 再夹）；golden 探针验证多行恢复
- 调试路径可复用：widget 测试 + golden 截图 → OCR/像素分析 → paint 异常日志

## 折行/吞音规则最终定案（2026-11-10 三轮 + 11-11 两轮收敛，**取代上方"简化三档"节**）

- **每行小节数 = 五档密度 ∩ 宽度校验**（按行内最挤小节的音列数）：
  五档 >32→2 / >20→3 / >14→4 / >10→5 / ≤10→6；
  宽度校验 = 行均分宽（扣 notePad 净空）下音距 ≥17px（两位数字实际宽+1），
  不足自动降档；保底 2/行（超密小节靠 2/行下 ~600px/小节行宽消化）
- 防吞音几何：同弦相邻错开趟 12→18px、防重叠 16→18px（两位数字 16px 宽）
- Distance 尾部 2 小节/行属正常（中段 20-25 音列是 17px 音距物理下限）
- 演进史（防重蹈）：三档删宽度校验 → 吞音（6/行 9 音列 12px 音距叠）→
  恢复校验 13px → 11-11 提 17px（13px 是中心距，两位数字边缘仍叠 3px）

## 播放实时变速实现（2026-11-10/11，用户 11-11 确认"变速没问题"）

- 采样路径：soloud `playScheduled` 的 `scale` = 移调 × _rate
  （**11-07"采样调度天然保调"复核结论是错的，已注释更正**——scale 从未
  传过变速率，0.5/0.25x "没变化"的根因）；谱面秒轴统一
  （_positionSeconds = 引擎流逝 ÷ rate；duration/seek/_t0 重锚全轴一致，
  防"变速瞬间 pos>duration 误判曲终"）；变速轴测试用例入 sample_player_test
- KS 降级路径：声部级 `setRelativePlaySpeed` 实时变速（原实现 stop→重渲染
  0.3-1s→start→seek 轴错位 = 用户看到的"停了从头播"）；未播放时只记速率
- 变速自然变调（gp8 采样变速同此行为），用户已接受
- 速度档 0.25x~2.0x 八档

## 旧会话交接（2026-11-11，会话 3c213ca7 上下文爆炸终结）

旧会话 11:48 死因：截图反复 Read 进主会话 + 88MB 转录 → 自动 compact 失败
（"summarization produced empty response"）。本会话（11-11 晚）已提取转录
纯文本完成交接。**当前一切改动未提交**（见下）。

### 未处理完的三个用户诉求（11-11 11:08-11:12 最后输入，优先级即此序）

1. [ ] **调音器布局**：打开应用后"吉他下方至设备栏中间空白很多"→ 放大
   音准方块区、吉他下移填充空白（旧会话刚 grep headHeight/Stack 即断线，
   未动手；lib/ui/tuner 相关文件 11-05 已提交版为基底）
2. [ ] **连音标注回退**：11-11 把 H/P 判向字母上移（y-10→y-19）后用户反馈
   "连音重叠部分出现回退情况，修改劣化"→ 回退该改动（回到 y-10）或重排
3. [ ] **播放器底部色块**：用户明确"播放器样式不能变，回退"——回退 11-11
   把 PlayBar 卡改不透明 surface+去阴影的改动；真正要去除的是**播放器后方
   一个连接到应用底部的圆矩形色块，颜色比曲谱背景深一点**。前两轮修复
   （bottomSheet Material(transparent)、PlayBar 卡片不透明化）都没找对
   目标。排查方向：score_detail_page Scaffold bottomSheet 槽下延至窗口底
   的区域/底部导航背景/装饰容器（像素分析定过位：浅色主题下灰
   227-238 横带）

### 提交前清理（用户验收后）

- test/failures/（golden 调试 diff 图）删除；test/ir_with_run.dart（共享
  测试 IR，tab_layout_test/tab_view_hit_test 已共用）与 test/fermata_test.dart
  （正式测试）保留
- 未提交跨度 = **11-07 Fermata 起全部工作**（HEAD grep fermata=0 实锤）：
  Fermata 解析/播放、139 份样本扫描魔数路由、clamp 崩溃修复、折行五档、
  pickup 拍号、实时变速、PlayBar 外观试验——diff 20 文件 +732/-251，
  11-11 晚本会话已复核 280 测试全绿（1 skip 环境相关）
- **未经用户明示不 commit 不 push**（教训 12）

### 本会话纪律（旧会话死因对策）

- 截图一律 zai `analyze_image`/`extract_text_from_screenshot` 或子代理，
  **禁止 Read 图片进主会话**；走查截图在 D:\workplace\code\test\ 按时间戳
- 转录提取脚本已备：C:\Users\plafa\AppData\Local\Temp\gb_session_extract.py
  （输出同目录 gb_session_3c213ca7.txt，按"日期边界"行号跳读）

## 连音劣化修复（2026-11-11 下午，进行中——会话重启交接点）

用户两张截图：141615_586 = **GP8 参照拼图**（左栏 gp8 六线谱 + 右栏总谱，
用户红块圈出 gp8 的 H 字母）、141640_527 = 我方渲染。指令"修改时看 gp8
的逻辑"。**三病灶**（子代理像素测量 + REA 逆向确认）：

1. [x] **数字"5/7"叠印 5px（最严重）**：同弦防重叠趟逆序守卫漏洞——
   错开趟把前音推过后面音的 noteX 后 `fl.x >= prev` 跳过推移。已修：
   统一为同弦音流 x 单调递增（`fl.x < prev + 18` 一律推到 `prev+18`），
   280 全绿（1 skip 环境相关）
2. [x] **弧线端点埋进数字字形**：按 gp8 实测定案（img1 左栏同刻度 +
   makeSlur 逆向）——端点改在弦线下方 0.27×弦距（gp8"端点微下探到
   线下 ~5.5px"），控制点高 0.45×弦距保持弧顶在线上 ~5.4px（=gp8 实测
   拱顶 5.5px）；弧从数字下缘出入不再穿字形上半。makeSlur 的障碍盒
   抬升避让在本布局（弦距 20 固定、数字带 ±6、弧顶 -5.4）下几何不可能
   触发，未移植（注释记档）。analyze 0 issue + 280 全绿
3. [x] **H/P 字母**：fs 9→7（gp8 字母明显小于数字）+ 垂直 y-19→**y-17**
   （golden 探针实锤：同拍相邻弦都有 hopo 时上弦弧顶 -22~-24 正好穿过
   y-19 字母带 2-4px，下移后净空 ≥2px）+ **水平避让**（数字盒/AH 盒/
   小节竖线 ±5、行首末保护、搜索限弧跨 ±2px 内，中点优先 3px 步进 10 档，
   全占回退中点）——解决 2-6 弦字母落进上弦数字带的几何必撞

**验证链（2026-11-11 晚）**：
- widget golden 探针（45 弧/42 字母密集场景）：子代理逐像素目检——四项
  目标全部达成：弧线端点 dip=10.8px 物理值与公式吻合、拱顶线上 2-4px、
  无一例弧穿数字上半；字母 fs7=数字一半、y-17 实测吻合；水平避让全部
  落空档（最小净距 25px，两处贴边 5px 为回退策略）；墨迹零重叠
- 字母下移 y-17 后复验：字母检出 6→41（与上弦弧顶墨迹脱连的直接证据），
  交集仍 0
- **dsh 一轮 FAIL → 整改（P0/P1 全单）**：
  - P0 同拍对齐破坏（单音推移让同拍异弦 x 分叉）→ 拥挤趟改**按组推移**
    （mIdx@beat 分组整组同移、组内各弦 lastX 同步）
  - P0 repeatEnd 行末越界（measureX(mIdx0+1) 跨行取到下 行 col0 → 组
    左移出屏；11-09 起的老 bug）→ sameRowNext 判定 + 行末用
    leftPad+ΣmeasureWidthAt（与行末竖线同算式）
  - P1 宽屏坐标错位（_paintMarks 收 size.width，noteX/measureX 依赖
    maxWidth）→ 改传 layoutWidth
  - P1 弧顶公式错误（拱顶=dip−0.75h，0.45 时只有 -1.35px）→ h=0.73，
    拱顶 -5.55px=gp8 实测 -5.5
  - P1 弧线盖字 → **绘制顺序翻转**：_paintMarks 提到文字层前（弧在
    数字底下，gp8 AMPainting 同序）
  - P2 barXs 逐弧重建 → 提到 _paintMarks 顶部每行一次
- v2 golden PIL 复验：拱顶 -5.8~-6.2 逻辑px（=gp8 -5.5 ✓）、44 字母分离、
  交集 0；analyze 0 issue + 280 全绿
- **dsh 二轮 + 子代理 v2 目检收尾**：
  - 条5 翻转 PASS；tap 弧 FAIL（y-14~-19 画字上、会盖上弦数字下半 +
    flowByTime 排序非稳定）→ tap 弧并入标注层（文字底下）+ 排序加
    弦号/x 决胜
  - 宽屏三处（pre-existing 但真实）：build sizeFor/_follow locate/_hitTest
    调用与弦线终点全部对齐 effectiveWidth/layoutWidth
  - prevEnd 跨行守卫（上行末 repeatEnd 不推本行首组）；弧块注释 0.45→0.73
  - 子代理 v2 目检三点全 PASS：拱顶 11.5 物理px（=5.75 逻辑）、弧在数字
    边缘干净截断、字母 y-17 与上弦数字/弧顶零重叠
  - dsh 沙箱未能跑测试（ProcessException），静态推演为主；280 全绿由本
    会话实跑背书
## LAS"音位置错误"根因与修复（2026-11-12 晨，用户截图 092211）

- **实锤**：真谱探针（103 小节全量模拟排布管线）——275 音越出本小节
  右线、最大 353px、394 次推移。根因两层：①拥挤阈 18px 比折行宽度
  校验保的 17px 音距大 1px → 全行密集音列系统性 +1 级联；②dup 尾部
  /组级联无小节边界 → 越线 + 跨小节传染（lastX 跨小节持续）
- **修复**：拥挤阈 18→17（与宽度校验对齐，17px 下 16px 字形有 1px
  净空，校验过的音列零推移）；拥挤组推移与 dup 错开趟均**钳制在本
  小节右线内 12px**（小节归属铁律绝对优先；12+notePad10=22px 跨小节
  间隙阻断传染；极端 dup 尾贴边接受，根治待排布升级）
- **复验**：探针越界 275→**0**、推移 394→229（全钳小节内）；
  analyze 0 issue + 280 全绿；探针已删
- [ ] dsh 三轮复核（后台）→ 构建 → 用户验收
- ⏳ 教训：dsh 二轮预警"累计越界"时我评估为"与旧行为相当"放行——
  **预警过但量级没量化，真谱探针当天就引爆**。规则：布局类改动必须
  跑真谱（LAS/Flower）探针量化，不能只看合成 fixture

## LAS 三问题 + 全库自检（2026-11-12 上午，用户三点反馈全解）

1. **"依旧有重叠"** → 三层根因连环曝光，全修：
   a. **maxBarInCur 回写覆盖**（折行锁死真凶）：flush 清零后被
      `maxBarInCur = maxAfter`（flush 前旧值）回写 → m77 的 56 音把
      后续 25 个稀疏小节永久锁死 2/行。改 post-flush 语义
   b. **拥挤阈超需求**：`9+半宽+半宽` 对一位数对算 17px，但一位数墨宽
      8px 实需 9px——超需求推挤 → 链条撞界。改 `1+前墨半+本墨半`
      （一位对 9、两位对 17、幽灵对 25，与布局层按列基准一致）
   c. **无空间不推**：部分推挤会把多组堆到右界同点（Bluebird m63
      三组 758.0 同点）——空间不足整组保持原位（自然列距分散）
   d. **处理序=文件序引发视觉倒序**（b3.75 画在 b3.5 左边）：多声部
      m.notes 文件序≠拍序 → 组处理改**小节+拍时间序**
2. **m22 波浪线在音下方** → gp8 同款改谱表上方（rowTop−14，字带上方
   0.6px 净空；L.R. 同层仅同音 letRing+vibrato 罕见组合相交）
3. **m82+ 稀疏小节仍 2/行** → 即 1a 的锁死；另发现宽度校验用"音数×17"
   把和弦小节（LAS 密集段 56 音仅 13 列，同拍跨弦叠放）算宽数倍——
   重写为**按列比例需求**：need = 阈值×拍数/最小列距（阈值按字形
   一位数 10/含两位数 17）+ dup 展开。**允许 1/行**（叠印投诉优先于
   "保底 2 不碎行"）

**全库终检（7 份谱 ×786 宽模拟管线）**：越界 0 / 低于自身墨阈音对 0 /
同点叠印 0 —— Distance/Flower×2/LAS/Time travel/Bluebird/月下之恋
全过。LAS rows 46→65（密段 1/行、稀段 3-6/行）；月下 28→20。

测试更新：tab_layout 2 用例（fret12 连排行 2 小节为新正确行为——两位数
16px 墨宽在旧 6/行 10.5px 列距必叠）、hit 坐标迁 6/行（9 音一位数谱
需求 109px 宽校验放行 6/行）。analyze 0 + 284 全绿 + exe 重建。

⏳ 记录：布局类改动必须跑真谱探针量化（本日三次教训：
自引用/回写覆盖/阈值失配都是合成 fixture 测不出、真谱一测就现形的）

## 用户"这对嘛"截图 → 折行判据三连修（2026-11-12 中午）

截图（111822）：**每个 3-7 音小节独占一整行拉满全宽**（泛音段 m1 前
62% 空白）——上一版"最小列距×拍数"需求公式被单个紧拍对绑架。zai +
子代理双路分析还发现：行首 `<12>` 贴死小节线、空拍无休止符、L.R.
虚线悬空、m4 孤立小弧等（渲染层缺项记档待查）。

**折行判据演进（三版收敛）**：
1. 需求宽求解器（二分拍宽）——**原理性缺陷**：需求随行宽变化，与行
   宽比较是循环论证（m25 需求按 1/行评估却分到 2/行 → 1.2px 漏网）
2. Σ链亏空求和——**过严**：亏空被后续大间隙吸收不累积（LAS 63 行
   过碎）
3. **链模拟精确判据（定稿）**：完全复刻拥挤趟——组链位 = max(自然
   位, 同弦链前+墨阈和)，判**链尾 ≤ 右界内 12px**。与渲染管线同构，
   零漏检零误判

**全库终检（7 谱）**：越界 0 / tight 0 / 叠印 0；LAS 37 行（密段 2、
稀段 5/行）、月下 15、Flower 9-11。测试断言按链模拟语义更新（fret12
0.25 拍连排 6/行放得下——旧公式误判 292px 需求压 2/行）。analyze 0 +
282 全绿 + exe 重建。

⏳ 渲染层缺项记档（子代理发现，待用户确认优先级）：空拍无休止符、
行首和弦贴小节线（2px）、L.R. 虚线跨小节续接、m4 孤立小弧、
`<12>` 内数字与普通数字两种字号

## dsh 三轮 FAIL → 排布趟重写（2026-11-12 晨，部分已被上节取代）

- **dsh 实锤 P0 自引用 bug**：按音遍历的组推移把组内各弦 lastX 写成
  组员自身 x → 组员再处理时"自己和比自己"恒真 → 每组多推 17px，
  密集谱把组推向右线 → 撞 dup 钳制塌缩（dsh 报"181 处完全同 x 叠印"，
  探针确认是自引用下游症状）
- **重写（全部落实 dsh 三轮建议）**：
  - 拥挤趟改**按组遍历每组一次**，组位移 = 各弦约束取 max（幂等）
  - lastX/lastNote **按小节 reset**（跨小节传染从隐式兜底变显式不变量）
  - 阈 = **9+前音半宽+本音半宽**（纯数字对=17 与宽度校验对齐；幽灵
    '(3)'/泛音'<12>' 宽字形自动加大——落实"校验按实际字形宽"）
  - beat 键 toStringAsFixed(1)→**(3)**（1.04 误判 1.0 的 dup 平白错开）
  - dup 钳制**首音永不钳**（noteX 列位上限右线−10 会被 −12 界误钳 2px）
  - _labelHalfWidth 抽共享静态（tap 弧/字母避让/拥挤阈三处统一）
- **v3 真谱对账**：越界 0、同点叠印 0、推移 123 全钳小节内、最小同弦距
  14.1px（最挤小节极端音对，"不越线"优先级的物理代价）
- analyze 0 issue + 280 全绿 + exe 重建
- ⏳ 记档待办：flow 排布抽取为可测单元 + 回归用例（三档宽/组/dup/逆序
  断言间距与边界）——与"排布算法整体升级"合并做
- 连音轮最终态：analyze 0 issue + 280 全绿 + release exe 构建（11-12 凌晨）
- 探针与 golden 用完即删；matchesGoldenFile 假时钟挂死 + File IO 须
  tester.runAsync（lessons 规则 17）
- [ ] 用户验收（连音/吞音三症状 + gp8 对照）
- ⏳ 已知遗留（未修，记档）：命中测试未跟随 dup/组推移偏移（11-10 起
  pre-existing，用户未报误击；行结构错位已随 layoutW 统一修复）；
  全占回退中点可能贴上弦数字（盒垫 1px 边际，罕见）；repeatEnd 小节
  多组同近右线的组间碰撞（pre-existing，病理场景）；hit 偏移根治待
  排布算法整体升级（flow 位置共享给 hitTest）

**GP8 实测子代理数据**（会话重启即终止，但产物留存）：
%TEMP%\gp8_meas\（measure2/3/4.py、page_scan.py、aggregate.py + 截图）——
新会话可直接读其聚合输出续分析，或重启 GP8 重测（GP8 exe：
C:\Program Files\Arobas Music\Guitar Pro 8\，曲谱 D:\Guitar\月下の恋）。

**逆向备忘**：GP8 自更新过——旧 Ghidra 工程（D:\ghidra_projects\*.rep，
11-01 建）与当前 DLL 函数地址偏移 0x760/0xd40，**不可混用**；当前版用
REA（open_binary）重新分析。makeSlur 调用点均为 .rdata 函数表引用（间接
调用），调用方追不到——字母发射逻辑未定位，以经验测量为准。

**新规则（2026-11-11 项目 CLAUDE.md）**：开发完成后调 dsh 做测试角色
最终测试（连同既有的 analyze+test 自测）。

**修复落码清单**（证据齐后）：弧端点锚定+避让（tab_view.dart 连音段）→
字母缩字号+x 避让 → 全量测试 → dsh 交叉复测 → 用户验收。

## 折行铁律 2~5/行 + 渲染缺项四修（2026-11-12 下午，进行中）

用户指令（附 CLAUDE.md 新铁律"除最后一行外，每行最少2小节，最多5小节"）：
①查 LAS m100 为何单行 ②渲染缺项一并处理 ③Flower m39 反复终止尾部多两点。

1. [x] **min2/max5 铁律落码**（tab_layout 折行循环）：密度档封顶 5（旧
   ≤10 档 6 删）；cur.length==1 时不得 flush（宽度不满足也压缩加入——
   规则优先于宽度）。真谱探针 6 谱 ×2 宽（786/834）对账 bad=[]：LAS 37
   行全 2~5、**m100@row35=2 小节**（单行根除）；唯一单行 = Distance 末行
   （豁免）。分布：LAS 密段 2、稀段 4-5；Flower 9 行 4-5；月下 15 行
2. [x] **Flower m39 双点根因**：行末收尾块（lastM.repeatEnd 画外侧点对
   endX+10 + 粗线 endX+5）与 per-measure repeatEnd 块（内侧点对 rx-6 +
   粗线 rx+4）叠加 = 4 点。gp8 反复终止形态仅内侧一对点；行末块整体
   删除（收尾竖线 + per-measure 粗线即完整「细|粗」形态）
3. [x] **孤立小弧修复**（用户走查 m4）：弧线终点跨行（同弦后继不在本行
   flow）时旧代码回退 f.x+22 画短弧悬空 → 改延伸到行末竖线收尾（gp8
   跨行形态）；hopo 字母仅 next!=null 时画（跨行终点品未知 H/P 无判据）；
   slide 斜线同款延伸
4. [x] **空拍休止符**：时值轴覆盖检测（[beat,beat+duration) 合并后找
   [0,bpb) 空洞），逐拍画休止符于谱表中线（弦 3-4 之间）——整拍四分
   锯齿、尾段 <1 拍八分（锯齿+旗）、整小节空画全休止方块（挂第 4 弦线）
5. [x] **行首贴线保护**（用户走查：行首 <12> 墨缘压左竖线）：**仅行首
   小节首音组**组粒度右移至墨左缘距左竖线 ≥5px（notePad=10 只保数字
   中心，宽字形墨半 11 压线）；全量强制钳制曾连锁破坏 tap 连线（11-09
   教训），非行首小节维持现状待排布升级
6. [x] 测试迁移 5/行语义：tab_layout（封顶 5/末行豁免用例）、hit（
   perRow=5、m7=row1col2、m6 failed=row1col1）；286 全绿 + analyze 0
7. [x] **验证链收口**（子代理静态复测 P0=0/P1=1/P2=8 + 自跑像素验证）：
   - 静态复测 PASS 项：折行循环边界（cur==1 永不 flush / ≤5 恒成立 /
     maxBarInCur post-flush 正确）、rowFits 与拥挤趟同构、双点根除形态
     =「点|细|粗」、跨行弧 clamp 安全且正常 slide 零影响、hopo 字母
     guard 正确
   - **三处整改落码**：P1-1 行首贴线保护移到拥挤趟**之前**（旧位置吃掉
     第二组 1px 净空 → 同弦墨重叠 2-6px）；P2-1 休止符覆盖区间钳制
     bpb（duration 越小节线会把 rest 画进下一小节）；P2-6 tab_layout
     注释漂移更新
   - **像素级终判（自跑 PIL 字符画）**：Flower m39 = 点恰 2 个（rx-6，
     rowTop+8/rowBottom-8）+ 细|粗线 ✓ 无双点；跨行弧延伸到行末 ✓；
     空小节全休止方块 ✓（zai 图像分析佐证）；LAS 倒数两行各 2 小节
     （竖线 [15,392,769]）✓ m100 修复确认
   - 渲染 rowTop/rowBottom 语义勘误：= 弦线 1/6 的 y（非谱行含 topPad
     顶）——repeat 点/L.R./波浪线 y 推算全以此为准
   - 287 全绿（tab_layout 新增铁律用例 +1）+ analyze 0
8. [ ] 重建 exe（进行中）→ 用户验收
9. [x] 临时探针清理（law_probe/render_probe/m5_probe 测试已删；%TEMP%
   gb_*.py 脚本留存备查可手动清）

### 行首贴线最终口径（2026-11-12 收口）

- **实现口径达标**：行首首音组字形墨缘距左竖线**中心** ≥5px（一位数
  22/两位数 21/泛音 21/幽灵 21——全部 ≥ mx+5）；**硬规则「不遮挡竖线」
  像素级满足**（x17-18 弦区零墨迹，两个子代理独立确认）
- 子代理判 FAIL 用的是「距竖线**右缘** ≥5px」口径 + 200 阈值含抗锯齿
  扩散（字形缘 21 → 检测出 19）——口径差 1px + 抗锯齿 2px，非缺陷
- 更宽间隙（gp8 ~16px 中心距）待排布升级一并做（强制加大推移有 11-09
  连锁教训）

### 用户验收反馈「小波浪线」（2026-11-12 下午，已修）

- **破案**：用户截图红框内的「小波浪线」= 本轮新画的**空拍休止符锯齿**
  （𝄽 折线，zai 聚焦分析确认）——源文件/gp8 里没有 → **误画**
- **根因**：部分空拍休止符按时值轴覆盖检测画，但 IR 的 duration 累计
  在真实谱上有洞（音的时值偏短/延音不回填）→ 有音的拍被误判成空拍、
  成排画锯齿；gp8 的休止符基于节奏结构（Rhythm）而非 duration 累计
- **修复**：**回滚部分空拍的逐拍休止符**，仅保留「整小节空」（notes.
  isEmpty 非 failed）的全休止方块（真数据无误判）；待解析层时值对齐
  gp8 Rhythm 后再考虑启用精确休止符
- 顺带实锤（记档）：tap 弧规则收紧为「两端都是 tap」（单发 tap 不连弧，
  LAS m40-45 每小节 5 个单发 tap 曾被连成满行弧链）；P.M./L.R. 虚线为
  真实数据（gpif PalmMuted 15 处/LetRing 7 处，gp8 同款应显示）
- 281 全绿 + analyze 0 + exe 重建；临时探针已删（%TEMP% gb_*.py 留存）

## 用户验收两反馈（2026-11-12 傍晚，已修）

1. [x] **导入重名连加不分类型**：`_uniqueTitle` 旧版全库查重（`a.gpx`
   与 `a.pdf` 同名也触发 `a (1)`）；改**同类型内查重**（`sourceType`
   过滤——与 scores_page 重命名同款语义；importScore/importImages
   两处调用传入类型）。用户要求：仅相同类型的重名文件才括号连加
2. [x] **弧线遮挡数字**：tie/hopo/legato 弧从「端点弦下 +5.4、弧体穿
   数字带」（11-11 gp8 复刻版）改为**数字头部上方**——端点 y-10、拱顶
   y-14.5（数字带 ±8 顶部 y-8 净空 2px；H/P 字母 y-17 在弧上方）。
   合成探针像素验证：弦下 y82-88 零墨迹、弧 y66-69、字母 y60-65
- 280 全绿 + analyze 0 + exe 重建；render_probe 探针用完即删

## 用户追问"超长连音弧判定依据"（2026-11-12 晚，已闭环）

- **用户指的线 ≠ 连音弧**：1px 级形态分析 = dash4-gap3 虚线（占空比
  53%≈57% 吻合 `_dashed()`）→ 是 **L.R. 延音虚线**；真正 tie 弧全曲
  仅 4 条且全是 0.25 拍短弧（m17 b3.25→3.5 s4、m21 b3.0→3.25 s3/s4/s6，
  IR 对账实锤），无超长弧
- **时间线闭环**：用户 15:37 截图时跑的是 15:33 exe（不含 L.R. 段尾
  修复）；L.R. 修复在 15:51 构建——截图的超长虚线正是旧 bug 产物
  （段内遇 letRing 音误判无段尾 → 画到行末 1381px）
- 弦 3 上方的浅灰长链（y74）= 弦 2 数字带下缘抗锯齿（非线元素）
- 无代码改动（L.R. 修复已完成）；tie 探针用完即删

- **判定链路**（用户问题的直接答案）：截图长线 = **L.R.（LetRing 延音）
  虚线**——数据判定 = gpif 音符 `<LetRing/>` 子元素（LAS 7 处全在泛音
  上，反复段展开后 IR 17 处）；画线 = 段头（同弦前一音非 LR）画虚线到
  **段尾** + "L.R." 文字（rowTop-15）
- **段尾 bug 实锤**：旧循环找到第一个同弦音就 break——若它也是
  letRing（段内音），segEnd 留默认 endX → **同弦 ≥2 个 letRing 音时
  虚线画到行末**（用户截图 636px 超长线根因）。修复：段内音跳过继续
  找，段尾 = 同弦下一个**非 LR** 音，无段尾才到行末
- **修复后对账（宽屏 1300 渲染 + IR）**：剩余长段全部有数据依据——
  r36 876px = m102 letRing 延续到曲终 m103（合法）；r0/r2 310px =
  m2/m4 泛音延音跨小节到下一音（ABA 镜像 r31/r33 同款 ✓）；Flower
  段 41-45px 正常
- 280 全绿 + analyze 0 + exe 重建；arc/render 探针用完即删

## Distance 超长弧共性修复（2026-11-12 晚，弧线规则重定义）

- **用户实锤**（两张截图 + "共性问题"）：Distance/全曲库的谱面有大量
  gp8 里不存在的长弧。数据对账：Distance tie 几十条（0.5-1 拍 + 跨小节）、
  Flower hopo 8 条 1-2.5 拍、月下 tie 40 条 1 拍——旧规则"tieStart/
  hopoStart/legatoStart 都画弧到同弦下一音"把它们全画了
- **gp8 对照差异**（GPCore 逆向 + 用户 gp8 截图对照）：gp8 tab 视图
  **只有击勾弧（HoPoSlurView）**——延音（tie）弧属五线谱层（NoteSlurView），
  tab 不画（延音由时值表达）；击勾弧只连**快速击勾对**（hammer-on/
  pull-off 乐理上必然 ≤0.5 拍），数据里的长距离"hopo"配对是连奏标注，
  gp8 tab 不画弧
- **新规则**（tab_view.dart 弧块）：①tieStart 不画弧（类型级停画）
  ②hopo/legato 弧终点拍距 >0.5 拍不画（跨小节累计拍数：Σ中间小节拍数
  − 起点 beat + 终点 beat）③终点跨行（next==null）不画——上午加的
  "跨行弧延伸到行末"规则一并作废（弧只在短距内存在，永不跨行）
- **合成探针四用例像素验证全 PASS**：短 hopo（0.5 拍内）画弧+H 字母
  ✓、tie 不画 ✓、1.5 拍 hopo 不画 ✓、跨小节 3.5 拍 hopo 不画 ✓
- **二轮收敛（用户复测"很多本该有的小连音弧都没有了"→ 一轮砍过头）**：
  tie/hopo/legato 全恢复画 + 阈值 0.5 → **1.5 拍**（保月下 40 条 1 拍
  tie + Distance 0.5-1 拍弧 + 0.25 拍跨小节短 tie；砍 2+ 拍与跨行弧）。
  合成探针二轮四用例 PASS（0.5/1.5 拍画、3.5 拍跨小节不画）+ GP8
  Distance 实拍对照（窗口级截图不抢前台）：GP8 tab 弧确实存在且为
  短弧（460px 区域 4-6 条，连相邻数字）——弧在数字下方（用户上午
  定案要在上方，保持用户要求优先）
- 280 全绿 + analyze 0 + exe 重建；阈值 1.5 拍为当前定版，用户 gp8
  对照反馈可再微调
- ⏳ 留观项：legato 弧（样本少，暂与 hopo 同规则）；slide 斜线长距离
  同类问题未处理（用户未提）；弧与上弦 label 底缘带重叠（弦距 20 的
  几何约束，弧 y-10..-14.5 与上弦 label 底 -12±8 重叠——极罕见场景
  文字层盖住，待用户反馈）

## 剩余两问题（2026-11-12 晚，提交后开工）

### 1. 调音器布局（吉他下方空白多）→ 已修

- 根因：gaugeHeight 旧 0.14 系数 + 200 封顶——pad 竖屏下总内容
  ~915px < 视口 1024，~109px 空白堆在吉他下方
- 修复：网格区**吃掉全部剩余视口**（视口 − 设备栏96 − padding48 −
  固定行区248 − 琴头 headHeight），clamp(120, 480)——音准方块区放大 +
  吉他下移贴满；窗口矮时下限 120 → 整页滚动保底

### 2. 播放器底部色块（三轮未解）→ 四轮根治

- **真相链**（golden A/B + 渲染树 dump 实锤）：Scaffold 自动把
  bottomSheet 包进 `_StandardBottomSheet→BottomSheet(Material
  elevation 1 + M3 默认色)`——浅色下画**全宽 panel(237) 灰带**，即
  用户"播放器背后连到底部的圆矩形色块"（比 ground 247 深一档）。
  11-10 加的 Material(transparent) 包裹根本盖不住它（槽容器在更下层，
  当时"暗带"就是这个 BottomSheet 容器）；11-11 的 surface 圆角卡、
  11-12 的去 Material 包裹/透明底板都只动了上层
- **根治**：主题 `bottomSheetTheme: BottomSheetThemeData(
  backgroundColor: transparent, elevation: 0)`——槽容器透明零海拔。
  PlayBar 底板同时全透明（panel@50% 灰板为次源），控件悬浮透出与
  谱面同色背景；note_edit_sheet（唯一 modal）显式传 panel 底色保样式
- 最终 golden 验证：底部纯 ground(247)，panel 灰带消失，控件正常
- 280 全绿 + analyze 0 + exe 重建

### 探针方法学教训（记档）

- golden A/B 二分法定位渲染层时**必须同步确认 detail page 的
  bottomSheet 状态**——本轮"逐个恢复控件全干净"是空 bottomSheet
  假象（PlayBar 不在树里），浪费一轮二分
- 渲染树 dump（visitChildren 找 Material elevation/color）比像素
  A/B 快：一轮定位 _StandardBottomSheet 真凶

### ⏳ 记档：LAS r1 行首孤立墨带（pre-existing，未修）

- LAS 第 2 行行首 x11-99、y 弦线 1±8 的 88×15px 实心墨带，覆盖左竖线
  顶部 ~9px（竖线 y240 起露出）。**非音符**（m5 首音 beat0.5 @x43、五
  音全无标注）、非弧线/滑音/波浪。旧图（整改前渲染）同样存在 →
  pre-existing。Flower 无此带（其 x19 首墨 = 13px 音符块）
- 用户真机从未报告该处异常（可能仅探针渲染环境可见），待用户下轮
  走查确认是否真机可见再决定排查优先级
- 怀疑方向：某 Paint strokeWidth 异常或路径退化（未定位）

- ⏳ 记档暂缓：L.R. 虚线跨行续接（无 gp8 证据——gp8 跨行走查样本待采）；
  `<12>` 内数字与普通数字字号差（代码确认同 fontSize 14，视觉差为尖括号
  轮廓效应，非 bug 不改）
- 命中测试未跟随 dup/组推移偏移、repeatEnd 多组同近右线组间碰撞（
  pre-existing，记档不变）
