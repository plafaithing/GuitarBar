import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/score/gtp_parser.dart';
import 'package:guitarbar/core/score/score_ir.dart';

// Bend/Whammy 解析（2026-11-04 gp8 播放能力补完）。
// 曲库真实样本无 Bend、Whammy 全 0.0 占位——合成 fixture 验证解析语义，
// 换算系数（y/4 半音、x/60 拍内位置）待真实谱校准。
void main() {
  test('parseGpif：Note 属性 Bend 曲线 → NoteIr.bend（x/60 位置、y/4 半音）', () {
    final ir = parseGpif(_bendGpif);
    final n = ir.tracks.first.measures.first.notes.first;
    expect(n.bend, isNotNull);
    expect(n.bend, hasLength(3));
    expect(n.bend![0].offset, 0.0);
    expect(n.bend![0].value, 0.0);
    expect(n.bend![1].offset, closeTo(0.5, 1e-9)); // x=30 → 0.5
    expect(n.bend![1].value, closeTo(1.0, 1e-9)); // y=4 → 1 半音
    expect(n.bend![2].offset, 1.0); // x=60 → 1.0
    expect(n.bend![2].value, closeTo(2.0, 1e-9)); // y=8 → 2 半音
  });

  test('parseGpif：Beat 属性 Whammy origin/destination → 挂拍全部音', () {
    final ir = parseGpif(_whammyGpif);
    final notes = ir.tracks.first.measures.first.notes;
    expect(notes, hasLength(2));
    for (final n in notes) {
      expect(n.whammy, [0.0, -1.5]); // 降全音半摇把
    }
  });

  test('parseGpif：Whammy 全 0（gp8 导出占位）不写入 IR', () {
    final ir = parseGpif(_whammyZeroGpif);
    final notes = ir.tracks.first.measures.first.notes;
    for (final n in notes) {
      expect(n.whammy, isNull);
    }
  });

  test('IR JSON 往返：bend/whammy 条件序列化兼容（无标注=无字段）', () {
    final ir = parseGpif(_bendGpif);
    final n = ir.tracks.first.measures.first.notes.first;
    final restored = NoteIr.fromJson(n.toJson());
    expect(restored.bend, isNotNull);
    expect(restored.bend![1].value, closeTo(1.0, 1e-9));
    // 无弯音音：无字段。
    final plain = parseGpif(_whammyZeroGpif).tracks.first.measures.first.notes.first;
    expect(plain.toJson().containsKey('bend'), isFalse);
    expect(plain.toJson().containsKey('whammy'), isFalse);
  });
}

// 单小节单拍单音 + Note 属性 Bend 三点曲线。
const _bendGpif = '''<?xml version="1.0" encoding="UTF-8"?>
<GPIF>
  <Score><Title><![CDATA[Bend Test]]></Title></Score>
  <MasterTrack><Tracks>0</Tracks><Automations><Automation><Type>Tempo</Type><Value>90 2</Value></Automation></Automations></MasterTrack>
  <Tracks><Track id="0"><Name><![CDATA[T]]></Name><Properties><Property name="Tuning"><Pitches>40 45 50 55 59 64</Pitches></Property></Properties></Track></Tracks>
  <MasterBars><MasterBar><Time>4/4</Time><Bars>0</Bars></MasterBar></MasterBars>
  <Bars><Bar id="0"><Voices>0</Voices></Bar></Bars>
  <Voices><Voice id="0"><Beats>0</Beats></Voice></Voices>
  <Beats><Beat id="0"><Rhythm ref="0" /><Notes>0</Notes></Beat></Beats>
  <Notes><Note id="0">
    <Properties>
      <Property name="String"><String>5</String></Property>
      <Property name="Fret"><Fret>3</Fret></Property>
      <Property name="Bend">
        <Curve>
          <Point x="0" y="0"/>
          <Point x="30" y="4"/>
          <Point x="60" y="8"/>
        </Curve>
      </Property>
    </Properties>
  </Note></Notes>
  <Rhythms><Rhythm id="0"><NoteValue>Quarter</NoteValue></Rhythm></Rhythms>
</GPIF>''';

// 单小节一拍双音 + Whammy origin 0 → destination -1.5。
const _whammyGpif = '''<?xml version="1.0" encoding="UTF-8"?>
<GPIF>
  <Score><Title><![CDATA[Whammy Test]]></Title></Score>
  <MasterTrack><Tracks>0</Tracks><Automations><Automation><Type>Tempo</Type><Value>90 2</Value></Automation></Automations></MasterTrack>
  <Tracks><Track id="0"><Name><![CDATA[T]]></Name><Properties><Property name="Tuning"><Pitches>40 45 50 55 59 64</Pitches></Property></Properties></Track></Tracks>
  <MasterBars><MasterBar><Time>4/4</Time><Bars>0</Bars></MasterBar></MasterBars>
  <Bars><Bar id="0"><Voices>0</Voices></Bar></Bars>
  <Voices><Voice id="0"><Beats>0</Beats></Voice></Voices>
  <Beats><Beat id="0"><Rhythm ref="0" /><Notes>0 1</Notes>
    <Properties>
      <Property name="WhammyBarOriginValue"><Float>0.000000</Float></Property>
      <Property name="WhammyBarDestinationValue"><Float>-1.500000</Float></Property>
    </Properties>
  </Beat></Beats>
  <Notes>
    <Note id="0"><Properties><Property name="String"><String>5</String></Property><Property name="Fret"><Fret>0</Fret></Property></Properties></Note>
    <Note id="1"><Properties><Property name="String"><String>4</String></Property><Property name="Fret"><Fret>2</Fret></Property></Properties></Note>
  </Notes>
  <Rhythms><Rhythm id="0"><NoteValue>Quarter</NoteValue></Rhythm></Rhythms>
</GPIF>''';

// 全 0 占位（gp8 导出常态）→ 不写 IR。
const _whammyZeroGpif = '''<?xml version="1.0" encoding="UTF-8"?>
<GPIF>
  <Score><Title><![CDATA[Whammy Zero]]></Title></Score>
  <MasterTrack><Tracks>0</Tracks><Automations><Automation><Type>Tempo</Type><Value>90 2</Value></Automation></Automations></MasterTrack>
  <Tracks><Track id="0"><Name><![CDATA[T]]></Name><Properties><Property name="Tuning"><Pitches>40 45 50 55 59 64</Pitches></Property></Properties></Track></Tracks>
  <MasterBars><MasterBar><Time>4/4</Time><Bars>0</Bars></MasterBar></MasterBars>
  <Bars><Bar id="0"><Voices>0</Voices></Bar></Bars>
  <Voices><Voice id="0"><Beats>0</Beats></Voice></Voices>
  <Beats><Beat id="0"><Rhythm ref="0" /><Notes>0</Notes>
    <Properties>
      <Property name="WhammyBarOriginValue"><Float>0.000000</Float></Property>
      <Property name="WhammyBarDestinationValue"><Float>0.000000</Float></Property>
    </Properties>
  </Beat></Beats>
  <Notes><Note id="0"><Properties><Property name="String"><String>5</String></Property><Property name="Fret"><Fret>0</Fret></Property></Properties></Note></Notes>
  <Rhythms><Rhythm id="0"><NoteValue>Quarter</NoteValue></Rhythm></Rhythms>
</GPIF>''';
