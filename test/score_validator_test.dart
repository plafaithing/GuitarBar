import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/vision/score_validator.dart';

void main() {
  test('近拍同弦去重：保留带技法者（"写两遍"防线）', () {
    final r = parsePage(
        '{"measures":[{"index":0,"confidence":0.9,"notes":['
        '{"beat":1.0,"duration":0.5,"string":2,"fret":12,"technique":null},'
        '{"beat":1.02,"duration":0.5,"string":2,"fret":12,"technique":"H"},'
        '{"beat":1.0,"duration":0.5,"string":1,"fret":0,"technique":null}]}]}',
        indexOffset: 0);
    final notes = r.measures.single.notes;
    expect(notes.length, 2, reason: '同弦近拍双音去重为一，跨弦保留');
    expect(notes.first.technique, 'H', reason: '带技法者胜出');
    expect(notes.first.string, 2);
    expect(notes.last.string, 1);
  });

  test('完全同拍同弦（双音和弦写法）同样去重', () {
    final r = parsePage(
        '{"measures":[{"index":0,"confidence":0.9,"notes":['
        '{"beat":0,"duration":1,"string":3,"fret":5,"technique":null},'
        '{"beat":0,"duration":1,"string":3,"fret":5,"technique":null}]}]}',
        indexOffset: 0);
    expect(r.measures.single.notes.length, 1);
  });

  test('干净 JSON 直接解析', () {
    final r = parsePage(
        '{"measures":[{"index":0,"confidence":0.9,"notes":'
        '[{"beat":0,"duration":1,"string":1,"fret":3,"technique":null}]}]}',
        indexOffset: 5);
    expect(r.measures.single.index, 5);
    expect(r.measures.single.notes.single.fret, 3);
    expect(r.failedCount, 0);
    expect(r.capo, 0); // 无 capo 字段按 0
  });

  test('capo 字段：谱面标注读取，坏值按 0', () {
    final r = parsePage(
        '{"capo":2,"measures":[{"index":0,"confidence":0.9,"notes":'
        '[{"beat":0,"duration":1,"string":1,"fret":3,"technique":null}]}]}',
        indexOffset: 0);
    expect(r.capo, 2);
    final bad = parsePage(
        '{"capo":"x","measures":[{"index":0,"confidence":0.9,"notes":'
        '[{"beat":0,"duration":1,"string":1,"fret":3,"technique":null}]}]}',
        indexOffset: 0);
    expect(bad.capo, 0); // 非 num 不废整页
    final clamped = parsePage(
        '{"capo":99,"measures":[]}', indexOffset: 0);
    expect(clamped.capo, 7); // 越界夹到 0-7
  });

  test('剥 Markdown 围栏', () {
    final r = parsePage('```json\n{"measures":[{"index":0,"confidence":0.8,'
        '"notes":[]}]}\n```', indexOffset: 0);
    expect(r.measures.length, 1);
  });

  test('越界音符 → 整小节 failed（不静默丢）', () {
    final r = parsePage(
        '{"measures":[{"index":0,"confidence":0.9,"notes":'
        '[{"beat":0,"duration":1,"string":9,"fret":3,"technique":null}]}]}',
        indexOffset: 0);
    expect(r.measures.single.failed, isTrue);
    expect(r.measures.single.notes, isEmpty);
    expect(r.failedCount, 1);
  });

  test('technique 白名单外的值 → failed', () {
    final r = parsePage(
        '{"measures":[{"index":0,"confidence":0.9,"notes":'
        '[{"beat":0,"duration":1,"string":1,"fret":0,"technique":"zz"}]}]}',
        indexOffset: 0);
    expect(r.measures.single.failed, isTrue);
  });

  test('H 泛音在白名单内', () {
    final r = parsePage(
        '{"measures":[{"index":0,"confidence":0.9,"notes":'
        '[{"beat":0,"duration":1,"string":1,"fret":12,"technique":"H"}]}]}',
        indexOffset: 0);
    expect(r.measures.single.failed, isFalse);
    expect(r.measures.single.notes.single.technique, 'H');
  });

  test('bad duration（<=0）→ failed', () {
    final r = parsePage(
        '{"measures":[{"index":0,"confidence":0.9,"notes":'
        '[{"beat":0,"duration":0,"string":1,"fret":0,"technique":null}]}]}',
        indexOffset: 0);
    expect(r.measures.single.failed, isTrue);
  });

  test('字符串化数字（"beat":"0"）→ 该音不合法整小节 failed，不抛 TypeError', () {
    final r = parsePage(
        '{"measures":[{"index":0,"confidence":0.9,"notes":'
        '[{"beat":"0","duration":1,"string":1,"fret":3,"technique":null}]}]}',
        indexOffset: 0);
    expect(r.measures.single.failed, isTrue);
    expect(r.measures.single.notes, isEmpty);
    expect(r.failedCount, 1);
  });

  test('confidence 缺省 0.5，越界夹到 [0,1]', () {
    final r = parsePage(
        '{"measures":[{"notes":[{"beat":0,"duration":1,"string":1,'
        '"fret":0,"technique":null,"confidence":3}]}]}',
        indexOffset: 0);
    expect(r.measures.single.confidence, 0.5);
    expect(r.measures.single.notes.single.confidence, 1.0);
  });

  test('index 按数组位置重编（不信 AI 的编号）', () {
    final r = parsePage(
        '{"measures":[{"index":99,"confidence":0.9,"notes":[]},'
        '{"index":42,"confidence":0.9,"notes":[]}]}',
        indexOffset: 10);
    expect(r.measures.map((m) => m.index), [10, 11]);
  });

  test('外层数组包对象也能解析（_extractJson 剥掉根数组的副产物，pin 住）', () {
    final r = parsePage(
        '[{"measures":[{"index":0,"confidence":0.9,"notes":[]}]}]',
        indexOffset: 0);
    expect(r.measures.length, 1);
    expect(r.failedCount, 0);
  });

  test('截断 JSON → FormatException（8192 token 截断的页级失败模式）', () {
    expect(
        () => parsePage(
            '{"measures":[{"index":0,"confidence":0.9,"notes":'
            '[{"beat":0,"duration":1,"string":1,"fret":3,"technique":null}',
            indexOffset: 0),
        throwsFormatException);
  });

  test('完全没有 JSON → FormatException（页级失败）', () {
    expect(() => parsePage('我不知道', indexOffset: 0), throwsFormatException);
  });
}
