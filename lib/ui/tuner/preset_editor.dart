import 'package:flutter/material.dart';

import '../../core/music/note.dart';
import '../../core/music/tuning.dart';
import '../../state/tuning_state.dart';
import '../theme.dart';

/// 打开「新建 / 复制」自定义调弦编辑器。
///
/// 新建或复制成功后写入 [TuningState.custom] 并关闭浮层；名称为空就地报错，
/// 不静默吞掉（旧版用 SnackBar，浮层一关就看不见了）。
Future<void> showPresetEditor(
  BuildContext context,
  TuningState state, {
  TuningPreset? base,
}) async {
  final mq = MediaQuery.of(context);
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        // 只限宽：高度由内容决定（6 行弦 + 页头页脚，不撑满屏幕）。
        width: (mq.size.width * 0.9).clamp(320.0, 420.0),
        child: PresetEditor(state: state, base: base),
      ),
    ),
  );
}

/// 自定义调弦编辑面板：名称 + 六根弦逐弦选音高。
class PresetEditor extends StatefulWidget {
  const PresetEditor({super.key, required this.state, this.base});

  final TuningState state;

  /// 非空 = 复制该预设为新的自定义预设。
  final TuningPreset? base;

  @override
  State<PresetEditor> createState() => _PresetEditorState();
}

class _PresetEditorState extends State<PresetEditor> {
  static final List<Note> _allNotes = [for (var m = 28; m <= 88; m++) Note(m)];

  late final TextEditingController _name;
  late final List<Note> _picked;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
        text: widget.base != null ? '${widget.base!.name} 副本' : '');
    _picked = List<Note>.from(widget.base?.strings ??
        [
          Note.parse('E2'),
          Note.parse('A2'),
          Note.parse('D3'),
          Note.parse('G3'),
          Note.parse('B3'),
          Note.parse('E4'),
        ]);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final trimmed = _name.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _nameError = '给它起个名字');
      return;
    }
    widget.state
        .addCustom(trimmed, _picked.map((n) => n.name).toList());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _header(context),
        Divider(height: 1, thickness: 1, color: p.rule),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(context, '名称'),
                const SizedBox(height: 6),
                TextField(
                  controller: _name,
                  autofocus: true,
                  onChanged: (_) {
                    if (_nameError != null) setState(() => _nameError = null);
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.base != null ? '给副本起个名字' : '例如：我常用的 Open C',
                    errorText: _nameError,
                    filled: true,
                    fillColor: p.ground,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: p.controlBorder)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: p.controlBorder)),
                  ),
                  style: TextStyle(fontSize: 15, color: p.ink),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  _label(context, '六根弦音高'),
                  const SizedBox(width: 8),
                  Text('从低音到高音',
                      style: TextStyle(fontSize: 11, color: p.muted)),
                ]),
                const SizedBox(height: 8),
                for (var i = 0; i < 6; i++) _stringRow(context, i),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: p.rule),
        _footer(context),
      ]),
    );
  }

  Widget _header(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.base != null ? '复制为新调弦' : '新建调弦',
                  style: TextStyle(
                      fontSize: 22,
                      height: 1.1,
                      color: p.ink)),
              const SizedBox(height: 3),
              Text('保存后出现在「自定义」组，数量不限',
                  style: TextStyle(fontSize: 12, color: p.muted)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          tooltip: '关闭',
          color: p.muted,
          onPressed: () => Navigator.pop(context),
        ),
      ]),
    );
  }

  Widget _label(BuildContext context, String text) => Text(text,
      style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: context.palette.muted));

  /// 单根弦一行：弦序标签 + 音高下拉。第 0 行是 6 弦（最低音）。
  Widget _stringRow(BuildContext context, int i) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(
          width: 52,
          child: Text('${6 - i} 弦',
              style: TextStyle(
                  fontSize: 15,
                  color: p.ink)),
        ),
        Expanded(
          child: DropdownButtonFormField<Note>(
            // Flutter 3.47：value 已弃用，改用 initialValue。
            initialValue: _picked[i],
            isDense: true,
            isExpanded: true,
            // 显式给箭头颜色：这套色板下 M3 角色色偏淡，默认箭头几乎看不见。
            icon: Icon(Icons.expand_more, size: 18, color: p.muted),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: p.ground,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: p.controlBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: p.controlBorder)),
            ),
            style: TextStyle(
                fontSize: 14, color: p.ink, fontFeatures: const [
              FontFeature.tabularFigures()
            ]),
            items: [
              for (final n in _allNotes)
                DropdownMenuItem(value: n, child: Text(n.name)),
            ],
            onChanged: (n) => setState(() {
              if (n != null) _picked[i] = n;
            }),
          ),
        ),
      ]),
    );
  }

  Widget _footer(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: p.muted),
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: p.primary,
            foregroundColor: p.ground,
            minimumSize: const Size(88, 40),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('保存'),
        ),
      ]),
    );
  }
}
