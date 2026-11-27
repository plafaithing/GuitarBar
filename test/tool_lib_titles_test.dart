// 定位曲库内各谱标题（找 Like A Star）。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: avoid_print
import 'package:guitarbar/core/score/gp34_parser.dart';
import 'package:guitarbar/core/score/gp5_parser.dart';
import 'package:guitarbar/core/score/gtp12_parser.dart';

String? _flavor(List<int> bytes) {
  if (bytes.length < 31) return null;
  final size = bytes[0];
  final raw = String.fromCharCodes(bytes.sublist(1, 31));
  final v = (size < 1 ? '' : raw.substring(0, size < 30 ? size : 30)).trim();
  if (v.contains('v5.')) return 'gp5';
  if (v.contains('v3.') || v.contains('v4.') || v.contains('L4.')) return 'gp34';
  if (v.contains('v1') || v.contains('v2') || v.contains('GUITARE')) return 'gtp12';
  return null;
}

void main() {
  test('曲库标题清单', () {
    final dir = Directory(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores');
    for (final d in dir.listSync()) {
      if (d is! Directory) continue;
      for (final x in d.listSync()) {
        if (x is! File) continue;
        final ext = x.path.toLowerCase().split('.').last;
        if (!['gp3', 'gp4', 'gp5', 'gtp', 'gpx'].contains(ext)) continue;
        String title;
        try {
          final bytes = Uint8List.fromList(x.readAsBytesSync());
          final head = String.fromCharCodes(bytes.sublist(0, 4));
          if (ext == 'gpx' || head == 'BCFZ' || head.startsWith('PK')) {
            title = '(gpx)';
          } else {
            switch (_flavor(bytes)) {
              case 'gp5':
                title = parseGp5Bytes(bytes).title;
              case 'gp34':
                title = parseGp34Bytes(bytes).title;
              case 'gtp12':
                title = parseGtp12Bytes(bytes).title;
              default:
                title = '(未知)';
            }
          }
        } catch (e) {
          title = 'ERR $e';
        }
        print('${d.path.split('\\').last}: $ext "${title.replaceAll('\n', ' ')}"');
      }
    }
  });
}
