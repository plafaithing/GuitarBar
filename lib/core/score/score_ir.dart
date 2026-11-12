import 'dart:convert';

/// 统一曲谱 IR（设计文档 §4）：所有来源（AI 识谱/确定性导入/人工修正）归一于此。
/// JSON 形态与存储、视觉模型输出同构。
class ScoreIr {
  const ScoreIr({
    required this.version,
    required this.title,
    required this.tempo,
    required this.timeSignature,
    required this.tuning,
    required this.capo,
    required this.tracks,
    this.capoApplied = false,
    this.unrecognizedPages = const [],
  });

  final int version;
  final String title;
  final double tempo;
  final String timeSignature; // "4/4"
  // 低→高：index 0 = 6弦（E2）……index 5 = 1弦（E4）；与 Note.parse 对齐
  final List<String> tuning;
  final int capo;

  /// fret 是否已含 capo 补偿（2026-10-31 语义定案）：
  /// - gpx 通道：fret = 绝对品（GP8 同款），capoApplied = false，
  ///   发声 = tuning + capo + fret
  /// - AI 通道：fret = 夹后品（谱面印刷数字），capoApplied = true，
  ///   发声 = tuning + fret（capo 已含）
  /// 谱面显示/GTP 通道默认 false。
  final bool capoApplied;
  final List<TrackIr> tracks;
  // 识别失败的页号（0 起），可见化不静默丢
  final List<int> unrecognizedPages;

  Map<String, dynamic> toJson() => {
        'version': version,
        'title': title,
        'tempo': tempo,
        'timeSignature': timeSignature,
        'tuning': tuning,
        'capo': capo,
        'capoApplied': capoApplied,
        'tracks': [for (final t in tracks) t.toJson()],
        'unrecognizedPages': unrecognizedPages,
      };

  static ScoreIr fromJson(Map<String, dynamic> j) => ScoreIr(
        version: (j['version'] as num?)?.toInt() ?? 1,
        title: j['title'] as String? ?? '未命名',
        tempo: (j['tempo'] as num?)?.toDouble() ?? 90,
        timeSignature: j['timeSignature'] as String? ?? '4/4',
        tuning: [
          if (j['tuning'] case final List l)
            for (final s in l) s as String
        ],
        capo: (j['capo'] as num?)?.toInt() ?? 0,
        capoApplied: j['capoApplied'] as bool? ?? false,
        tracks: [
          if (j['tracks'] case final List l)
            for (final t in l) TrackIr.fromJson(t as Map<String, dynamic>)
        ],
        unrecognizedPages: [
          if (j['unrecognizedPages'] case final List l)
            for (final n in l) (n as num).toInt()
        ],
      );

  @override
  bool operator ==(Object other) =>
      other is ScoreIr &&
      (identical(this, other) || jsonEncode(other.toJson()) == jsonEncode(toJson()));

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// 曲轨。相等语义由 ScoreIr 的 JSON 编码比较覆盖整棵树，本类不单独实现 ==。
class TrackIr {
  const TrackIr({required this.name, required this.measures});
  final String name;
  final List<MeasureIr> measures;

  Map<String, dynamic> toJson() =>
      {'name': name, 'measures': [for (final m in measures) m.toJson()]};

  static TrackIr fromJson(Map<String, dynamic> j) => TrackIr(
        name: j['name'] as String? ?? '主旋律',
        measures: [
          if (j['measures'] case final List l)
            for (final m in l) MeasureIr.fromJson(m as Map<String, dynamic>)
        ],
      );
}

class MeasureIr {
  const MeasureIr({
    required this.index,
    required this.confidence,
    required this.failed,
    required this.notes,
    this.repeatStart = false,
    this.repeatEnd = false,
    this.repeatCount = 0,
    this.endings = const [],
    this.fermatas = const [],
    this.timeSignature,
  });

  final int index; // 全曲连续小节号（0 起）
  final double confidence; // 0-1；0 表示不可用
  final bool failed; // true = 识别失败占位，notes 恒空
  final List<NoteIr> notes;

  /// 小节级拍号（2026-11-10 Flower gp5 根因修复：首小节可为 1/4
  /// pickup 前奏——全局拍号 4/4 会把该小节音位/时长全部算错）。格式
  /// "N/D"；null = 继承全曲 ScoreIr.timeSignature。
  final String? timeSignature;

  // 反复记号（2026-11-02 走查：GP8 显示反复双竖线+圆点，v1 缺失）。
  // gpif MasterBar 的 Repeat start="true"/end="true"（count 为重复次数，
  // 0/缺省 = 音乐惯例 2 遍；播放展开见 score_ir.expandMeasures）。
  final bool repeatStart;
  final bool repeatEnd;

