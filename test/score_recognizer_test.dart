import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/score_ir.dart';
import 'package:guitarbar/core/vision/score_recognizer.dart';
import 'package:guitarbar/core/vision/vision_client.dart';
import 'package:guitarbar/core/vision/vision_model.dart';

/// VisionClient 测试替身：按脚本逐次返回（String 成功 / VisionException 失败）。
/// Task 7 审查修复后 VisionClient 接口含 timeout 与 close，须一并实现；
/// 2026-10-30 走查修复又加了 maxTokens，同理由 implements 契约带出。
class ScriptedClient implements VisionClient {
  ScriptedClient(this.responses);
  final List<Object> responses; // String 成功 / VisionException 失败
  int callCount = 0;

  @override
  Duration get timeout => Duration.zero;

  @override
  int get maxTokens => 1024;

  @override
  void close() {}

  @override
  Future<String> complete({required String baseUrl, required String apiKey,
      required String model, required String prompt, required Uint8List png,
      String mime = 'image/png'}) async {
    final r = responses[callCount++];
    if (r is VisionException) throw r;
    return r as String;
  }
}

File tmpPage(Directory d, String name) =>
    File('${d.path}/$name')..writeAsBytesSync([1, 2, 3]);

const cfg = VisionModelConfig(
    id: 'a', name: 'x', baseUrl: 'https://u', apiKey: 'k',
    model: 'm', active: true);

Future<ScoreIr> run(ScriptedClient c, List<File> pages,
        {bool Function()? cancelled, void Function(int, int)? onPage}) async =>
    ScoreRecognizer(c).recognize(
    title: 'T', pagePngs: pages, cfg: cfg, tempo: 90,
    tuning: const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
    timeSignature: '4/4', capo: 0,
    cancelled: cancelled, onPage: onPage);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('recognizer'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('两页成功：合并小节、index 连续', () async {
    final client = ScriptedClient([
      '{"measures":[{"index":0,"confidence":0.9,"notes":[]},{"index":1,"confidence":0.8,"notes":[]}]}',
      '{"measures":[{"index":0,"confidence":0.7,"notes":[]}]}',
    ]);
    final ir = await run(client,
        [tmpPage(tmp, 'a.png'), tmpPage(tmp, 'b.png')]);
    expect(ir.tracks.single.measures.map((m) => m.index), [0, 1, 2]);
    expect(ir.unrecognizedPages, isEmpty);
    expect(ir.tempo, 90);
    expect(ir.capo, 0);
    expect(ir.tuning, const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']);
  });

  test('单页异常重试 1 次后成功', () async {
    final client = ScriptedClient([
      const VisionException('boom'),
      '{"measures":[{"index":0,"confidence":0.9,"notes":[]}]}',
    ]);
    final ir = await run(client, [tmpPage(tmp, 'a.png')]);
    expect(ir.unrecognizedPages, isEmpty);
    expect(ir.tracks.single.measures.length, 1);
  });

  test('重试仍异常：failed 占位小节 + unrecognizedPages 记录', () async {
    final client = ScriptedClient([
      const VisionException('boom'),
      const VisionException('boom'),
      '{"measures":[{"index":0,"confidence":0.9,"notes":[]}]}',
    ]);
    final ir = await run(client,
        [tmpPage(tmp, 'a.png'), tmpPage(tmp, 'b.png')]);
    expect(ir.unrecognizedPages, [0]);
    final failed = ir.tracks.single.measures.where((m) => m.failed).toList();
    expect(failed.length, 1);
    expect(failed.single.index, 0);
    expect(ir.tracks.single.measures.length, 2); // 第二页正常编入
    expect(ir.tracks.single.measures.last.index, 1);
  });

  test('空页两次：记 unrecognizedPages、不插占位小节、后续页 index 连续', () async {
    final client = ScriptedClient([
      '{"measures":[]}',
      '{"measures":[]}',
      '{"measures":[{"index":0,"confidence":0.9,"notes":[]}]}',
    ]);
    final ir = await run(client,
        [tmpPage(tmp, 'a.png'), tmpPage(tmp, 'b.png')]);
    expect(ir.unrecognizedPages, [0]);
    expect(ir.tracks.single.measures.length, 1);
    expect(ir.tracks.single.measures.single.index, 0); // 不被空页污染
    expect(ir.tracks.single.measures.single.failed, isFalse);
  });

  test('取消：循环顶部抛 RecognizeCancelled，未发起任何调用', () async {
    final client = ScriptedClient([
      '{"measures":[{"index":0,"confidence":0.9,"notes":[]}]}',
      '{"measures":[{"index":0,"confidence":0.9,"notes":[]}]}',
    ]);
    await expectLater(
        run(client, [tmpPage(tmp, 'a.png'), tmpPage(tmp, 'b.png')],
            cancelled: () => true),
        throwsA(isA<RecognizeCancelled>()));
    expect(client.callCount, 0);
  });

  test('交叉路径：首次空→重试异常→catch 内翻案成功；onPage 处理前回调', () async {
    final client = ScriptedClient([
      '{"measures":[]}',
      const VisionException('boom'),
      '{"measures":[{"index":0,"confidence":0.9,"notes":[]}]}',
    ]);
    final onPageCalls = <(int, int)>[];
    final ir = await run(client, [tmpPage(tmp, 'a.png')],
        onPage: (done, total) => onPageCalls.add((done, total)));
    expect(ir.tracks.single.measures.length, 1);
    expect(ir.tracks.single.measures.single.failed, isFalse);
    expect(ir.unrecognizedPages, isEmpty);
    expect(client.callCount, 3);
    expect(onPageCalls, [(0, 1)]); // 单页场景：处理该页前回调一次
  });
}
