import 'note.dart';
import 'tuning.dart';

TuningPreset _t(String name, TuningGroup g, List<String> notes) => TuningPreset(
      id: 'builtin-$name',
      name: name,
      strings: notes.map(Note.parse).toList(),
      group: g,
      isBuiltIn: true,
    );

final List<TuningPreset> builtinTunings = [
  // 标准/降调
  _t('Standard', TuningGroup.standardDown, ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']),
  _t('Half Step Down', TuningGroup.standardDown, ['Eb2', 'Ab2', 'Db3', 'Gb3', 'Bb3', 'Eb4']),
  _t('Full Step Down', TuningGroup.standardDown, ['D2', 'G2', 'C3', 'F3', 'A3', 'D4']),
  _t('1.5 Steps Down', TuningGroup.standardDown, ['C#2', 'F#2', 'B2', 'E3', 'G#3', 'C#4']),
  _t('Two Steps Down', TuningGroup.standardDown, ['C2', 'F2', 'Bb2', 'Eb3', 'G3', 'C4']),
  // Drop
  _t('Drop D', TuningGroup.drop, ['D2', 'A2', 'D3', 'G3', 'B3', 'E4']),
  _t('Drop C', TuningGroup.drop, ['C2', 'G2', 'C3', 'F3', 'A3', 'D4']),
  _t('Drop B', TuningGroup.drop, ['B1', 'F#2', 'B2', 'E3', 'G#3', 'C#4']),
  _t('Drop A', TuningGroup.drop, ['A1', 'E2', 'A2', 'D3', 'F#3', 'B3']),
  // Open
  _t('Open D', TuningGroup.open, ['D2', 'A2', 'D3', 'F#3', 'A3', 'D4']),
  _t('Open E', TuningGroup.open, ['E2', 'B2', 'E3', 'G#3', 'B3', 'E4']),
  _t('Open G', TuningGroup.open, ['D2', 'G2', 'D3', 'G3', 'B3', 'D4']),
  _t('Open A', TuningGroup.open, ['E2', 'A2', 'E3', 'A3', 'C#4', 'E4']),
  _t('Open C', TuningGroup.open, ['C2', 'G2', 'C3', 'G3', 'C4', 'E4']),
  _t('Open F', TuningGroup.open, ['F2', 'A2', 'C3', 'F3', 'A3', 'F4']),
  _t('Open D Minor', TuningGroup.open, ['D2', 'A2', 'D3', 'F3', 'A3', 'D4']),
  // 特殊
  _t('DADGAD', TuningGroup.special, ['D2', 'A2', 'D3', 'G3', 'A3', 'D4']),
  _t('Modal D', TuningGroup.special, ['D2', 'A2', 'D3', 'E3', 'A3', 'D4']),
  _t('Nashville (High Strung)', TuningGroup.special, ['E3', 'A3', 'D4', 'G4', 'B4', 'E5']),
  _t('All Fourths', TuningGroup.special, ['E2', 'A2', 'D3', 'G3', 'C4', 'F4']),
];