  /// 反复遍数（repeatEnd 小节上的 gpif Repeat count；0 = 缺省 2 遍）。
  final int repeatCount;

  // 结尾跳房子标记（2026-11-02 走查：GP8 "1."/"2." 括号，v1 缺失）——
  // gpif AlternativeEndings/Ending 的 number（该小节属于第 N 结尾）。
  final List<int> endings;

  // 延长记号（2026-11-07 gp8 对照补完；月下之恋 8 处真值）：gpif
  // MasterBar → Fermatas → Fermata。beat = 小节内拍位（Offset 分数
  // "2/1"→2.0）；length = 延长比例（gpif Length 0.46 ≈ 该拍后顺延
  // 0.46 拍，播放层采样事件轴顺延实现；显示层弧线符号待画）。
  final List<FermataIr> fermatas;

  Map<String, dynamic> toJson() => {
        'index': index,
        'confidence': confidence,
        'failed': failed,
        'notes': [for (final n in notes) n.toJson()],
        if (repeatStart) 'repeatStart': true,
        if (repeatEnd) 'repeatEnd': true,
        if (repeatCount > 0) 'repeatCount': repeatCount,
        if (endings.isNotEmpty) 'endings': endings,
        if (timeSignature != null) 'timeSignature': timeSignature,
        if (fermatas.isNotEmpty)
          'fermatas': [
            for (final f in fermatas) [f.beat, f.length]
          ],
      };

  static MeasureIr fromJson(Map<String, dynamic> j) => MeasureIr(
        index: (j['index'] as num?)?.toInt() ?? 0,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        failed: j['failed'] as bool? ?? false,
        notes: [
          if (j['notes'] case final List l)
            for (final n in l) NoteIr.fromJson(n as Map<String, dynamic>)
        ],
        repeatStart: j['repeatStart'] as bool? ?? false,
        repeatEnd: j['repeatEnd'] as bool? ?? false,
        repeatCount: (j['repeatCount'] as num?)?.toInt() ?? 0,
        endings: [
          if (j['endings'] case final List l)
            for (final n in l) (n as num).toInt()
        ],
        timeSignature: j['timeSignature'] as String?,
        fermatas: [
          if (j['fermatas'] case final List l)
            for (final f in l)
              FermataIr(
                  beat: (f[0] as num).toDouble(),
                  length: (f[1] as num).toDouble())
        ],
      );

