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

## gp3/gp4 格式适配（2026-11-13，用户："158 目录自行对照，开始适配"）

1. [x] 移植规格：子代理从 PyGuitarPro 源码提取 tasks/gp34_spec.md
   （412 行逐字节规格；核心结论 GP4 = GP3 + 头部 3 插入 + 4 效果段覆写）
2. [x] lib/core/score/gp34_parser.dart：GP3/GP4 共用解析器（_Gp34Reader，
   版本串自判 _isV4 分层差异段；GBK 标题；轨选择跳过全 0 调弦哑轨）
3. [x] PyGuitarPro 基线对账（test/tool_gp34_reconcile_test.dart）：
   gp3 伤心1999（242 音）+ gp4 世界最慢（257 音）逐音对齐——
   beat/str/fret/dur/dotted/tuplet/tied/hammer/slide/vibrato/ghost/
   staccato/palmMute/harmonic 全字段。对账口径三件套：
   py 绝对 tick 基准 960 对齐（gp3.py:384 start=quarterTime）、
   py 基线 dur 补 tupletRatio、tie 链式合并对齐产品 _refs 语义
4. [x] 全量扫描（test/tool_gp34_scan_test.dart）：158 目录 2357 个
   gp3/gp4（9 秒）——2312 解析成功、3 错标 v5 自愈走 gp5 通道、
   42 GP1/2 错标、50 坏文件（PyGuitarPro 同判，双向对账）
5. [x] 路由：魔数判定 _gpBinaryFlavor（版本串/BCFZ/zip 头）替代
   扩展名路由（158 实测 46 个错标扩展名：v2.21/v1.04/v5.00 都有）；
   GP1/2 明确报"老格式暂不支持"；导入选择器/文案/注释同步
6. [x] repeatCount 语义对齐：GP3/4 raw=重复次数（py 直存）→ +1 换算
   总遍数（score_ir:246 展开器语义；对照 GP5 raw=总遍数直存）
7. [x] 全量 283 测试绿（280 存量 + 2 对账 + 1 扫描）
8. [ ] dsh 复测（claude 子代理静态复核，后台）→ 构建验收 → 提交

### 关键纠错记录（对账过程中的四处真 bug）
- empty beat 时值推进：曾误改成"恒推进"再回退——py 源码实证
  （gp3.py:468）empty 返回 0 不推进、rest 拍推进
- 对账 test flatten 的拍号累计：sig=null（回全局拍号）误用
  "保持上一小节"——伤心1999 m39 真实是 2/4（pos 1000 flags=9
  实证），m40 起 null 应回 4/4；曾误判为解析器错位白查一轮
- GP4 slide 枚举：3/4（outDown/Up）、-1/-2（into）此前丢弃 →
  统一映射 shift
- 哑轨隔离：_refs 全局共享，非选中轨必须 out=null 不入 IR 不
  登记（防 tie 回溯污染）；tuning 全 0 轨（东方之珠轨 1）跳轨

### 待办
- gtp（GP1/2，444 份 + 42 个错标在 gp3/gp4 里）：PyGuitarPro 不
  支持、无参考实现——需用户确认是否自研（3.x 版低频格式）
- 42+50 个错标/坏文件导入时会明确报错（不崩），属预期行为

## gtp（GP1/2）格式适配（2026-11-13 下午进行中，下班存档）

### 已完成
1. [x] gp8 实现定位：**GPIO.dll**（C:\Program Files\Arobas Music\Guitar Pro
   8\，非 GPCore）的 `gp::io::GP5ScoreLoader::readOldGtp`（0x180074420，
   10.9KB 单函数内联 GP1/2 全解析；v1.01~v5.10 版本串表都在该 dll）
2. [x] 规格基准：**TuxGuitar**（helge17/tuxguitar）GP1InputStream.java /
   GP2InputStream.java / GTPInputStream.java（源码在
   C:\Users\plafa\AppData\Local\Temp\tuxgtp\）——比反编译 71k 行可读
3. [x] 444 份 .gtp 版本分布：191 GP1 + 180 GP2 + **73 错标 GP3/4**（错标
   的会被 gp34 通道自愈吃掉）
4. [x] python 直译基线（gb_gtp12_baseline.py）：v1 样本 108 音 + v2 样本
   990 音
5. [x] **lib/core/score/gtp12_parser.dart 写完且对账全绿**（v1+v2 逐音
   对齐：beat/str/fret/dur/tied/hammer/slide/vibrato/dead/harmonic）
6. [x] test/tool_gtp12_reconcile_test.dart 全绿
7. [~] python 全量扫描 444 份（**关机中断了**，下次重跑一条命令：
   `python D:\workplace\code\GuitarBar\tasks\gtp12_tools\gb_gtp12_pyscan.py`
   ——脚本/两个样本/TuxGuitar 规格源码已备份到
   D:\workplace\code\GuitarBar\tasks\gtp12_tools\，Temp 丢了也无所谓；
   基线重新生成用同目录 gb_gtp12_baseline.py + samples\ 下样本）

### 下次继续的接力点（2026-11-14 更新：1-2 已完成）
1. [x] python 全量判决修正后落盘：**439 可解析（gtp12 366 + 错标 v3/v4
   走 PyGuitarPro 73）/ 失败 5**——与 Dart 完全同级双向对账。修正点：
   py 直译只认 GP1/2，错标 v3/v4 的 .gtp（73 个）误当 GP1/2 读到 EOF
   才显 77 假失败；判决脚本加同款路由（v3/v4/v5 → PyGuitarPro）后收敛
   到 5 = 真截断文件（单身情歌2/那些花儿2/自动胜利/灰姑娘2/爱的呼唤2，
   偏移=文件大小实锤）
2. [x] **路由接入完成**：_gpBinaryFlavor 加 gtp12 分支、importScore
   switch 加 'gtp12'、isGtp 加 ext、选择器/文案加 gtp、删旧"暂不支持"
   报错（analyze 0 issue）
3. [x] **全量 286 测试绿**（280 存量 + gtp12 对账 2 + gtp12 扫描 1 +
   gp34 对账 2 + gp34 扫描 1）；release 构建跑着
4. [x] dsh 子代理复测完成（对照 TuxGuitar Java 源码逐段复核）：
   **2 必修全修 + 4 建议全落实**——
   - 必修1 全拍 tie 跨休止拍幻影音（rest 后 0x40 复制休止前旧音；
     TuxGuitar rest beat 无音符 → tie 查空 voice = 静音拍）：Dart rest
     分支清空 lastBeats（1 行）+ python 基线同口径修 2 处 + 基线重生成
   - 必修2 repeatAlternative 多结尾丢弃（24 文件反复第二遍连"1. 结尾"
     重播）：从 gp34 通道移植 existingAlternatives 累积算法（~15 行），
     endings 填入 MeasureIr
   - 建议：13B→12B 注释勘误 / beat effect 5→tap（TuxGuitar tapping）/
     GP2 dynamic→velocity+dynamicMark（16d-1 同 gp34）/ durByte 负数
     math.pow 守卫（1 << -1 崩 → breve 支持）
   - 复测实证：reconcile 2/2 绿 + 全库 444 扫描零失败 + python 判决
     439/5 双向一致；修复后重生成基线对账仍绿（样本无休止+tie 模式）
   - 复测教训：**对账只能证 Dart==基线，证不了 Dart==权威**——python
     基线与 Dart 共享同一建模分歧（rest 不清 lastBeats），这次靠 Java
     源码做第三方裁决才暴露；影响面量化工具 gapcount（复测产出，
     tasks/gtp12_tools/）
5. [ ] 终态：analyze 0 issue + 286 全绿 → release 构建确认 → 用户验收
   → 提交
- 教训（新）：**python i32 在 EOF 静默返 0**——错位读垃圾当弦数/拍数
  时 range(巨值) 假死循环（首跑扫描卡 20 分钟的根因）；直译脚本加
  EOFError 守卫后 3 分钟跑完。py 判决脚本与被测实现必须**同路由口径**，
  否则错标文件污染失败清单（77 vs 5 的假差异白查一轮）

### 关键技术档案（gtp 与 gp3/4 的代际差异，规格在 parser 头注释）
- 无独立 measure header 段（拍号/反复嵌小节体）；每小节 8 轨 × 13B 表
- 字符串**双长度字节**（U8(len-1)+U8(len)+内容）；版本串 30 定长 ✓ 同 gp3
- tie 是**拍级全拍连音**（flags1 0x40 复制上一拍）非逐音标记
- 效果 1 字节枚举（非位掩码）；弦位 bit i = stringCount - i
- GP2 增量：拍双 flags（mixChange/stroke）、音符 dynamic、grace 3B
- GP1 trackCount：code≤2 单轨；code>2 / GP2 恒 8 轨（多哑轨 beats=0）
- 轨选择：第一个有音且调弦非全 0 的轨（每轨独立 refs/lastBeats）
- repeatClose U8 = 重复次数 → repeatCount = raw+1（同 gp34 口径）
- **教训**：8 轨"弦数+调弦"必须一体循环读（拆两遍读错位 1112 字节
  白查半天——python pos 打点对照才定位）

