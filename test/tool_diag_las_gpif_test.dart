// 一次性诊断：LAS(80) gpif 全标记穷举——弧线信息存在性终极检查。
// heavy：硬编码曲库 id（80→83 漂移）——使命完成（对照解析定案 hopo=0、
// 结论落 spec §4.2/§4.3），日常套件跳过。
@Tags(['heavy'])
library;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/gtp_parser.dart';

void main() {
  test('LAS gpif 全标记穷举',
      skip: '一次性诊断已完结（结论落 spec §4.2/§4.3）；曲库 id 漂移'
          ' 80→83→已删，需用时改路径重启用', () {
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\80\source.gpx');
    final gpif = gpifBytes(Uint8List.fromList(f.readAsBytesSync()));
    final xml = String.fromCharCodes(gpif);
    final out = <String>[];
    // 全部元素名（<Name 与 </Name）
    final elRe = RegExp(r'</?([A-Za-z][A-Za-z0-9]*)');
    final els = <String, int>{};
    for (final m in elRe.allMatches(xml)) {
      els[m.group(1)!] = (els[m.group(1)!] ?? 0) + 1;
    }
    out.add('== 元素名 ==');
    final elSorted = els.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final e in elSorted) {
      out.add('${e.key}: ${e.value}');
    }
    // 全部 Property name 值
    final prRe = RegExp(r'<Property name="([^"]+)"');
    final prs = <String, int>{};
    for (final m in prRe.allMatches(xml)) {
      prs[m.group(1)!] = (prs[m.group(1)!] ?? 0) + 1;
    }
    out.add('== Property name ==');
    for (final e in prs.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
      out.add('${e.key}: ${e.value}');
    }
    // 全部 XProperty id
    final xpRe = RegExp(r'<XProperty id="(\d+)"');
    final xps = <String, int>{};
    for (final m in xpRe.allMatches(xml)) {
      xps[m.group(1)!] = (xps[m.group(1)!] ?? 0) + 1;
    }
    out.add('== XProperty id ==');
    for (final e in xps.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
      out.add('${e.key}: ${e.value}');
    }
    File(r'D:\workplace\code\GuitarBar\tasks\las_gpif_tags_out.txt')
        .writeAsStringSync(out.join('\n'));
  });
}
