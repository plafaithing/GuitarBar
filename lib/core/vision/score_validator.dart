import 'dart:convert';

import '../music/note.dart';
import '../score/score_ir.dart';

const _techniques = {'h', 'p', 's', 'b', 'x', 'H'};

class PageParseResult {
  const PageParseResult(
      {required this.measures,
      required this.failedCount,
      this.capo = 0,
      this.tuning});
  final List<MeasureIr> measures;
  final int failedCount; // 本页被判 failed 的小节数

  /// 谱面标注的变调夹品数（模型从谱面文字读出；0 = 无标注）。
  /// 坏值（非 num/越界）按 0，不让一个字段废掉整页。
  final int capo;

  /// 谱面标注的调弦（6 个音名，6弦→1弦低到高；null = 谱面无标注）。
  /// 坏值（长度非 6 / 坏音名）按 null，一个字段废不掉整页（对齐 capo 容错）。
  final List<String>? tuning;
}

/// 视觉模型响应 → IR 小节（零成本机器防线，设计文档 §5.2）。
/// 规则：剥围栏 → 解析 → 逐音校验；任一音不合法 = 整小节 failed（不静默丢）；
/// index 一律按数组位置重编，不信任模型编号。
PageParseResult parsePage(String raw, {required int indexOffset}) {
  final json = _extractJson(raw);
  final data = jsonDecode(json);
  if (data is! Map<String, dynamic> || data['measures'] is! List) {
    throw const FormatException('响应缺少 measures 数组');
  }
  final capoRaw = data['capo'];
  final capo = capoRaw is num ? capoRaw.toInt().clamp(0, 7) : 0;
  final tuning = _tuning(data['tuning']);
  final measures = <MeasureIr>[];
  var failed = 0;
  final rawMeasures = data['measures'] as List;
  for (var i = 0; i < rawMeasures.length; i++) {
    final m = _measure(rawMeasures[i], i + indexOffset);
    if (m.failed) failed++;
    measures.add(m);
  }
  return PageParseResult(
      measures: measures, failedCount: failed, capo: capo, tuning: tuning);
}

/// 调弦字段校验：List 且长度 6、每个元素 Note.parse 成功才采信；
/// 用 Note.parse(s).name 规范大小写（'e2' → 'E2'）。
/// 缺省/长度不符/坏音名 → null（谱面无标注语义，兜底参数接管）。
List<String>? _tuning(dynamic raw) {
  if (raw is! List || raw.length != 6) return null;
  try {
    return [for (final s in raw) Note.parse(s as String).name];
  } on ArgumentError {
    return null;
  } on TypeError {
    return null; // 元素非 String（模型输出数字等）同样不采信
  }
}

String _extractJson(String raw) {
  final s = raw.indexOf('{');
  final e = raw.lastIndexOf('}');
  if (s < 0 || e <= s) throw const FormatException('响应中没有 JSON 对象');
  return raw.substring(s, e + 1);
}

MeasureIr _measure(dynamic raw, int index) {
  double confidenceOf(dynamic v, double fallback) {
    if (v is! num) return fallback;
    return v.toDouble().clamp(0.0, 1.0).toDouble();
  }

  if (raw is! Map<String, dynamic>) {
    return MeasureIr(index: index, confidence: 0, failed: true, notes: const []);
  }
  final conf = confidenceOf(raw['confidence'], 0.5);
  final notes = <NoteIr>[];
  var ok = true;
  if (raw['notes'] is List) {
    for (final n in raw['notes'] as List) {
      final note = _note(n);
      if (note == null) {
        ok = false;
        break;
      }
      notes.add(note);
    }
  } else {
    ok = false;
  }
  if (!ok) {
    return MeasureIr(index: index, confidence: 0, failed: true, notes: const []);
  }
  // 近拍同弦去重（2026-10-31 走查反馈"写两遍"）：模型会对同一音输出
  // 近拍双 note（beat 差 ≤ 0.05，一带技法一不带），渲染层错位叠加成两份
  // 文字。保留带技法的（信息更全）；都不带保留首个。和弦同拍跨弦不受影响。
  final deduped = <NoteIr>[];
  for (final n in notes) {
    final dup = deduped.any((d) =>
        d.string == n.string && (d.beat - n.beat).abs() <= 0.05);
    if (!dup) {
      deduped.add(n);
    } else {
      final i = deduped.indexWhere((d) =>
          d.string == n.string && (d.beat - n.beat).abs() <= 0.05);
      if (n.technique != null && deduped[i].technique == null) {
        deduped[i] = n; // 带技法者替换裸音
      }
    }
  }
  return MeasureIr(index: index, confidence: conf, failed: false, notes: deduped);
}

NoteIr? _note(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  final beat = raw['beat'];
  final duration = raw['duration'];
  final string = raw['string'];
  final fret = raw['fret'];
  final technique = raw['technique'];
  // 防御式（同 confidenceOf 的 is num 模式）：非 num（如字符串化数字 "0"）
  // 按该音不合法处理 → 整小节 failed，不抛 TypeError 被编排层吞成整页失败。
  if (beat is! num || beat < 0) return null;
  if (duration is! num || duration <= 0) return null;
  if (string is! num || string < 1 || string > 6) return null;
  if (fret is! num || fret < 0 || fret > 24) return null;
  if (technique != null &&
      (technique is! String || !_techniques.contains(technique))) {
    return null;
  }
  final conf = raw['confidence'];
  return NoteIr(
      beat: beat.toDouble(),
      duration: duration.toDouble(),
      string: string.toInt(),
      fret: fret.toInt(),
      technique: technique as String?,
      confidence: conf is num ? conf.toDouble().clamp(0.0, 1.0).toDouble() : null);
}
