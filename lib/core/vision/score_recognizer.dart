import 'dart:io';

import '../score/score_ir.dart';
import 'score_validator.dart';
import 'tab_prompt.dart';
import 'vision_client.dart';
import 'vision_model.dart';

/// 识谱编排（设计文档 §5）：逐页调视觉模型 → 机器校验 → 合并 IR。
/// 延迟校准（§5.2）：模型 thinking 分钟级，超时由注入的 VisionClient 决定
/// （Task 11 用 Duration(minutes: 10)），本层不做超时逻辑。
/// 失败语义：异常重试 1 次仍败 = failed 占位小节 + unrecognizedPages；
/// 空 measures（含重试后）= 仅记 unrecognizedPages，不插占位（合法空页如
/// 视奏顺序图，见计划 d84d304 裁决）。
class ScoreRecognizer {
  ScoreRecognizer(this._client);
  final VisionClient _client;

  Future<ScoreIr> recognize({
    required String title,
    required List<File> pagePngs,
    required VisionModelConfig cfg,
    required double tempo,
    required List<String> tuning,
    required String timeSignature,
    required int capo,
    void Function(int done, int total)? onPage,
  }) async {
    final measures = <MeasureIr>[];
    final failedPages = <int>[];
    var offset = 0;

    for (var i = 0; i < pagePngs.length; i++) {
      onPage?.call(i, pagePngs.length);
      final png = await pagePngs[i].readAsBytes();
      final prompt = '$tabSystemPrompt\n\n'
          '${tabUserPrompt(tuning: tuning, timeSignature: timeSignature, capo: capo, page: i, total: pagePngs.length)}';

      Future<String> once() => _client.complete(
          baseUrl: cfg.baseUrl, apiKey: cfg.apiKey, model: cfg.model,
          prompt: prompt, png: png);

      List<MeasureIr>? pageMeasures; // null = 异常路径全败
      try {
        var r = parsePage(await once(), indexOffset: offset);
        if (r.measures.isEmpty) {
          // 空结果重试 1 次（模型可能漏识整页；合法空页多花一次调用可接受）。
          r = parsePage(await once(), indexOffset: offset);
        }
        pageMeasures = r.measures;
      } catch (_) {
        try {
          final r = parsePage(await once(), indexOffset: offset); // 重试 1 次
          pageMeasures = r.measures;
        } catch (_) {
          pageMeasures = null;
        }
      }

      if (pageMeasures == null) {
        failedPages.add(i);
        measures.add(MeasureIr(
            index: offset, confidence: 0, failed: true, notes: const []));
        offset += 1;
      } else if (pageMeasures.isEmpty) {
        failedPages.add(i); // 空页：仅页级记录，不插占位
      } else {
        measures.addAll(pageMeasures);
        offset += pageMeasures.length;
      }
    }

    return ScoreIr(
      version: 1,
      title: title,
      tempo: tempo,
      timeSignature: timeSignature,
      tuning: tuning,
      capo: capo,
      tracks: [TrackIr(name: '主旋律', measures: measures)],
      unrecognizedPages: failedPages,
    );
  }
}
