import 'note.dart';

enum TuningGroup { standardDown, drop, open, special, custom }

extension TuningGroupLabel on TuningGroup {
  String get label => switch (this) {
        TuningGroup.standardDown => '标准/降调',
        TuningGroup.drop => 'Drop',
        TuningGroup.open => 'Open',
        TuningGroup.special => '特殊',
        TuningGroup.custom => '自定义',
      };
}

class TuningPreset {
  final String id;
  final String name;
  final List<Note> strings; // 低音弦 → 高音弦
  final TuningGroup group;
  final bool isBuiltIn;

  const TuningPreset({
    required this.id,
    required this.name,
    required this.strings,
    required this.group,
    this.isBuiltIn = false,
  });

  TuningPreset copyWith({String? name, List<Note>? strings, TuningGroup? group}) =>
      TuningPreset(
        id: id,
        name: name ?? this.name,
        strings: strings ?? this.strings,
        group: group ?? this.group,
        isBuiltIn: isBuiltIn,
      );
}
