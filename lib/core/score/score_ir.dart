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
  });

  final int index; // 全曲连续小节号（0 起）
  final double confidence; // 0-1；0 表示不可用
  final bool failed; // true = 识别失败占位，notes 恒空
  final List<NoteIr> notes;

  Map<String, dynamic> toJson() => {
        'index': index,
        'confidence': confidence,
        'failed': failed,
        'notes': [for (final n in notes) n.toJson()],
      };

  static MeasureIr fromJson(Map<String, dynamic> j) => MeasureIr(
        index: (j['index'] as num?)?.toInt() ?? 0,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        failed: j['failed'] as bool? ?? false,
        notes: [
          if (j['notes'] case final List l)
            for (final n in l) NoteIr.fromJson(n as Map<String, dynamic>)
        ],
      );

  @override
  bool operator ==(Object other) =>
      other is MeasureIr &&
      (identical(this, other) || jsonEncode(other.toJson()) == jsonEncode(toJson()));

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

class NoteIr {
  const NoteIr({
    required this.beat,
    required this.duration,
    required this.string,
    required this.fret,
    required this.technique,
    this.confidence,
  });

  final double beat; // 小节内拍位置，0 起
  final double duration; // 单位拍
  final int string; // 1-6，1 = 最细高音弦
  final int fret; // 0-24，0 = 空弦
  final String? technique; // null | h | p | s | b | x | H
  final double? confidence; // null = 非 AI 来源

  Map<String, dynamic> toJson() => {
        'beat': beat,
        'duration': duration,
        'string': string,
        'fret': fret,
        'technique': technique,
        'confidence': confidence,
      };

  static NoteIr fromJson(Map<String, dynamic> j) => NoteIr(
        beat: (j['beat'] as num?)?.toDouble() ?? 0,
        duration: (j['duration'] as num?)?.toDouble() ?? 1,
        string: (j['string'] as num?)?.toInt() ?? 1,
        fret: (j['fret'] as num?)?.toInt() ?? 0,
        technique: j['technique'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble(),
      );

  NoteIr copyWith({double? beat, double? duration, int? string, int? fret,
      String? technique, double? confidence}) =>
      NoteIr(
          beat: beat ?? this.beat,
          duration: duration ?? this.duration,
          string: string ?? this.string,
          fret: fret ?? this.fret,
          technique: technique ?? this.technique,
          confidence: confidence ?? this.confidence);

  @override
  bool operator ==(Object other) =>
      other is NoteIr &&
      (identical(this, other) || jsonEncode(other.toJson()) == jsonEncode(toJson()));

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}