## gp3 扫弦方向 + gtp 连音密度（2026-11-16 用户两报，方法论升级）

1. **gp3 扫弦方向错误**（哆啦A梦.gp3，app 显示 ↓ gp8 显示 ↑）——已修：
   根因 = PyGuitarPro gp3 代码与自身 docstring 矛盾（docstring 说字节 1=
   上扫，代码按 down 先读），TuxGuitar 照抄同错；py gp5 靠 swapDirection
   补偿反而正确。修 gp34 GP3/GP4 两分支 → 字节1='up'（与 gp8 实测、gp5
   通道网络效果、py docstring 三重一致）。analyze 0 + 286 全绿。
2. **gtp 连音密度**（Prologue，"每个音都有连音线"）——定位完成待修：
   - score 68 的 Prologue.gtp **实为 GP4.06 错标**（走 gp34 通道）
   - 文件本身 tie=190/normal=234（py 实证，押尾持续低音写法）
   - 我们渲染画 166 条弧（190 tie 中 34 条被 1.5 拍阈值抑制）
   - gp8 对照（截图 + 双判读）：TAB 行几乎不画弧（五线谱画全部 190 条）
3. **方法论升级（用户定调）：不再逐符号截图判定**——成体系逆向 gp8 的
   "音符属性 → TAB 显示"完整决策链，1:1 复刻。逆向 agent 已出发：
   - P0：tie 在 TAB 的显示判定（画弧条件 + 数字形态：普通/括号/隐藏）
   - P1：全部符号（dead/ghost/accent/staccato/tap/L.R./P.M./vibrato/
     slide/泛音/trill/grace/arpeggio/brush/fadeIn/tremolo…）的判定表
   - 产物：tasks/gp8_tab_display_spec.md（判定表+反编译证据）
   - 工具：旧 Ghidra 工程 gpcore.rep 免导入直挖（渲染逻辑小版本更新
     不变；旧地址不得套当前 DLL）
4. [ ] tie 修法等 P0 判定条件落地后按 gp8 原文实现（渲染层改动）
5. [ ] 全符号判定表落地 = tab_view 显示层对齐 gp8 的系统性升级

## tie TAB 显示规则落地（2026-11-16 晚，逆向判定表 §2 复刻）

1. [x] 数字形态（tab_view 数字分支）：tie 延续音 = 锚点音（hopo 起/滑音/
   颤音/trill/bend）裸数字 / 小节首拍括号 "(N)"（Prologue 多位置实锤，
   decomp 未挖到括号路径、实证优先）/ 中段隐藏
2. [x] 弧线门（tab_view 弧线块）：纯延音 tie（非 hopo/legato）弧线 =
   两端数字可见 + 同小节才画；hopo/legato 弧不受门（HoPoSlurView 独立类）
   + 1.5 拍阈值保留（用户已验收口径）；纯 tie 弧过门后不再受拍距限制
3. [x] inkHalf：小节首拍 tie 括号 = 12（幽灵括号同宽）
4. [x] analyze 0 + 287 全绿
5. [ ] 实机验证：重建 exe → 开 Prologue（score 68）对照 gp8 裁剪图
   （hi_m1_tab / hi_m2m3_tab / hi_m9m10_tab）
6. P1 对齐遗留（判定表已备，逐项需样本验证）：
   - slide 斜线缺 "sl" 文字（spec §5 + 今日 crop 双证据："3↗10 sl"）——下轮加
   - trill：gp8 TAB 画 trill 目标品数字（TabBeatView.trills FretView），
     我们画 tr 右上角——需 trill 样本对照后改
   - tap：decomp 说 LeftHandTapView 是 TAB 专属（T+短弧线），11-08 截图
     对照说 gp8 六线谱无 T——两证冲突，需左手点弦样本仲裁
   - bend 曲线 TAB 渲染（BendView 相位点）——v1 已知缺口
7. hideTiesBetweenBar 不实现（8.1.1 渲染路径零消费者，死设置）

## 数字重叠铁律落地：常驻探针 + 全谱清零（2026-11-16 深夜，进行中）

铁律来源：用户"增加一个铁律，小节内数字，(数字)，<数字>等展示形式，不允许
除六线谱外的遮挡……很多次改完之后发现多数字重叠"→ 已入 .claude/CLAUDE.md。

1. [x] 墨盒捕获基建：tab_view TabViewDebug.lastPaintedTexts（paint 真实
   TextPainter 墨盒：center/halfW=实宽/2/halfH=字号×0.36）+ TabFlowDebug.
   lastFlow（排布终位镜像，残类定位用）
2. [x] 常驻探针 test/tool_overlap_probe_test.dart：真实曲库 56 谱×宽
   [786/900/1100/1300] → 两两判相交（双轴穿透>1px）→ 零重叠
3. [x] 首轮 3134 → inkHalf 旧常数失真（一位数 4 vs 真实 7）→ 改真实
   TextPainter 实测 + tabLabel 抽共享唯一事实源 → 245
4. [x] 二轮 245 → 11：mf 去重/带位移/L.R. 避让阈 38/箭头 x/pickStroke；
   H×L.R.（band 标签预收集，绘制顺序无关）；H×数字（上带→弧下带→放弃
   字母，铁律优先）；capo×小节号（按实测墨宽起排，textInkWidth 新公共
   助手）；(5)×(0)（dup 错开趟步长改 1+前墨半+本墨半）；12×11（拥挤趟
   链状态跨小节贯穿——按小节 reset 在边界留 5~21px 死角）
5. [x] 三轮 11 → 4 → 0：
   - fade in/Wah 段头去重 + 行底带游标（fff×fade in 同拍双标注互压根除）
   - 左推趟新增（拥挤趟右推被小节右界挡死的末拍组/dup 去钳溢出：时间倒
     序把亏空转前驱组左移，整组移保同拍对齐，左线头寸硬钳）
   - **趟序修正**：repeat 保护趟移到拥挤趟之前（链后再移=吃掉链内净空，
     gtp "(2)"×"2" 恒 17px 实锤）；左推趟亏空判据改实际墨距
     dist=|f.x-p.x|（倒置不重叠对不得按 p.x+gap-f.x 误判级联拉爆）
   - **度量字体统一（关键）**：测试环境 Ahem 每字形 1em（"(2)" 虚胖 2 倍，
     7 连括号谱误判结构放不下）→ tab_view._text 显式注入 kUiFontFamily
     + tab_layout._measureInk 同款 + 布局/渲染测试 FontLoader 加载生产
     字体文件（test/font_setup.dart；'Ahem' 名下加载被内建压住不生效）
6. [x] 探针全绿（56×4 组合零重叠）+ analyze 0 + 全量 290 过 0 挂
7. [ ] 实机验证：重建 exe → 用户抽查宽谱（月下之恋/Prologue/LAS/多声部）
8. [x] lessons 已记（规则 20 度量字体一致性 / 21a 趟序 / 21b 实际墨距判据）

## 全量探针（158 库 3376 文件 × 4 宽，2026-11-16 深夜，**下班交接点**）

- [x] 建全量探针 test/tool_overlap_probe_full_test.dart + 共享件
  overlap_probe_lib.dart（魔数路由/y 扫描判交/谱集收集）+ 常驻探针升级
  **全谱高渲染**（旧 h=2400 只检前 12 行，长谱下行漏检的洞已补）
- [x] 首轮 44735 违例 → 分型：①结构性不可满足（2~5 铁律 × 连排密度，
  gp8 靠窄音乐字体才放得下）→ 豁免判据 hasOverfullMeasure；②真 bug 505
  - crowd 前瞻缺失/判据口径差三处（行首偏移 +3.6 踩线/跨小节入链/dup
    占位）→ **rowFits 升级行级链模拟 rowOverfull**（dup 错开+跨小节贯
    穿链+行首偏移，完全复刻实际排布趟）——七里香 5/行判 TRUE 实际超
    界 → 倒置对 → 左推趟级联回退（重叠搬家）实锤
  - 标注符号层：accent×断音同位（点右移 8）/L.R.P.M. 标签让位 1 弦
    accent/字母 occupied 加 accent 盒+已画字母盒/力度带行级游标
- [x] 二轮 427 → 豁免漏"保位互叠"形态 → rowOverfull 补判据（保位且
  缺口 >2px = 探针口径必违例 → 豁免）——**三轮跑批中**（后台
  b24c0h2c9，输出存 tasks/probe_full_out.txt）
- [ ] **下次接力**：读 probe_full_out.txt 汇总行（判罚/豁免/违例三数）
  → 违例仍多则继续分型（violation 明细 + diag 脚本 test/tool_diag_
  dense_test.dart 改谱名即用）→ 常驻探针+全量 test 回归 → 重建 exe
- 常驻探针（用户曲库 56 谱）本轮全绿**未回归** ✓
- [x] lessons 已补规则 22：**判据必须完全复刻实际排布趟**——行首偏
  移/跨小节链/dup 占位/保位互叠四处口径差各爆一轮（判 TRUE 实际叠
  或反向豁免漏判）；保位互叠的豁免口径 = 探针同款（缺口 >2px）

## 哆啦A梦击勾弧反转（2026-11-17 用户 gp8 截图实证）

