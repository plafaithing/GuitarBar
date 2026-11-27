// 一次性诊断：全曲库 gpx 扫描——GPVersion + Property name 频次 + Tie 上下文。
// 目的：确认 LAS(80) 的 gpif 版本；对照其他 GP6 文件的 hopo/slide Property 分布。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:guitarbar/core/score/gtp_parser.dart';

void main() {
  test('全曲库 gpx prop 扫描', () {
    final root = Directory(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores');
    final out = <String>[];
    for (final d in root.listSync().whereType<Directory>()) {
      final f = File('${d.path}\\source.gpx');
      if (!f.existsSync()) continue;
      try {
        final gpif = gpifBytes(Uint8List.fromList(f.readAsBytesSync()));
        final xml = String.fromCharCodes(gpif);
        // GPVersion / GPRevision
        final ver = RegExp(r'<GPVersion>([^<]*)</GPVersion>').firstMatch(xml);
        final rev = RegExp(r'<GPRevision>([^<]*)</GPRevision>').firstMatch(xml);
        // Property name 频次
        final prRe = RegExp(r'<Property name="([^"]+)"');
        final prs = <String, int>{};
        for (final m in prRe.allMatches(xml)) {
          prs[m.group(1)!] = (prs[m.group(1)!] ?? 0) + 1;
        }
        final tieCount = RegExp(r'<Tie').allMatches(xml).length;
        final tieDest =
            RegExp(r'destination="true"').allMatches(xml).length;
        final slideCount = RegExp(r'<Slide').allMatches(xml).length;
        final hopoCount =
            RegExp(r'Hopo(Origin|Destination)').allMatches(xml).length;
        out.add('== ${d.uri.pathSegments.last} ${f.uri.pathSegments.last} '
            '(${f.lengthSync()}B) ==');
        out.add(
            'GPVersion=${ver?.group(1)} GPRevision=${rev?.group(1)} '
            'Tie=$tieCount(tieDest=$tieDest) SlideTag=$slideCount '
            'HopoProp=$hopoCount');
        final sorted = prs.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        out.add('Properties: ${sorted.map((e) => '${e.key}:${e.value}').join(', ')}');
      } catch (e) {
        out.add('== ${d.uri.pathSegments.last} == ERROR $e');
      }
    }
    File(r'D:\workplace\code\GuitarBar\tasks\gpx_prop_scan_out.txt')
        .writeAsStringSync(out.join('\n'));
  });
}