  @override
  bool operator ==(Object other) =>
      other is MeasureIr &&
      (identical(this, other) || jsonEncode(other.toJson()) == jsonEncode(toJson()));

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// 播放反复展开（2026-11-02 走查：复刻 GP8 播放结构——反复跳回 + 结尾
/// 走向）。返回**播放顺序的小节 index 序列**：
/// - repeatEnd（count 次，缺省 2）：未满遍数跳回最近未闭合 repeatStart
/// - 结尾跳房子：第 pass 遍只播 endings 含 pass 的小节（pass = 最近
///   repeatEnd 的已过遍数 + 1），不匹配的结尾段整体跳过
/// - 无结构的谱返回 0..n-1（恒等）
/// 谱面显示保持线性不动；播放时间轴按此序列累计拍位。
/// 限制声明（dsh 交叉测试记录）：不支持嵌套反复（openStart 单变量，GP
/// 本身不产生嵌套）；无 start 的孤立 end 容错回 0 号小节。
List<int> expandMeasures(List<MeasureIr> measures) {
  final n = measures.length;
  if (n == 0) return const [];
  final hasStructure = measures
      .any((m) => m.repeatStart || m.repeatEnd || m.endings.isNotEmpty);
  if (!hasStructure) return [for (var i = 0; i < n; i++) i];

  final out = <int>[];
  var i = 0;
  var openStart = 0; // 最近未闭合 repeatStart（start 缺失容错回 0）
  var passCounter = 1; // 当前段遍次（显式计数：跳回 +1，遇新段重置）
  var justJumped = false; // 跳回落点标记：段首重置被抑制一次

  /// 当前反复段（openStart 起）的结束 end：从 openStart 向后扫第一个
  /// repeatEnd（结尾段管辖判定用）。
  int segmentEnd() {
    for (var j = openStart; j < n; j++) {
      if (measures[j].repeatEnd) return j;
    }
    return -1;
  }

  while (i < n) {
    final m = measures[i];
    // 新反复段（非跳回落点）：重置段状态（openStart/遍次）——必须在
    // endings 判定**之前**（dsh 交叉测试 P3：相邻两段"段首兼结尾"的谱，
    // 第二段段首若先被上一段的遍次判定跳过，段状态永远不重置）。
    if (m.repeatStart && !justJumped) {
      openStart = i;
      passCounter = 1;
    }
    // 结尾走向：当前遍次（显式 passCounter）不在本小节结尾集 → 跳过整个
    // 结尾段管辖区（到反复结束线含）直达下一结尾；落点不匹配则前进。
    // 防死循环：i 已在 end 之后时只能前进（seg+1 回退会原地打转）。
    if (m.endings.isNotEmpty) {
      final seg = segmentEnd();
      if (!m.endings.contains(passCounter)) {
        i = seg + 1 > i ? seg + 1 : i + 1;
        justJumped = false;
        continue;
      }
    }
    out.add(i);
    if (m.repeatStart && justJumped) {
      justJumped = false; // 跳回落点：段状态保留（遍次延续），清标记
    }
    if (m.repeatEnd) {
      if (passCounter < (m.repeatCount > 0 ? m.repeatCount : 2)) {
        passCounter++; // 进入下一遍
        i = openStart; // 跳回反复起始（重播段内）
        justJumped = true;
        continue;
      }
    }
    i++;
  }
  return out;
}

/// 延长记号（2026-11-07 gp8 对照补完）：beat = 小节内拍位；
/// length = 延长比例（gpif Length，0.46 = 顺延 0.46 拍）。
class FermataIr {
  const FermataIr({required this.beat, required this.length});
  final double beat;
  final double length;
}

/// 弯音曲线点（2026-11-04 gp8 补完）：offset = 音符时值内位置 0-1，
/// value = 半音（gpif y/4）。
class BendPointIr {
  const BendPointIr({required this.offset, required this.value});
  final double offset;
  final double value;
}

class NoteIr {
  const NoteIr({
    required this.beat,
    required this.duration,
    required this.string,
    required this.fret,
    this.technique,
    this.confidence,
    this.tieStart = false,
    this.tieEnd = false,
    this.hopoStart = false,
    this.hopoEnd = false,
    this.legatoStart = false,
    this.legatoEnd = false,
    this.letRing = false,
    this.palmMute = false,
    this.vibrato = false,
    this.tap = false,
    this.ghost = false,
    this.slide,
    this.arpeggio,
    this.brush,
    this.pickStroke,
    this.trill = false,
    this.accent = false,
    this.staccato = false,
    this.grace = false,
    this.dynamicMark,
    this.fadding,
    this.wah = false,
    this.tremolo = false,
    this.velocity,
    this.bend,
    this.whammy,
    this.harmonicOffset,
    this.harmonicType,
  });

  final double beat; // 小节内拍位置，0 起
  final double duration; // 单位拍
  final int string; // 1-6，1 = 最细高音弦
  final int fret; // 0-24，0 = 空弦
  final String? technique; // null | h | p | s | b | x | H
  final double? confidence; // null = 非 AI 来源

  // —— 曲谱标注（2026-10-31 GP8 逆向补齐，gpif 属性 → bool 标记）——
  // tie 弧线两端：start 出音（时长已含续接端累计），end 不发声仅画弧端点。
  final bool tieStart;
  final bool tieEnd;
  // 击勾弦弧线两端（gpif HopoOrigin/HopoDestination）：两端都出音，
  // 渲染按品数走向画 H（升）/P（降）。
  final bool hopoStart;
  final bool hopoEnd;
  // 连滑音弧线两端（gpif LegatoOrigin/LegatoDestination / Slide legato 位）。
  final bool legatoStart;
  final bool legatoEnd;
  // 延音 L.R. 虚线 / 闷音 P.M. 虚线 / 揉弦波浪 / 点弦 T / 幽灵音括号。
  final bool letRing;
  final bool palmMute;
  final bool vibrato;
  final bool tap;
  final bool ghost;
  // shift = 定滑音（斜线箭头）；legato = 连滑音（弧线）。null = 无滑音。
  final String? slide;
  // Beat 级标注（2026-11-01 走查补齐，挂该拍全部音）：
  // 琶音竖波浪 / 扫弦箭头 / 拨片方向符号，'up'|'down'|null。
  final String? arpeggio;
  final String? brush;
  final String? pickStroke;