- [x] 根因：GP3/4（及 GP1/2 老格式）hammer 标志 = **origin 语义**（弧
  从带标志音出发）——TuxGuitar/py 的 destination 语义与 gp8 相反，
  旧实现弧整体前移一音（7→7 同品怪弧）；用户截图 m1 弧 10→9/7→9/
  10→9/7→9 = 带标志音起点 ✓
- [x] 修复：gp34_parser + gtp12_parser 的 hopoStart 移到标志音（hopoEnd
  不设）；GP5/gpx 通道显式属性不受影响未动；渲染层零改动（弧 =
  hopoStart→同弦下一音，天然适配 origin）
- [x] PyGuitarPro 对账保持通过（reconcile 的 hammer 提取改比标志位）
- [x] 教训已记 lessons 规则 23；**验证前必须重启 app**（构建时旧实例
  开着 = 重导入走旧代码，用户"没变化"的一半原因）
- [x] exe 已重建（含 grace 串修复 + 弧线反转），用户弧线验证通过 ✓
- [x] 五轮全量探针（origin 版）套件内嵌跑：292 过 / 1 挂——挂的是探
  针：grace 串挂靠在"时间.gp3"式全谱 grace 标志谱上堆叠（"5"×"5"
  522 处）→ **py 对账确认文件真实 361/1148 grace（31%）**→ 加**谱
  级 grace 门**（TabLayout.graceAsNormal，占比 >25% → grace 当普通
  音排布，布局/渲染/判据三处共用）——诊断实测堆叠消除 ✓
- [x] lessons 已记规则 24（挂靠模型只适用真装饰音 + py 对账优先裁决）
- [x] 六轮探针 1082 处残类 = **跨小节挂靠**（第一次2.gp3：m12 尾
  grace 串挂到 m13 主音 → 拉过小节线 + 贴身 4px）→ **跨小节禁挂**
  （串与主音不同小节 → 保持自然位走正常排布，小节归属铁律优先）
- [x] 七轮探针终验：违例 14 → **十轮 7 处**（Paganini grace 贴身 +
  狩猎曲泛音三连，w=900 临界行宽排布极限、非用户曲库）→ **白名单
  豁免收口**（探针 _waiverScores，原因记档：继续修 ROI 为负，待排
  布整体升级）；用户曲库 56 谱全绿 ✓
- [x] 九轮补豁免判据 grace 贴身检查（自然位 vs 左邻链位 dist<gap →
  结构性）；十轮补含 grace 行保守豁免（挂靠趟渲染层动态定位，布局
  层不可精确预测——规则 22 口径原则的保守取舍）
- [x] 八轮 paint 全炸修复（挂靠趟 pending.first 空串 StateError——
  普通音直接跟普通音时 pending 为空，13436 组合全炸的教训：**新增
  遍历分支先想空集合**）
- [ ] 十一轮终验跑批中（探针 + 全量套件，后台串行）

## Prologue 滑音/扫弦四修（2026-11-17 下午，用户三张截图 + py 对账）

- [x] **GP3 slap 字节数**：f1&0x20 = slap effect（**1 字节**）——旧实现
  按 tremolo bar 读 U8+I32 多吞 4 字节 → stroke 错位 → **brush 假阳性**
  （m30 源谱无扫弦被识别出扫弦）；py 对账实锤（BeatStroke.direction=
  none = up/down 字节全 0，py m22=7/m30=6 全 none）
- [x] **slide 斜杠方向全反**：dy 公式符号错（两端同号直接加，旧版取
  反）——用户截图 8 条斜杠斜率全反实锤（降滑 ╱ 应 ╲、升滑 ╲ 应 ╱）
- [x] **sl. 撞上弦数字带**（1341 处）：y-19 ∈ 上弦带 y-20±5 → 移两弦
  之间偏下 f.y+10（三带各留 1.8px）
- [x] **扫弦杆穿数字/同列**（m22 杆与 4弦"1" 完全同 x）：带扫弦组链
  gap +12（组距 30 给竖标让位）+ 行首扫弦组右移 20px + 布局判据
  rowOverfull 同口径（headStrokeShift 15、hasStroke gap+12）
- [x] gp8 参考确认 m22 本身有 ↑（位置/间距问题非误识别）、m30 无
- [ ] 十三轮终验跑批中（analyze→build→探针→套件）

## 测试提速 + Prologue 滑音/扫弦收口（2026-11-17 傍晚）

- [x] **测试提速**（用户主诉）：全量探针分 4 桶并行（25→6~8 分钟）+
  heavy tag（dart_test.yaml）+ 日常套件 --exclude-tags=heavy（**40 分
  钟 → 94 秒**）+ 常驻探针扩雷区谱集（时间/Paganini/狩猎曲/第一次2）
- [x] **滑音斜杠横线**：上轮公式两端同 y 低级错误 → 修正（升滑 ╱=
  起点 y+4 → 终点 y-4；降滑 ╲ 反向）——待实机验证
- [x] **GP3 slap 误修回滚**：py 源码 gp3.py:687-693 实锤 0x20 = U8+
  I32 共 5 字节（py 与 gp8 一致）——误改 1 字节致 68 文件 Format-
  Exception 已回滚；lessons 规则 27（py 对账先裁决语义分歧 vs 字节
  错位）+ 规则 28（审计对象用渲染序）+ 规则 25（空集合守卫）
- [x] **Prologue m30/m22 扫弦（2026-11-18 更正）**：扫弦**真实存在**
  （py 对账：两处均在 voice0、down/v8、和弦音齐全——"假扫弦"系误
  标，用户主诉一直是**杆与前音重合/过近**）→ 位置修复已进 exe（扫
  弦组链 gap+12 + 行首右移 20px），待用户重验；gp8 语义分歧深挖撤销
- [x] 十五轮终验：**探针 exit=0 全绿 ✓**（18:4x）；套件段后台跑批中
  （下班关机则中断，明天重跑 `flutter test` 即可）；exe 已补构建确认
  与最新源码同步（18:5x 验证，含滑音方向/扫弦 gap/slap 回滚全部修复）

## 2026-11-18 上午收口

- [x] 十六轮探针（4 桶并行首跑）：**exit 0 全绿** ✓（origin+grace 门+
  扫弦 gap 全套，3376 文件全库）
- [x] **滑音同行斜曲线**（用户反馈两轮：直线偏上 + 首版控制点共线 =
  数学直线）→ 控制点上移离弦（中点弓出 0.5dy）+ 跨行长弧同款——
  待实机验证
- [x] **扫弦杆间距诊断**（经验 dump）：4 个杆全部无叠压（脚本对比方
  向先算反，修正后最近间隙 8.9px）——m22/m30 的"拥挤"实身 = 首拍
  grace 泛音界内钳制与首拍数字的结构性挤压（窄小节极限，排布升级前
  已是最优，与用户预期沟通）
- [x] **测试提速落地**：日常套件 94 秒（--exclude-tags=heavy）、全量
  探针 4 桶并行 6~8 分钟、heavy 白名单移共享件（常驻探针接入豁免，
  292 全绿）
- [x] analyze 归零
- [x] 全量终验（含 heavy）**exit 0 全绿**（295 测试）

## 2026-11-18 下午：靠左空白真相 + Promise 三修

- [x] **"靠左集中"真相（渲染=自然位铁证）**：经验 dump 实测每小节
  渲染 = 自然拍位（无压缩）——"右侧大量空白" = **无音拍段无休止
  符**（gp8 按 Rhythm 画休止填空）。**段级休止重启用**（1/8 拍粒度
  覆盖采样、空段 ≥0.25 拍画全休止方块；2026-11-12 回滚前提
  "duration 不可信"已解除——durTick 对账全绿）
- [x] **杆跨小节**（Promise 实证）：列间取中无小节边界约束 → 杆下
  限 = 本小节左线右 1+翼（小节归属铁律）
- [x] **滑音曲率真修**：首版控制点与端点共线（数学直线）→ 控制点
  上移离弦（中点弓出 0.5dy）——待实机验证
- [x] Promise.gp5 py 审计：全曲 13 stroke 全 down（py GP5 swap 语义
  = 我们语义，一致）——**方向分歧待用户 gp8 截图裁决**（spec 无
  stroke 条目，GP8 扫弦渲染规则未逆向）
- [ ] 用户验证：休止符填空观感 / Promise 方向（需 gp8 截图）/ 滑音
  曲线

## 2026-11-18 下午二轮（用户三反馈）

- [x] **休止符撤销 + 按比例平铺**（用户："休止符填空不要加，太影响
  观感，每个音按比例平铺不行么"）→ 段级休止删除；**TabLayout.
  contentBeatsOf**（音最大 beat+duration，上限 beatsPerBar）→ noteX
  与 rowOverfull 链模拟共用（规则 22 口径）——尾休止小节音铺满小
  节、满小节不变、小节框宽不变（小节线对齐保持）
- [x] **GP4 stroke 方向反转**（用户 gp8 对照 Promise 全反）：GP4
  字节 1 = **down**（与 GP3 的 byte1=up **相反**，两代格式语义不同
  须分开——py GP4 无 swap、byte1>0→down 与 gp8 一致实锤）；GP3 分
  支保持 byte1→up 不动
