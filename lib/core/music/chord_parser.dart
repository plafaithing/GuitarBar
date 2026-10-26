class ParsedChord {
  final int rootPc;
  final List<int> intervals;
  const ParsedChord(this.rootPc, this.intervals);
}

const _qualities = <String, List<int>>{
  '': [0, 4, 7], 'm': [0, 3, 7], '7': [0, 4, 7, 10], 'm7': [0, 3, 7, 10],
  'maj7': [0, 4, 7, 11], 'dim': [0, 3, 6], 'aug': [0, 4, 8],
  'sus2': [0, 2, 7], 'sus4': [0, 5, 7], 'm7b5': [0, 3, 6, 10],
  '6': [0, 4, 7, 9], 'm6': [0, 3, 7, 9], 'add9': [0, 4, 7, 14],
  '9': [0, 4, 7, 10, 14], 'm9': [0, 3, 7, 10, 14], '5': [0, 7],
};

const _basePc = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

ParsedChord parseChord(String input) {
  final m = RegExp(r'^\s*([A-G][#b]?)(.*)$').firstMatch(input);
  if (m == null) throw ArgumentError('无法解析和弦: $input');
  final rootToken = m.group(1)!;
  var rootPc = _basePc[rootToken[0]]!;
  if (rootToken.endsWith('#')) rootPc += 1;
  if (rootToken.endsWith('b')) rootPc -= 1;
  rootPc = (rootPc % 12 + 12) % 12;
  final intervals = _qualities[m.group(2)!];
  if (intervals == null) throw ArgumentError('不支持和弦类型 "${m.group(2)}" ($input)');
  return ParsedChord(rootPc, intervals);
}
