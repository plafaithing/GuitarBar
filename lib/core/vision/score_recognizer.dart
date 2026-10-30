import 'dart:io';

import '../score/score_ir.dart';
import 'score_validator.dart';
import 'tab_prompt.dart';
import 'vision_client.dart';
import 'vision_model.dart';

/// 用户取消识谱（页间检查，分钟级在途调用不强杀）。
class RecognizeCancelled implements Exception {
  const RecognizeCancelled();
  @override
  String toString() => '识谱已取消';
}

/// 识谱编排（设计文档 §5）：逐页调视觉模型 → 机器校验 → 合并 IR。
/// 延迟校准（§5.2）：模型 thinking 分钟级，超时由注入的 VisionClient 决定
/// （Task 11 用 Duration(minutes: 10)），本层不做超时逻辑。
/// 失败语义：异常重试 1 次仍败 = failed 占位小节 + unrecognizedPages；
/// 空 measures（含重试后）= 仅记 unrecognizedPages，不插占位（合法空页如
/// 视奏顺序图，见计划 d84d304 裁决）。
/// onPage：0 起页号、处理该页前回调（UI 显示"第 done+1/N 页"）。
/// 每页 complete 最坏 3 次（交叉路径：首次空→重试异常→catch 内翻案机会）。
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
    bool Function()? cancelled,
    void Function(int recognizedCapo)? onCapoRecognized,
  }) async {
    final measures = <MeasureIr>[];
    final failedPages = <int>[];
    var offset = 0;

    // capo 语义（2026-10-30 用户反馈定案）：谱面标注优先——模型从谱面读出的
    // 品数覆盖手动参数；手动值仅作无标注时的兜底。多页取最大（标注通常一致，
    // 取最大可吸收个别页漏识）。
    var effectiveCapo = capo;
    var capoFromSheet = false;

    for (var i = 0; i < pagePngs.length; i++) {
      // 取消抛异常而非返回半成品 IR：保住库里已有识别结果不被残缺 IR 覆盖。
      if (cancelled?.call() ?? false) throw const RecognizeCancelled();
      onPage?.call(i, pagePngs.length);
      // readAsBytes 在 try 外：本地文件错误不属模型调用失败，不走重试/占位，直接上抛。
      final png = await pagePngs[i].readAsBytes();
      final prompt = '$tabSystemPrompt\n\n'
          '${tabUserPrompt(tuning: tuning, timeSignature: timeSignature, capo: capo, page: i, total: pagePngs.length)}';

      Future<String> once() => _client.complete(
          baseUrl: cfg.baseUrl, apiKey: cfg.apiKey, model: cfg.model,
          prompt: prompt, png: png);

      List<MeasureIr>? pageMeasures; // null = 异常路径全败
      int? pageCapo;
      try {
        var r = parsePage(await once(), indexOffset: offset);
        if (r.measures.isEmpty) {
          // 空结果重试 1 次（模型可能漏识整页；合法空页多花一次调用可接受）。
          r = parsePage(await once(), indexOffset: offset);
        }
        pageMeasures = r.measures;
        pageCapo = r.capo;
      } catch (_) {
        try {
          final r = parsePage(await once(), indexOffset: offset); // 重试 1 次
          pageMeasures = r.measures;
          pageCapo = r.capo;
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

      // 谱面标注覆盖手动 capo（成功页才采信；失败页的 capo 不可靠）。
      if (pageMeasures != null && pageMeasures.isNotEmpty && pageCapo != null) {
        if (!capoFromSheet && pageCapo > 0) {
          capoFromSheet = true;
          effectiveCapo = pageCapo;
          onCapoRecognized?.call(pageCapo);
        } else if (capoFromSheet && pageCapo > effectiveCapo) {
          effectiveCapo = pageCapo;
          onCapoRecognized?.call(pageCapo);
        }
      }
    }

    return ScoreIr(
      version: 1,
      title: title,
      tempo: tempo,
      timeSignature: timeSignature,
      tuning: tuning,
      capo: effectiveCapo,
      tracks: [TrackIr(name: '主旋律', measures: measures)],
      unrecognizedPages: failedPages,
    );
  }
}