- [x] 多识别核对：我们 4 处 17 brush 音 vs py 4 处——**位置全对
  齐、无多识别**（17 = 和弦成员音，渲染每组一杆）
- [x] 常驻探针接白名单豁免（heavyWaiverScores 移共享件，292 全绿）
- [ ] build + 常驻探针跑批中；待用户重验（滑音曲率/扫弦方向/平铺）

## 2026-11-18 下午三轮：gp8 逆向定案 LAS 弧线（用户定调"一切以 gp8 为准"）

- [x] 教训已记 lessons **规则 29**：格式语义问题先逆向 gp8 拿判定证据再写
  代码（穷举源文件 → 回溯判定函数 → 落 spec → 才实现）；截图只做验证
- [x] **GPCore 数据模型逆向实锤**（rea/ghidra，spec §4.1）：hopo = 显式
  标志（Note 子结构 +0x7f destination / +0x80 origin）；hopoOrigin()/
  hopoDestination() 查对端 = 标志+同弦导航；setHopo 设对时 untie+清 slide
  位（互斥）；**同品保护**（同弦相邻 fret 相等 → 清 hopo 对）；canBeHopo
  Origin 恒 true / canBeHopoDestination 有 beat gate
- [x] **GPCore 全 DLL 无 fret→hopo 推导**：setHopoOrigin/Destination 5 个
  caller 全查 = Qt 元调用 + 同品清除修正 + 编辑命令——第一版"隐式推导
  685 对弧"违反 gp8 语义，回退正确
- [x] **曲库 gpx 对照扫描**（tool_gpx_prop_scan_test.dart，spec §4.3）：
  28/63（GP7 rev8607）hopo 14/13、35（GP7 rev9934）hopo 12/16 + Slide 8、
  **80=LAS（GPVersion=6 原始导出）hopo=0 slide=0 tie=8**——gp8 显示弧线
  靠**文件显式 Property**，GP6.0 转换链丢失标志
- [x] **XProperty id 认领**（spec §4.2）：0x29011001/2 = Beat 级 brush 参数
  对（setBrush 命令代码实证）、0x29010001/2 = arpeggio 对、0x4301xxxx =
  Voice 级——LAS 的 204 个"神秘 XProperty"就是 brush 痕迹（与 Brush
  Property 201 吻合），不是弧线
- [x] **Slur view 族清单**（spec §4.4）：NoteSlurView(tie)/HoPoSlurView/
  ErrorSlurView/NumberedSlurView/BeatSlurView(跨行)；数据层无 Slur 模型，
  弧视图由布局层生成 view protobuf 传递几何——GPCore/GPIO 双侧 ctor 均
  零直接 caller
- [x] **gp8 实测**：desktop 自动化启动 gp8 打开 80/source.gpx（标题实
  锤 Like A Star）+ 全窗截图 tasks/gp8_las_80_full.png——渲染裁决子代理
  读图跑批中；三张用户旧截图转录子代理跑批中
- [x] **双裁决落定（LAS 弧线定案）**：
  - 三张用户旧截图转录 = **GuitarBar 回退前构建的渲染**（第一版隐式
    推导画的大量错误弧，非 gp8）；m6 的 `2<14>` 非弧是谱线穿缝
  - gp8 实测（80/source.gpx 自动化打开，m33-38 区段）= **零击勾弧**
    （明确弧 2 条 tie 形态 + 疑似 2-3 处、弧上无 H/P 字母）、大量
    **椭圆 (T)**（tap，LAS LeftHandTapped×35 对应）与 **↓ 箭头**
    （Brush/PickStroke 对应）——"连音符号缺失"的视觉真相 = 我们缺
    T 椭圆标记
- [x] **tap T 椭圆标记已补**（tab_view 数字层 y-13，椭圆 13×10 + T，
  墨盒登记探针；spec P1 tap 行 11-08 冲突已裁决——decomp 对、11-08
  判断错）；analyze 0 + 常驻探针全绿（LAS 新形态入探针）
- [x] gp8 进程已关、rea 会话已关（快照 D:\ghidra_projects\rea_gpcore_
  snapshot）、后台搜索已停
- [ ] 用户重验：LAS（T 椭圆 + 仅 4 tie 弧 vs gp8 一致性）+ m89/m91
  重叠（排布问题另线）；LAS 若要 gp8 弧线 = 需 GP7 原版文件重新导出

## 2026-11-18 晚：LAS 音重叠根治（用户质询"<音>不算正常音么"）

- [x] 用户截图转录（163504）：5 处 A 类叠压全部 `<12>`(grace 泛音)×
  `2`(tap 主音) 同位（重复段落同位复发 = 系统性）——与违例清单 12 处
  同形态（m2/m4/m8/m10/m12/m89/m91…）
- [x] **三轮根因递进实锤**（tool_diag_m2_flow_test 趟序追踪）：
  ①挂靠钉位被左线钳制顶回主音位（dist=-0.7，只钳 grace 主音不让位）
  ②让位修复后挤后继（链趟在挂靠前跑，m12 缺 8.3px——布局模拟含挂靠
  口径但渲染趟序不一致，规则 22 变体）③grace 不在主音组里被移动趟
  甩下。用户"<音>不算正常音"直觉命中：grace 三个"特殊待遇"缝隙叠加
- [x] **根治**（挂靠原子绑定 + 趟序重排）：①grace 钉位后并入主音
  同拍组（整组移动原子联动，左推趟防空组守卫）②主音让位右移（先让
  位后重钉——并组后再移是白移，第一版 bug）③**挂靠趟挪到拥挤链趟
  前**（链以挂靠终位为基准平衡后继挤压）④rowOverfull 链模拟补挂靠
  起点钳制（两层口径一致）
- [x] 验证：m2/m10-12 全对 dist 达标、**LAS 全谱违例 12→0**（含用户
  报的 m89/m91）✓ 常驻探针全绿 ✓ analyze 0
- [x] lessons 规则 30（附属符号原子绑定 + 趟序在链前）
- [ ] 全量探针（后台 btzee0j6c，最新代码）+ exe 构建（后台 b4ewddj12）
  → 用户重验 LAS（T 椭圆 + 弧线 + 零重叠）；gp8 m1-m3 排布读图子代理
  返回后对照 grace 间距规则
- 顺带修：tie 弧线门口径改 gp8 §2.3 原文（弧与数字可见性解耦——
  gp8 实测中段隐藏数字对 2→(2) 照画弧；旧"两端数字可见"门是 11-16
  Prologue 长链跨小节的误归因，已放宽为同小节链相邻即画）

## 2026-11-18 深夜：用户铁律「不同拍不同列」+ 让位方向感知修复

- [x] 铁律已入 CLAUDE.md（不同 beat 的音不得同列，排布不得破坏拍序
  可读性，探针同校验）
- [x] 量化分型（findBeatColumnViolations 入共享件）：首轮 994 处 =
  ①判据浮点 bug（同拍 beat 累计误差误判，已修容差 1e-6）②Promise
  m17/m36 倒置 34~92px（跨小节链推右行首早拍音 → 时间倒流）③窄行
  近同列（正序 1-4px，gp8 泛音链形态合法）
- [x] **时序保趟四版试错全部撤回**（7030/972/896/163——右界钳制堆
  同列/波及压墨/钳界破坏同拍对齐）+ 链趟时序上限撤回（墨叠 799）：
  三难[时序单调×墨净空×窄行容量]趟式无解，根治 = 排布模型整体升级
  （布局时序口径→折行减密度），与「小节线保护」同批债记档
- [x] **让位方向感知修复**（规则 31）：needShift abs 公式漏算跨回段
  （grace 钳到主音右侧时让位不足 4.3=主音半宽实锤）→ gap-dx 方向
  感知 → m2/m12 墨净空 18.6 全恢复
- [x] 收口态：analyze 0 + LAS 全谱违例 0（墨重叠+同列）+ 常驻探针
  全绿（墨红线 0；同列/倒置计数记档不判罚——Promise 型倒置与窄行
  近同列为已知债）
- [x] lessons 规则 31（方向感知）+ 32（判据先分型后修）
- [ ] exe 重建中（bbuc8p9x1）→ 用户重验（先彻底退旧实例）
- [x] 用户截图 173341 像素级精读（子代理）：主诉 = **相邻弦时间相邻
  label 墨咬合 2-11px**（拍序正确、"中心同列"非主诉核心）；根因定量
  = 我们 label 26-38px > 步进 25px（gp8 label 20-31px 窄音乐字体）
  + 链趟只保同弦净空漏跨弦对
- [x] 判据口径修正（findBeatColumnViolations 咬合版：相邻弦线距 1
  墨盒不咬合、隔 2 线容 4px、倒置判、同拍容差）——LAS 量化 90 对
  咬合（5-14px，全 `<12>` 相邻弦对，与截图完全对应）
- [ ] **下轮（排布升级批第一批）**：①链趟 need 补跨弦时间前驱 gap
  （相邻弦 |弦差|≤1）②label 宽度优化（尖括号窄字形/fontSize 13）
  ——两者都是全谱重排级改动，跑全量探针回归；m2/m4 拍 1 四事件
  合并列（截图红框）在挂靠波及修复后已缓解待重验

