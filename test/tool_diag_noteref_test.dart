// tap 膨胀根因：同 noteId 是否被多个 beat 引用（id 复用检查）。
@Tags(['heavy'])
library;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';

void main() {
  test('noteId 引用复用检查', () {
    final f = File(
        r'D:\workplace\code\GuitarBar\build\windows\x64\runner\Release\data\scores\83\source.gpx');
    final bytes = Uint8List.fromList(f.readAsBytesSync());
    final xml = String.fromCharCodes(gpifBytes(bytes));
    // 每个 <Beat>…<Notes>A B C</Notes> 的引用展开计数
    final refRe = RegExp(r'<Beat id="(\d+)">[\s\S]*?<Notes>([^<]*)</Notes>');
    final noteRefCount = <String, int>{};
    for (final m in refRe.allMatches(xml)) {
      for (final ref in m.group(2)!.trim().split(RegExp(r'\s+'))) {
        if (ref.isEmpty) continue;
        noteRefCount[ref] = (noteRefCount[ref] ?? 0) + 1;
      }
    }
    final reused = noteRefCount.entries.where((e) => e.value > 1).length;
    debugPrint('不同 noteId 引用数=${noteRefCount.length} 复用>1 的=$reused');
    final top = noteRefCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in top.take(8)) {
      debugPrint('  noteId=${e.key} 被引 ${e.value} 次');
    }
    // 全 <Note id=> 定义数
    final defCount = RegExp(r'<Note id=').allMatches(xml).length;
    debugPrint('Note 定义数=$defCount');
  });
}
