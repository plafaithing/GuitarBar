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
  });

  final int index; // 全曲连续小节号（0 起）
  final double confidence; // 0-1；0 表示不可用
  final bool failed; // true = 识别失败占位，notes 恒空
  final List<NoteIr> notes;

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

  Map<String, dynamic> toJson() => {
        'index': index,
        'confidence': confidence,
        'failed': failed,
        'notes': [for (final n in notes) n.toJson()],
        if (repeatStart) 'repeatStart': true,
        if (repeatEnd) 'repeatEnd': true,
        if (repeatCount > 0) 'repeatCount': repeatCount,
        if (endings.isNotEmpty) 'endings': endings,
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
List<int> expandMeasures(List<MeasureIr> measures) {
  final n = measures.length;
  if (n == 0) return const [];
  final hasStructure = measures
      .any((m) => m.repeatStart || m.repeatEnd || m.endings.isNotEmpty);
  if (!hasStructure) return [for (var i = 0; i < n; i++) i];

  int lastEndBefore(int i) {
    for (var j = i - 1; j >= 0; j--) {
      if (measures[j].repeatEnd) return j;
    }
    return -1;
  }

  final out = <int>[];
  var i = 0;
  var openStart = 0; // 最近未闭合 repeatStart（start 缺失容错回 0）
  final endPass = <int, int>{}; // repeatEnd 小节 index → 已过遍数

  /// 当前反复段（openStart 起）的结束 end：从 openStart 向后扫第一个
  /// repeatEnd。结尾段的"当前遍次"由它计数（结尾段在 end 之前，往
  /// 前找会漏；2026-11-02 测试实证修正）。
  int segmentEnd() {
    for (var j = openStart; j < n; j++) {
      if (measures[j].repeatEnd) return j;
    }
    return -1;
  }

  while (i < n) {
    final m = measures[i];
    // 结尾走向：当前遍次不在本小节结尾集 → 整段跳过（连续同结尾号的
    // 小节）。遍次语义分两段（2026-11-02 测试实证）：end **之前**的结尾
    // 段 = end 已过遍数 + 1（当前遍进行中）；end **之后**（如结尾 2）=
    // end 已完成遍数（第二遍 end 走完时计数已是 2，结尾 2 属于该遍）。
    if (m.endings.isNotEmpty) {
      final seg = segmentEnd();
      var pass = seg >= 0 ? (endPass[seg] ?? 0) : 0;
      if (seg < 0 || i <= seg) pass += 1;
      if (!m.endings.contains(pass)) {
        var j = i;
        while (j < n &&
            measures[j].endings.isNotEmpty &&
            measures[j].endings.join(',') == m.endings.join(',')) {
          j++;
        }
        i = j;
        continue;
      }
    }
    out.add(i);
    if (m.repeatStart) openStart = i;
    if (m.repeatEnd) {
      final pass = endPass[i] = (endPass[i] ?? 0) + 1;
      final count = m.repeatCount > 0 ? m.repeatCount : 2;
      if (pass < count) {
        i = openStart; // 跳回反复起始（重播段内）
        continue;
      }
    }
    i++;
  }
  return out;
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
          pickStroke: pickStroke ?? this.pickStroke);

  @override
  bool operator ==(Object other) =>
      other is NoteIr &&
      (identical(this, other) || jsonEncode(other.toJson()) == jsonEncode(toJson()));

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}