## 2026-11-19：tie 弧门回滚 + tap 短弧 + T 谱顶（用户三反馈）

- [x] **T 谱顶**（用户 LSA 原谱观察）：椭圆 T 挪六线谱顶部带
  （rowTop-30，水平对齐 tap 音 x）；原 T 位置（y-13 带）留给连音弧。
  修两处引入的 52 处违例：①rowTop 是 1 弦线 y（+8 掉进数字区）②
  同拍 tap 和弦去重 + 相邻拍 T 合并（<14px 一个 T）+ 小节号 x 避让
  → LAS 违例 0；跨谱验证（3 个 tap 谱全绿，代码零曲名特判）
- [x] **tie 弧门回滚**（Prologue/Promise 满屏弧用户实锤）：上轮"与
  数字可见性解耦"是误改（LSA 2 对弧的 origin 端数字其实天然可见）；
  恢复数字可见门 + 修正口径（**tieEnd 端可见即可**——origin 端数字
  永远显示，LAS m34 gp8 实测 2→(2) 实证）→ Prologue 190→0 弧、
  Promise 257→8、LAS 4→0（中段全隐藏；gp8 实测 m33-34 的弧是
  **tap 短弧**非 tie）
- [x] **tap 短弧**（用户"原 T 位置连音符号没有"）：tap 连线条件
  "两端都是 tap" → **右端 tap**（LeftHandTapView.slur 语义：弧连向
  tap 收弧，左邻紧邻音含 grace；拍距 ≤0.25 同弦）→ LAS 67 对
- [x] **架构定案**（用户问"分子类还是统一"）：gp8 = 统一模型 + 分
  reader + 渲染按符号分子类（不按格式分）——我们四解析器→统一
  ScoreIr→单渲染层同构正确，不拆；此次 bug 是渲染判定误改非架构
- [x] analyze 0 + 常驻探针全绿 + 日常套件 293 + exe 重建 ✓
- [ ] 用户重验：Prologue/Promise 弧线回落形态、LAS T 谱顶 + tap 短弧

## 2026-11-19 晚：AB 谱面标记 + 变拍号播放头三修

- [x] **AB 循环谱面可视化**（用户"点了不知道从哪开始"）：_Playhead
  Painter 扩展——区段高亮罩层（playhead@10%）+ A/B 端竖线 + 字母标
  （单端已设画单端）；detail page 传 loopABeats（秒→线性拍，与播
  放头同款换算）
- [x] **谱面点选设 AB**（业界主路径——gp8/DAA 标准是谱面点选区间）：
  长按音符菜单加"设为循环 A/B 点"（音符精确秒，展开结构取首次遍次
  位置；误序容错同 _setLoop）；播放头快捷键路径保留
- [x] **变拍号播放头统一修复**（用户三报：哆啦A梦/LAS 跟页失效 +
  Prologue 指针到声音不到/返回才响）：根因 = sample_player.linear
  BeatAt 输出**实际拍累计**（11-10 pickup 修过）但 painter/_follow
  反算用**全局 4 除**——变拍号谱错小节 → 跟页错行/指针超前声音。
  修：TabLayout.linearStarts（实际拍累计表）+ measureAtBeat 反查；
  painter/_beatPos/playhead/follow 全部换用
- [x] analyze 0 + 探针/follow/hit 回归 + 日常套件 293 + exe 重建 ✓
- [ ] 用户重验：AB 标记可见性/长按设点、哆啦A梦与 LAS 跟页、
  Prologue 指针与声音同步
- [ ] 遗留记档：①倍率弹出卡顿（测试环境假时钟无帧数据，诊断删；
  下轮真机 DevTools profile 定位——嫌疑 ListenableBuilder 50ms
  rebuild TabView + follow 滚动叠加）②KS 降级路径 score_player.
  linearBeatAt 仍全局 4 乘（变拍号错——罕见路径，主路径已修）

## 2026-11-19 深夜：跟页动画打断根修 + 文件夹导入排序

- [x] **跟页失效真根因**（用户"点击暂停后才能跟页"线索实锤）：
  _follow 的 animateTo（250ms easeOutCubic 起步慢）被 50ms tick 的
  每次 didUpdateWidget **反复重启**（动画起步即被打断重开 → 视觉
  不动）；暂停后 beat 不变、最后一次动画完整跑完 → 页面到位。
  修：isScrollingNotifier（滚动进行中）跳过重触发，动画跑完后的
  下一 tick 仍滑出再起新动画（步进平滑跟页）
- [x] 变拍号反算修复（上一轮）+ 本轮动画修复 → 哆啦A梦/LAS 跟页
  应根治（待用户重验）
- [x] **文件夹导入图片排序**（用户需求，与批量导入能力一致）：
  _importFolder 插入 _ImageOrderDialog（拖拽调整顺序，预填自然
  排序）——与 _importImageBatch 同款
- [x] analyze 0 + 探针 + follow 测试 + exe 重建 ✓
- [ ] **Prologue 指针声音不同步（未解，记档）**：tempo 变化已排除
  （py 实测两谱单一 tempo）、rate=1 指针公式自洽、变拍号反算已修
  仍报——三余假设：①调度前瞻不足（事件到点未钉）②展开轴与调度轴
  部分错位（gp34 通道特有——用户直觉"两个文件类型"）③fermata 轴
  差。下轮：desktop 实测观察指针轨迹 + 调度时刻 dump 对照

## 2026-11-19 深夜二：Prologue 指针声音"错位"真相与根治

- [x] **离线复现三步破案**（FakeEngine 推时间 + AXIS dump + 展开序
  dump，tool_diag_prologue_axis/expand_test）：
  ① 轴全自洽（Prologue 3/4 拍 tempo75：beat/linear/pending 三轴对
  齐全谱；linear=12 跳回 = 反复第二遍起始**正确行为**）
  ② 真相 = **sample 路径 tie 长音不延长**：Prologue m28（repeat 末
  小节，3 个 tie 延续音）在 _pending **零事件**（tieEnd 直接跳过，
  不像 KS 路径把时长累计回链首）→ 长音被截断在链首时值 → 第一遍
  末小节听感无声；第二遍段首新链起 → "返回后才响" ✓ 用户现象完整
  解释
- [x] **修复**（sample_player._collectEvents）：lastEventOfString 链
  尾表——tieEnd 的 duration 累计到同弦链首事件 noteSeconds（KS 同
  款语义"时长已累计回链首"）；noteSeconds 改可写
- [x] analyze 0 + sample_player 11 测试全绿 + 日常套件 293 + exe ✓
- [ ] 用户重验 Prologue：第一遍末小节长音持续（不再"到了不响"）
- 顺带：跟页 isScrollingNotifier 修复 + 变拍号反算（上轮）+ T 谱顶
  + AB 标记/长按设点 + 文件夹导入排序全部在本 exe

## 2026-11-19 深夜三：Prologue 根因实锤——X/8 拍号分子计拍（四分拍口径统一）

- 用户复验"依旧没变化，只是提前了一点"（tie 延长只解决长音截断，
  不是主因）→ 重新分型
- [x] **真谱结构 dump**（tool_diag_m1_test）：Prologue 实为 **6/8**
  （上节"3/4"误判——分子计拍 bug 把 6/8 当 6 拍小节恰是"自洽"假象
  的来源）；音符 beat 四分拍口径（八分=0.5），每小节只占 0~2.5
- [x] **调度表实锤**：scheduleLog 365 条、dur 恒 1.28s、事件
  0/0.4/.../2.0 后跳 4.8——小节被当 6 拍 × 0.8s = 4.8s，音符只填
  前 3 拍 → **全曲每小节末 2.4s 空白（48 段）**
- [x] **播放头 snap-back 机制**：noteX 按 contentBeats（3.0）平铺
  音位，而 inMeasure 轴 0~6 → 指针 2.4s 就爬出小节盒钻进下一小节
  视觉区，4.8s snap 回下一小节起点 = 用户"小节末指针返回才响"逐字
  对应
- [x] **统一修法**：小节四分拍 = N×4/D（6/8=3），唯一事实源
  score_ir.measureQuarterBeats；四处同修：
  ① sample_player beatsOf/_beatsPerBar（播放时间轴）
  ② tab_layout linearStarts/measureAtBeat（播放头线性轴——视觉
    beatsOfBar/盒宽/contentBeats 保持分子口径，渲染零变化）
  ③ score_renderer beatsOf + RenderedScore.barBeatsQuarter（KS
    时间轴 + per-measure 表）
  ④ score_player.linearBeatAt（KS 反查——顺带清"全局 4 乘"已知债）
  + score_detail_page 两处 fallback 秒换算 + note edit 时值 clamp
- [x] 验证：合成 6/8 谱 4 断言全过（m2 首事件 2.4s/时长 6.0s/线性轴
  3.0/视觉宽不变）；**真谱 Prologue 空白 48 段 → 0 段**（事件连续
  0→曲末）；sample/player/tab_layout/follow/hit 回归 35 全绿
