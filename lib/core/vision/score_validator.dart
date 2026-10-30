import 'dart:convert';

import '../score/score_ir.dart';

const _techniques = {'h', 'p', 's', 'b', 'x', 'H'};

class PageParseResult {
  const PageParseResult({required this.measures, required this.failedCount});
  final List<MeasureIr> measures;
  final int failedCount; // 本页被判 failed 的小节数
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
  final measures = <MeasureIr>[];
  var failed = 0;
  final rawMeasures = data['measures'] as List;
  for (var i = 0; i < rawMeasures.length; i++) {
    final m = _measure(rawMeasures[i], i + indexOffset);
    if (m.failed) failed++;
    measures.add(m);
  }
  return PageParseResult(measures: measures, failedCount: failed);
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
  return ok
      ? MeasureIr(index: index, confidence: conf, failed: false, notes: notes)
      : MeasureIr(index: index, confidence: 0, failed: true, notes: const []);
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
