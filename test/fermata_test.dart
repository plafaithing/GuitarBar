// Fermata 延长记号解析（2026-11-07 gp8 对照补完；月下之恋 8 处真值形态）。
import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';

void main() {
  test('parseGpif：MasterBar Fermatas → MeasureIr.fermatas（分数拍位+延长比例）',
      () {
    final ir = parseGpif(_fermataGpif);
    final m0 = ir.tracks.first.measures[0];
    expect(m0.fermatas, hasLength(2));
    // Offset "0/1" → beat 0；Length 0.46。
    expect(m0.fermatas[0].beat, 0.0);
    expect(m0.fermatas[0].length, closeTo(0.46, 1e-9));
    // Offset "5/4" → beat 1.25（分数换算）。
    expect(m0.fermatas[1].beat, closeTo(1.25, 1e-9));
    // 无 fermata 的小节：空列表 + JSON 不写字段（存量兼容）。
    final m1 = ir.tracks.first.measures[1];
    expect(m1.fermatas, isEmpty);
    expect(m1.toJson().containsKey('fermatas'), isFalse);
  });
}

const _fermataGpif = '''<?xml version="1.0" encoding="UTF-8"?>
<GPIF>
  <Score><Title><![CDATA[Fermata Test]]></Title></Score>
  <MasterTrack><Tracks>0</Tracks><Automations><Automation><Type>Tempo</Type><Value>90 2</Value></Automation></Automations></MasterTrack>
  <Tracks><Track id="0"><Name><![CDATA[T]]></Name><Properties><Property name="Tuning"><Pitches>40 45 50 55 59 64</Pitches></Property></Properties></Track></Tracks>
  <MasterBars>
    <MasterBar><Time>4/4</Time><Bars>0</Bars>
      <Fermatas>
        <Fermata><Type>Medium</Type><Offset>0/1</Offset><Length>0.46</Length></Fermata>
        <Fermata><Type>Medium</Type><Offset>5/4</Offset><Length>0.46</Length></Fermata>
      </Fermatas>
    </MasterBar>
    <MasterBar><Time>4/4</Time><Bars>1</Bars></MasterBar>
  </MasterBars>
  <Bars><Bar id="0"><Voices>0</Voices></Bar><Bar id="1"><Voices>1</Voices></Bar></Bars>
  <Voices><Voice id="0"><Beats>0</Beats></Voice><Voice id="1"><Beats>1</Beats></Voice></Voices>
  <Beats>
    <Beat id="0"><Rhythm ref="0" /><Notes>0</Notes></Beat>
    <Beat id="1"><Rhythm ref="0" /><Notes>1</Notes></Beat>
  </Beats>
  <Notes>
    <Note id="0"><Properties><Property name="String"><String>5</String></Property><Property name="Fret"><Fret>0</Fret></Property></Properties></Note>
    <Note id="1"><Properties><Property name="String"><String>4</String></Property><Property name="Fret"><Fret>2</Fret></Property></Properties></Note>
  </Notes>
  <Rhythms><Rhythm id="0"><NoteValue>Quarter</NoteValue></Rhythm></Rhythms>
</GPIF>''';