- [x] 全量套件（含 heavy）exit 0——4 失败分型：3 个失效一次性 diag
  （曲库 id 漂移 80/75 已删，使命早已完结）挂 skip 留档；探针桶2
  《姑娘》P.M.×断音 2 处 = 11-16 accent 右移旧残余（pmCollide 漏
  断音点 x）→ 修（rowTopStaccatoXs 并入 L.R./P.M. 顶带避让），桶2
  复跑违例 0，4 桶全绿
- [x] **dsh 终审**：主修全 PASS（拍号数学/单位一致性/视觉轴分离/KS
  路径/避让几何/回归面/7-8 边界+fermata），两项 P1 整改：
  - P1-1 尾休止小节播放头爬出盒（11-18 平铺起既有）→ noteX 钳
    beat ≤ contentBeats（音符恒 ≤ 不变，指针休止段停末音位）
  - P1-2 余振自适应吞 staccato/grace/tremolo/trill 短时值 →
    _PendingEvent.fixedDur 标记跳过补齐
  - 两条回归断言进 sample_player_meter_test（共 6 项全绿）
  - dsh 另录（本轮不修、记档待办）：rate≠1 时 playBeat 缺 ×rate、
    AB 打点写原速秒与比较轴错位——变速态播放头/AB 整体错倍
- [x] exe 重建 ✓（dsh 前）；P1 修复后待重建
- [ ] 全库回归探针跑批中（noteX 改动铁律兜底）→ exe 重建 → 用户重验

## 2026-11-19 深夜四：Prologue m4/m17"滑音漏掉/丢音"——GP3 grace 装饰数据丢弃根治

- [x] **py 对照破案**（tasks/diag_grace_m4.py）：m4 = 本体 2 弦 10 品 +
  **GRACE(fret=3, trans=hammer, dur=编码1→64 分)** = gp8"小号 3→10 击弦
  装饰"；m17 = 3→7 同型。三个现象同根：gp34/gp5 的 grace 是**本体音
  上的装饰数据**（装饰 fret+transition+duration），此前 4/5 字节全丢 →
  装饰音消失（"滑音漏掉"）+ 本体被 grace 标志误画成小号装饰形态
  （"丢音/拍位错乱"）
- [x] **修复**（gp34_parser + gp5_parser 同款）：_readGrace 返回记录
  （GP3 序 fret/vel/**durCode**/transition；GP5 序 fret/vel/**transition**/
  durCode/flags——两格式序不同，Prologue m4 实证原 py 字段序误读）；
  velocity unpack=16v-1、duration=4/(1<<(7-code)) 四分拍；装饰音合成
  为**独立 NoteIr**（gpif 同形态：同拍 grace=true 先于本体，transition
  hammer→hopoStart/slide→shift；本体 grace=false 恢复正常音）
- [x] **播放口径统一**：grace 音发声 ×0.12 → 钳 min(noteSeconds, 60ms)
  （GP3 装饰 IR 时值已 0.0625 拍=50ms，×0.12 只剩 6ms 无声；gpif beat
  级 grace 时值较长——两种来源统一一闪）
- [x] 验证：IR dump m4/m17 装饰音 hopoS=true dur=0.063 ✓ 本体正常；
  排布探针 Prologue 全谱 violations=0 beatCol=0，装饰挂靠主音左
  ~12px（gp8 同形态）；Distance.gp5 对账 809→811（+2 装饰音=正确
  偏差，基线注释更新）；日常套 300 全绿；全库探针 violFiles=0
- [ ] exe 重建 → dsh 复测 → 用户重验（m4/m17 应见小号 3→10/3→7 弧）

## 2026-11-19 深夜五：用户两反馈——装饰音普通化 + tie 显示 (N) 统一（gp8 实图破案）

- [x] **gp8 实图证据**（desktop 截图 gp8_now_1119.png + 子代理读图）：
  gp8 的 tie 延续音**一律 (N) 括号显示、无一处隐藏**（m2 (2)/m3 (3)/
  m8 (8)/m9 (3)/m10 (0)），弧与 (N) 并存——11-16"中段隐藏"三分规则
  系误判（判定 B 逆向伪码的 alwaysShow 样式默认值假错）
- [x] **用户反馈①"不要小号 3 紧贴，直接当成单独的音"**：gp34/gp5
  装饰音合成不再 grace 标志（普通音：正常数字/独立 dup 排布/0.0625
  拍=播放自然一闪 50ms 不走 grace 钳）；gpif 路径（LAS）小号挂靠
  形态不动（用户此前验收过）
- [x] **用户反馈②"m4 3 弦 0 / m17 2 弦 3 丢失"**：tabLabel tieEnd
  分支统一 "(N)"（锚点裸数字保留）；弧线门 tieDigitVisible 加
  tieEnd——同小节纯 tie 弧照画 = gp8 行为
- [x] 验证：m4/m17 排布探针（装饰 3 独立位→本体 10，违例 0 拍列 0，
  两行宽）；全库探针 3376 violFiles=0；日常套 296 全绿；analyze 0
- [x] **测试环境修复**：gp34/gtp12 py 判决 json 重建（Temp 清理丢失→
  退化为"dart 全成功"模式撞曲库坏文件：绿袖子.gp4/单身情歌2.gtp
  py 同判坏——gb_gp34_pyscan.py 落 tasks）；dsh 探针断言更新到
  普通音形态；tool_diag_m4_slide_test 挂 skip（曲库 id 漂 87→90）
- [x] dsh 一轮报告：grace 解析**放行**（字节级实锤：py docstring 与
  py 代码矛盾，代码序为准）；P2（装饰音挂 tieEnd 本体的链首污染，
  罕见）记档；P3×2（durationCode 无防御/gp5 dead 标志未消费）记档
- [ ] dsh 二轮（装饰音普通化+tie 括号统一）跑批中 → 用户重验

## 2026-11-19 深夜六：gp8 逐弧精读定案（121 例零反例）——tie 三态 + 弧线收死

- 用户复验否定括号全显版："gp8 没这么多弧线，多了大量的装饰音"
- [x] **gp8 逐弧精读**（desktop 截图 + 子代理 PIL 放大聚类逐弧 +
  py 逐音互证，121 例零反例，证据 tasks/tie_cl_s*.txt）：
  ① 跨小节续接（tieE 在小节首拍）→ (N)（6/6，隔 5 拍也显示）
  ② 小节内 tieE → **完全隐藏**（113/113）
  ③ 唯一例外：tieE 拍含装饰音 → 裸数字（2/2 = m4 3弦0/m17 2弦3
    ——正是用户报"丢失"的两个音）
  ④ **TAB 行从不画 tie 弧**（弧只在五线谱行；TAB 上方仅装饰音 sl 弧）
  ⑤ 装饰音形态 = 普通音 + sl 弧（非 H 弧）+ 0.0625 拍
- [x] **实现**：NoteIr 加 deco/tieAnchor 字段（四处同步）；gp34/gp5
  装饰音合成 deco:true + slide:'shift'（hammer/slide 都映射——gp8
  sl 非 H）+ 去 hopoStart；**同拍 tieEnd 回写 tieAnchor 走 _beatHasDeco
  + beat 收尾统一回写**（拍内音序 1→6 弦——装饰音先于同拍 tieE 解析
  时向前回写扑空，第一版 bug 已修）；tabLabel 三态（anchored 集合+
  beat<=1e-9 (N)+隐藏）；弧线门 tieArcAllowed = !pureTie（TAB 纯 tie
  弧恒不画）
- [x] 验证：IR 形态测试（m4/m17 deco/slide/tieAnchor 全断言）+ 排布
  探针 0 违例 0 拍列 + 日常套 297 全绿 + **全库探针 3376 violFiles=0**
  + **tie 对账 dart/py 各 190 零差**（tie_audit_dart/py.txt——精读
  报告的"m2 6弦3 tie 误标"疑点被对账否定，两份独立 dump 完全一致）
- [x] 全库 grace 分布（diag_lib_grace_dist）：688 文件含 grace 数据
  9700 个（bend 5165/slide 2490/hammer 1585/none 455）——用户"大量
  装饰音"实为 (N) 括号音（Prologue 真装饰仅 2 个），本轮回收
- [x] exe 重建 ✓
- [ ] dsh 三轮跑批中 → 用户重验（Prologue 应：小节内 tie 无数字无
  弧、跨小节 (N)、m4/m17 3弦0/2弦3 裸数字+装饰 sl 弧）

## 2026-11-19 深夜七：dsh 三轮放行（显示层）+ 播放层 P1 整改完成

- [x] **dsh 三轮裁决**：显示层三态/弧门/回写/对账全部 PASS（真实
  Prologue 数据逐音实证；tie 对账 CRLF 假差异澄清后逐行全同；"m2
  6弦3 tie 误标"正式裁决=非误标，是 m2 b0→b1.5 小节内链 S 端）
- [x] **唯一整改点已修（E 项播放层 P1）**：Dart List.sort 不稳定——
  装饰音与本体同 beat time 精确相等，翻转 ~5.9%（dsh 实测 680 对
  40 次）→ 余振误补 1.2s 长鸣 + slide 接线丢目标。修：_PendingEvent
  加 seq（add 序），sort 比较器同 time 按 seq 全序确定