  // 轻量标注第二批（2026-11-02 GP8 标识符对照补齐；Bend/Whammy 曲线类
  // 另立项）：
  // - Trill 颤音（Note 属性 Trill）→ "tr" 上标
  // - Accent 重音（Note 属性 Accent）→ 数字上方 >
  // - Staccato 断音 → 数字上方 ·
  // - Grace 装饰音（Beat GraceNotes）→ 小号斜体数字
  // - Dynamic 力度（Beat Dynamic 'MF' 等）→ 行底力度字（拍群首画）
  // - Fadding 淡入出（Beat Fadding 'FadeIn'）→ 行底文字
  // - Wah → 行底文字
  final bool trill;
  final bool accent;
  final bool staccato;
  final bool grace;
  final String? dynamicMark; // 小写规范化（'f'/'mf'/'p'...）
  final String? fadding; // 'in' | 'out'
  final bool wah;

  // 播放行为映射（2026-11-02 gp8 编辑面板播放能力复刻）：
  // - Tremolo 震音拨（Beat 属性）：该拍音符在时值内按 32 分快速重复发声
  // - Velocity 音符力度（Note 属性 0-127，gp8 MIDI 力度）→ 发声音量映射
  final bool tremolo;
  final int? velocity;

  // 弯音（2026-11-04 gp8 编辑面板播放能力补完；样本缺口——曲库三 gpx +
  // 三 gp5 探针均无 Bend 数据，Like A Star 的 1257 处 Whammy 属性全为
  // 0.0 占位。解析按 gpif/alphaTab 语义实现，合成 fixture 验证，换算
  // 系数待真实谱校准）：
  // - bend：音符弯音曲线（gpif Note 属性 Bend 的 Curve 点列，x 0-60 →
  //   0-1 拍内位置，y 单位 1/4 半音 → value 半音 = y/4）
  // - whammy：拍级摇把 [origin, destination]（半音，gpif Beat 属性
  //   WhammyBarOrigin/DestinationValue 的 Float 值；全 0 不写入）
  final List<BendPointIr>? bend;
  final List<double>? whammy;

  // 泛音（2026-11-05 gp8 实现方式逆向）：**发声 = 音高重映射**——原品
  // 采样固定移调到泛音分节点（GP8/alphaTab 同款，无独立采样）。
  // harmonicOffset = 相对空弦的半音偏移（解析层算好）：
  // - Natural：自然泛音表[fret]（12→+12、9→+16、7→+19、5→+24、4→+28、
  //   3→+31、2→+34，未知品兜底 +12）
  // - Artificial：按弦音 + 自然泛音表[HFret]（HFret 为触点相对距离）
  // 曲库样本：月下之恋 Artificial(Fret19/HFret12)、Like A Star
  // Natural(HFret12)/Artificial、Bluebird Natural——22 处真值。
  final double? harmonicOffset;

  /// 泛音类型（'natural' | 'artificial'，gp8 六线谱 AH 文字标注区分用；
  /// null = 非泛音）。2026-11-08 截图对照补。
  final String? harmonicType;

  /// 有标注才写字段：无标注音符的 JSON 与旧格式一致（存量 irJson 兼容）。
  Map<String, dynamic> toJson() => {
        'beat': beat,
        'duration': duration,
        'string': string,
        'fret': fret,
        'technique': technique,
        'confidence': confidence,
        if (tieStart) 'tieStart': true,
        if (tieEnd) 'tieEnd': true,
        if (hopoStart) 'hopoStart': true,
        if (hopoEnd) 'hopoEnd': true,
        if (legatoStart) 'legatoStart': true,
        if (legatoEnd) 'legatoEnd': true,
        if (letRing) 'letRing': true,
        if (palmMute) 'palmMute': true,
        if (vibrato) 'vibrato': true,
        if (tap) 'tap': true,
        if (ghost) 'ghost': true,
        if (slide != null) 'slide': slide,
        if (arpeggio != null) 'arpeggio': arpeggio,
        if (brush != null) 'brush': brush,
        if (pickStroke != null) 'pickStroke': pickStroke,
        if (trill) 'trill': true,
        if (accent) 'accent': true,
        if (staccato) 'staccato': true,
        if (grace) 'grace': true,
        if (dynamicMark != null) 'dynamicMark': dynamicMark,
        if (fadding != null) 'fadding': fadding,
        if (wah) 'wah': true,
        if (tremolo) 'tremolo': true,
        if (velocity != null) 'velocity': velocity,
        if (bend != null)
          'bend': [for (final p in bend!) [p.offset, p.value]],
        if (whammy != null) 'whammy': whammy,
        if (harmonicOffset != null) 'harmonicOffset': harmonicOffset,
        if (harmonicType != null) 'harmonicType': harmonicType,
      };

  static NoteIr fromJson(Map<String, dynamic> j) => NoteIr(
        beat: (j['beat'] as num?)?.toDouble() ?? 0,
        duration: (j['duration'] as num?)?.toDouble() ?? 1,
        string: (j['string'] as num?)?.toInt() ?? 1,
        fret: (j['fret'] as num?)?.toInt() ?? 0,
        technique: j['technique'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble(),
        tieStart: j['tieStart'] as bool? ?? false,
        tieEnd: j['tieEnd'] as bool? ?? false,
        hopoStart: j['hopoStart'] as bool? ?? false,
        hopoEnd: j['hopoEnd'] as bool? ?? false,
        legatoStart: j['legatoStart'] as bool? ?? false,
        legatoEnd: j['legatoEnd'] as bool? ?? false,
        letRing: j['letRing'] as bool? ?? false,
        palmMute: j['palmMute'] as bool? ?? false,
        vibrato: j['vibrato'] as bool? ?? false,
        tap: j['tap'] as bool? ?? false,
        ghost: j['ghost'] as bool? ?? false,
        slide: j['slide'] as String?,
        arpeggio: j['arpeggio'] as String?,
        brush: j['brush'] as String?,
        pickStroke: j['pickStroke'] as String?,
        trill: j['trill'] as bool? ?? false,
        accent: j['accent'] as bool? ?? false,
        staccato: j['staccato'] as bool? ?? false,
        grace: j['grace'] as bool? ?? false,
        dynamicMark: j['dynamicMark'] as String?,
        fadding: j['fadding'] as String?,
        wah: j['wah'] as bool? ?? false,
        tremolo: j['tremolo'] as bool? ?? false,
        velocity: (j['velocity'] as num?)?.toInt(),
        bend: j['bend'] == null
            ? null
            : [
                for (final p in j['bend'] as List)
                  BendPointIr(
                      offset: (p[0] as num).toDouble(),
                      value: (p[1] as num).toDouble()),
              ],
        whammy: (j['whammy'] as List?)
            ?.map((v) => (v as num).toDouble())
            .toList(),
        harmonicOffset: (j['harmonicOffset'] as num?)?.toDouble(),
        harmonicType: j['harmonicType'] as String?,
      );

  NoteIr copyWith({
    double? beat,
    double? duration,
    int? string,
    int? fret,
    String? technique,
    double? confidence,
    bool? tieStart,
    bool? tieEnd,
    bool? hopoStart,
    bool? hopoEnd,
    bool? legatoStart,
    bool? legatoEnd,
    bool? letRing,
    bool? palmMute,
    bool? vibrato,
    bool? tap,
    bool? ghost,
    String? slide,
    String? arpeggio,
    String? brush,
    String? pickStroke,
    bool? trill,
    bool? accent,
    bool? staccato,
    bool? grace,
    String? dynamicMark,
    String? fadding,
    bool? wah,
  }) =>
      NoteIr(
          beat: beat ?? this.beat,
          duration: duration ?? this.duration,
          string: string ?? this.string,
          fret: fret ?? this.fret,
          technique: technique ?? this.technique,
          confidence: confidence ?? this.confidence,
          tieStart: tieStart ?? this.tieStart,
          tieEnd: tieEnd ?? this.tieEnd,
          hopoStart: hopoStart ?? this.hopoStart,
          hopoEnd: hopoEnd ?? this.hopoEnd,
          legatoStart: legatoStart ?? this.legatoStart,
          legatoEnd: legatoEnd ?? this.legatoEnd,
          letRing: letRing ?? this.letRing,
          palmMute: palmMute ?? this.palmMute,
          vibrato: vibrato ?? this.vibrato,
          tap: tap ?? this.tap,
          ghost: ghost ?? this.ghost,
          slide: slide ?? this.slide,
          arpeggio: arpeggio ?? this.arpeggio,
          brush: brush ?? this.brush,
          pickStroke: pickStroke ?? this.pickStroke,
          trill: trill ?? this.trill,
          accent: accent ?? this.accent,
          staccato: staccato ?? this.staccato,
          grace: grace ?? this.grace,
          dynamicMark: dynamicMark ?? this.dynamicMark,
          fadding: fadding ?? this.fadding,
          wah: wah ?? this.wah);

  @override
  bool operator ==(Object other) =>
      other is NoteIr &&
      (identical(this, other) || jsonEncode(other.toJson()) == jsonEncode(toJson()));

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}