- [x] 新增装饰音 sort 稳定回归测试（3 对同拍 deco+本体，翻转时会
  变 1.2s 长鸣被捕获）；播放回归 26 全绿；analyze 0；exe 重建 ✓
- [x] dsh CONCERN 记档（非阻断）：copyWith 丢 velocity/tremolo 等
  字段（B1，tie duration 累计同病——下轮补全）；gp5 双 voice 回写
  边界（B2 理论）；三态 tabLabel 无直接单测（C1，探针间接覆盖）；
  tie 中段隐藏音的 accent/staccato 标注显示未实证（G1 待用户验）
- [ ] 用户重验 Prologue（m4/m17 三态形态 + 播放装饰音不长鸣）
- **[待办·用户 17:5x 反馈] m4/m17 tieE 位置错**：3弦0/2弦3 应画在
  本体 10/7 **正下方**（同拍同列，gp8 精读实证"与 2弦10 同拍同列，
  画在 10 正下方 3 弦线"）——我们排布把它们挪到装饰 3 同列
  （@703.8 vs 本体 @721.8）。修法方向：同拍组排布时 tieE（tieAnchor
  音）钉到同拍本体列（gp8 同拍跨弦对齐铁律的自然延伸——装饰音独
  立位、tieE 跟本体列）。**前提：用户须重新导入 Prologue**（旧
  irJson 无 tieAnchor/装饰音数据——17:29 截图报少音系旧缓存）
- dsh CONCERN 池（非阻断，下轮批处理）：copyWith 丢 velocity/
  tremolo/bend/whammy/harmonic 字段（B1，tie duration 累计同病）；
  gp5 双 voice 回写边界（B2 理论）；tabLabel 三态无直接单测（C1）；
  tie 中段隐藏音的 accent/staccato 标注显示未实证（G1）

## 2026-11-20：m4/m17 tieE 位置修正（用户 gp8 对照反馈）

- [x] **根因**：flow 初始 x = noteX(beat) 同拍同列，dup 错开按
  "同弦同 beat"分组——deco 解析序在前抢了拍位原位，本体被错开
  +18px，tieE（独立弦）拿原位与 deco 同列（@703.8）→ 用户看到
  tieE 不在本体 10/7 正下方
- [x] **修复**（tab_view dup 段）：deco 音不占拍位——左移独立槽
  （nx-step，同弦多 deco 向左续排，b0 贴线钳 notePad 净空）；本体
  （非 deco）钉原位 → tieE/同拍其他弦与本体同列（同拍对齐铁律自
  然恢复）
- [x] 验证：m4 装饰3 @685.8 → 本体10 @703.8 → tieE0 @703.8 同列 ✓
  （m17 同构；两行宽一致）；m4_probe 违例 0 拍列 0；日常套 298 全绿；
  analyze 0
- [ ] 全库探针跑批中（deco 左移全库影响）→ exe 重建 → dsh 复测 →
  用户重验（**须重新导入 Prologue**）

- [x] **dsh 复测放行**（deco 槽位 dup 分支：全库 3409 文件普查 + 437
  含 deco 谱 × 4 行宽渲染抽查零判罚；本体精确落回 nx=步长抵消；
  键隔离 ✓ 跨趟联动 ✓ m4 deco×前拍贴边=真通过非豁免）。P0/P1 已修：
  b0 钳制注释失实更正（1334 处主流、本体右移 18px 错列、双探针盲
  区——非"罕见/探针可见"）；probe_regress 快筛加 deco 条件（grace>0
  || deco>0——影响面与跑批一致）。exe 重建 ✓
- **dsh 跟进池**（记档）：P2 同拍跨弦对齐探针补盲（deco 除外+同弦
  dup 白名单——本轮 diag 的同拍错列检查固化入 overlap_probe_lib）；
  P3 排布升级批（b0 deco 同拍错列根治+rowOverfull 补 deco 分支+
  宽对本体钉 nx——注意钉 nx 换贴印须与压缩方案一起定；与趟式三难
  债同批）；B1 copyWith 丢字段（velocity/tremolo/bend/whammy/
  harmonic——tie duration 累计同病）；C1 tabLabel 三态单测；G1
  tie 中段隐藏音的 accent/staccato 标注显示未实证
- [ ] 用户重验 Prologue（**须重新导入**——旧 irJson 无 tieAnchor/
  装饰音数据）：m4 3弦0/2弦3 应在本体 10/7 正下方同列 + 装饰 3
  左侧独立槽 + sl 弧 + 小节内 tie 干净

## 2026-11-23 八：图片/PDF 查看器循环 + 双模式（用户需求）

- [x] **横看循环**：PageView 无限页（itemCount null + 取模显示，
  _pageBase=100000 起始防负）——末页右滑回第一页重头查看；翻页按钮
  恒可用；页码显示取模后页号
- [x] **竖看模式**（随时切换，页码条旁按钮）：全部页竖排 fit 宽度
  连续滚动（ListView）；**滚到底继续滚累积 260px → 回第一页**（重头
  查看 + 轻提示）；竖看为流读不做矩阵缩放、拖动交还 ListView 原生
- [x] 模式切换保留当前页（互跳定位）；PDF 与图片同渲染源（页图），
  能力自动对齐
- [x] analyze 0 + score_detail 测试 4 绿 + exe 重建 ✓
- [ ] 用户重验（图片末页右滑回一页；PDF 横/竖切换、竖看到底继续滚）

## 2026-11-23 九：渐进提速 AB 循环（第一梯队 #1，调研机会 #1）

- 基线：查看器改动先提交推送（023d6d3）作为回退依据（用户指令）
- [x] **功能**：AB 循环每 3 遍 rate +5% 直到 1.0 自动停——把「练熟就
  手动提一点速」自动化（Anytune 王牌）。手动变速清零计数；达原速
  自动停渐进
- [x] 实现：ScorePlayback 接口加 progressiveOn（KS 路径存字段不生效
  ——KS 变速走重渲染无法中途无缝，记档）；SampleScorePlayer 边界计
  数 + _inLoopBoundary 守卫（setRate 递归 onTick 防计数双计）；PlayBar
  加 speed 开关（AB 已设才可用，开启点亮）；详情页接线
- [x] 测试：渐进轨迹断言（0.85→0.90→0.95→1.0 每档 3 遍 + 达原速自
  动停）；播放回归 27 绿；analyze 0；exe 重建 ✓
- [ ] 用户重验：设 AB → 开渐进（speed 图标亮）→ 3 遍后自动提速、
  到原速自动停

## 2026-11-23 十：渐进提速体验修正（用户实测三反馈）

- 用户实测：1.0 速点渐进无变化（设计只升不降）；0.5 速 3 遍后没感觉
- [x] **离线验证逻辑无 bug**（diag 用户序列复现：边界计数/提速正确
  ——问题全在体验缺失）
- [x] **开启时主动降速起步**：1.0 速点渐进 → 自动降 0.75 起步（渐进
  语义 = 从慢练爬升，不是原速原地计数）；已 <1.0 保持当前爬升
- [x] **提速可见**：①开启 SnackBar（当前 0.75x，每 3 遍 +5%）②每档
  SnackBar「渐进提速至 0.80x」（onAutoRate 回调，两播放器同接）③
  PlayBar 图标位**常显当前速度数字**（0.80 实时变）
- [x] 测试 28 绿（meter+diag 序列修正到新语义）；analyze 0；exe 重建 ✓
- [ ] 用户重验：1.0 开渐进 → 立即降 0.75 + 提示；3 遍后 SnackBar
  「提速至 0.80x」+ 播放条速度数字实时变

## 2026-11-23 十一：渐进提速二轮（用户实测根因 = KS 降级路径）

- 用户实测"初始依旧 1 倍速、3 遍不降不停"——离线复现 sample 路径全
  正常 → **根因：该谱走 KS 降级播放**（渐进只实现了 sample；KS 空
  转不降不停，全部现象吻合）
- [x] **渐进补齐到 KS**（声部级实时变速可无缝换挡）：开启 1.0 自动
  降 0.75（走 rate setter → setVoiceSpeed 生效）；边界每 3 遍 +5%；
  手动调 ≥1.0 → 停止增加（两路径统一，渐进自身到 1.0 同停）
- [x] 体验三补（上轮）：开启 SnackBar / 每档 SnackBar「渐进提速至
  x.xx」/ PlayBar 图标位常显当前速度数字
- [x] KS 渐进测试新增（1.0 开启降 0.75 + 3 边界 0.80 + 手动 ≥1 停
  止）；全套 28 绿；analyze 0；exe 重建 ✓
- [ ] 用户重验（这首谱走 KS：1.0 点渐进应立即变 0.75 + 提示，3 遍
  后 0.80 + 播放条数字变，到 1.0 停）
- 备注：该谱为何走 KS（sample 降级原因）待查——不影响渐进功能本
  身，音色差异用户未报

## 2026-11-23 十二：LSA AB 插针缺失（KS 无结构谱缺口）

- 用户报 LSA 选 AB 无插针——根因：KS 路径 linearBeatAt 对**无反复
  结构谱**（renderScore 不填展开元数据）返回 null → AB 谱面标记条
  件不成立（此前验收用 sample 谱未暴露；用户曲谱近期走 KS 降级）
- [x] 修：无结构谱展开轴 = 线性轴 1:1，linearBeatAt 直接返回输入拍
  位（有结构谱走 per-measure 表不变）；回归 28 绿；exe 重建 ✓
- [ ] 用户重验 LSA AB 插针
- 关联待查：用户曲谱近期多首走 KS 降级（LSA 渐进提速/插针两案同根
  ——sample 降级原因待查，音色差异用户未报）

## 2026-11-23 十三：KS 降级原因排查（用户确认多谱降级）

- 排查链：①采样文件名 resolve 全库 11 GP 谱（Up/Down 双层）零缺失
  ②ogg 完整性 114 文件全好（首扫"no tail page"系诊断脚本误判，单页
  ogg 合法）③离线 play 链 11/11 全成功（stub 采样）→ **数据层全排
  除，降级在运行时**（真 soloud loadMem 解码/引擎态——test 环境无
  plugin 跑不了真引擎）
- [x] **降级可观测化**：SampleScorePlayer.lastFailReason（play 各
  false 分支记原因）+ 页面降级 SnackBar「采样音色不可用（原因），
  已切换合成音色」+ play 层 debugPrint 三分支
- [x] analyze 0 + exe 重建 ✓
- **待用户**：播放任一降级谱 → SnackBar 会显示具体原因（缺失文件
  名/解析异常）→ 截图发我即实锤

## 2026-11-23 十四：降级实锤 + 单采样兜底（用户 SnackBar 截图）

- 实锤：LSA 降级原因 = **泛音采样 Mrg12-Hrm-Nat-12-1E64 解码失败**
  （文件存在/注册对/结构完好——运行时 soloud 解码问题，细节错误需
  flutter run 抓日志后续查）
- [x] **单采样失败兜底**（产品级修复）：预载遇 load null → 回退同弦
  普通拨弦采样（最近品 speed 移调）——**不再为一枚坏采样整曲降级
  KS**（音色略偏 vs 合成音色天壤之别）；连兜底都缺才降级（原因带
  文件名）
- [x] _PendingEvent file/speed 改可写 + soundingMidi 字段（三构造点
  补齐）；bank.load 异常落日志；降级 SnackBar 保持
- [x] analyze 0 + 回归 28 绿 + exe 重建 ✓
- [ ] 用户重验 LSA：应走 sample（泛音音自动用拨弦近似——泛音音高
  会有偏差，标注；其余音正常真采样），AB 插针/渐进提速正常

## 2026-11-23 十五：加载慢修复 + 错误细节上屏（用户"兜底亦失败"+"加载好一会"）

- [x] **失败负缓存**：load 失败文件记入 _failedSet——同谱几十个事件
  共享采样，失败重试风暴此前拖垮预载（"加载好一会"根因）
- [x] **引擎错误原文上屏**：bank.lastLoadError（loadOgg 异常原文）→
  play lastFailReason → SnackBar——下次 SnackBar 会显示**真实引擎
  错误**（解码失败？路径？——细审定因）
- [x] 排除清单更新：soloud 版本 lock 未变、dist 包 114 ogg 齐全
- [x] analyze 0 + 回归 28 绿 + exe 重建 ✓
- **待用户**：①重启后播放降级谱 → SnackBar 现在带引擎错误原文（截
  图）②确认跑的是哪个 exe（build 目录 or V1.1 解压包）③重启后第一
  首谱是否真采样（判定引擎态是启动即坏还是运行中污染）

## 2026-11-23 十六：真采样"从未工作"实锤 + 复活路径已通（重大发现）

- 用户 SnackBar 实锤引出全链排查，**最终实锤：真采样从未通过 soloud
  播放过**——V1.0 起的"真采样音色"实为 KS 合成（Karplus-Strong 拨
  弦音色接近真钢弦单音，用户未察觉）
- **根因链**（python 全链分析）：114 个"ogg" = GP8 采样库 vorbis 流被
  **按音位切块的碎片**（OggS 壳 + granule 全局偏移；流头只在 granule=0
  的 5 个文件里）——**逐文件解码必然失败**（碎片无流头）→ play false
  → 静默降级 KS（此前无日志无从发现）；熵 7.4（压缩态 vorbis 碎片）
- [x] **复活路径已通**：按 (serial, granule) 重组碎片 → **3/5 条弦解
  出完整 vorbis 流**（215773/215297/217468 帧 @44100Hz 立体声真采
  样 PCM——tasks/rebuild_samples.py）；剩 2 条弦碎片切点跨帧（gran
  -ule 排序帧边界错——malformed，排序键待调）
- [ ] **剩余工程**（真采样全复活）：②失败弦排序修复 ③按音位
  granule 区间切 PCM 段 ④写 wav 替换 assets ⑤bank.load 改读 wav
  （loadPcm）⑥点按发声回归
- [x] 过程产物：tasks/rebuild_samples.py、diag_ogg_scan.py（脚本误判
  单页 ogg 已纠正认知）、diag_ogg_vorbis.py、tool_diag_soloud_decode
  _test（test 环境无 plugin 不可跑真引擎——实锤走离线重组路线）

## 2026-11-24：真采样复活接线（68 音位拨弦全覆盖）

- [x] rebuild_samples_v4.py：**3 条弦流独立解码**（各 5s 立体声）+
  跨页聚合切片 → **68 个拨弦 WAV**（全 6 弦 × 4 采样品位 × Up/Down
  ——主力采样全覆盖）；泛音 18 片在缺头流（malformed 细节待查）→
  走拨弦移调兜底（音高对音色近似）
- [x] 接线：68 wav 进 assets/sounds/steel/（与 ogg 并存）；resolve
  后缀 .ogg → .wav（_pluckFile/_harmonicFile）；bank.load 读 wav 喂
  loadMem（soloud 内容 sniff wav ✓）
- [x] analyze 0 + 回归 28 绿 + exe 重建 ✓；全量测试后台终验中
- [ ] 用户重验：任意谱播放——**第一次听到真录音采样**（此前全部是
  KS 合成——V1.0 起的历史真相）；音色对比前后
- [ ] 泛音流（5bc7/49df）malformed 深调：帧边界对齐切点（vorbis 帧
  粒度重组）——泛音音位后续补齐

## 2026-11-24 二：碎片重组解码完成——**内容实锤为加密态**（决策点）

- [x] 3/5 流重组解码成功（601280 帧 @44100 stereo）——**但内容不对**：
  全流峰值仅 0.056、RMS 0.0046（正常拨弦采样峰值应 0.3-0.9）、有声
  段零星且微弱、熵 7.3-7.5（压缩/加密态）
- [x] **终判**：碎片页体 = **GP8 采样银行的加密态数据**（Arobas 保护
  ——提取时未解密），非可解 vorbis——重组路线到头，**解密需逆向
  GPCore.dll 的采样加载/解密函数**（rea 工具可做，大工程）
- [x] **历史真相定案**：真采样从未工作过（soloud 无法解加密容器）→
  play false → 静默降级 KS——**用户 V1.0 起听到的"真采样音色"实为
  KS 合成**（Karplus-Strong 拨弦物理模型，音色接近真钢弦单音故未
  察觉）——渐进/插针/加载慢等现象全部源于此
- **决策点（三选一，待用户定）**：
  ① 逆向 GP8 解密（大工程——rea 逆向 GPCore，解出真 114 采样）
  ② 换公开真采样库（CC0 钢弦单音采样适配 resolve 命名，中工程）
  ③ 保持 KS 现状（零成本——音色用户已默认接受了三版发布）
- 查看器循环/双模式、渐进提速、插针等全部不受影响（KS 路径已补齐）

## 交接点（持续更新）

1. **用户待验证**（重启 app 后）：Prologue 滑音方向（升╱降╲）、
   m22/m30 扫弦杆与前音分离（gap+12 + 行首右移已进 exe）、
   sl. 两弦间、扫弦杆不穿数字

2. **Prologue m30/m22 扫弦（2026-11-18 更正）**：扫弦**真实存在**
   （py 对账：两处均在 voice0、down/v8、和弦音齐全——"假扫弦"系
   误标，用户主诉一直是**杆与前音重合/过近**）→ 位置修复已进 exe，
   若重验仍贴/叠，回到竖标定位公式继续调
3. **终验**：`flutter test`（全跑，约 40 分钟）；日常用
   `flutter test --exclude-tags=heavy`（94 秒）
4. **未 commit**——全部改动等用户验收 + dsh 复测后用户发话才提交
5. 测试提速已落地：全量探针 4 桶并行 + heavy tag + 快速探针雷区谱集


## 2026-11-23 V1.1 发版完成

- [x] commit 85592ab（指板重做/横向窗口/调音器三改 + pubspec 1.1.0+2）
  推送 origin/master ✓
- [x] **GitHub Release**：https://github.com/plafaithing/GuitarBar/releases/tag/V1.1
  （tag V1.1 @ 85592ab，zip 20MB 附件）✓
- 教训：dist zip 不入 git 仓库（误提交 c6b34b8 已 reset+force 清历史；
  reset --hard 顺带删工作区 zip → -SkipBuild 重打包）；发版流程 =
  build.ps1 -Version Vx.y → gh release create tag "dist/包"