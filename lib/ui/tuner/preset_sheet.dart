import 'package:flutter/material.dart';

import '../../core/music/builtin_tunings.dart';
import '../../core/music/tuning.dart';
import '../../state/tuning_state.dart';
import '../theme.dart';

/// 调弦预设选择面板（抽屉式浮层）。
///
/// 纯表现层：只读 [TuningState] 的数据，选择/新建/复制/删除全部通过回调交给
/// 调音页处理，因此可以脱离数据库单独渲染（见 test/preset_sheet_test.dart）。
///
/// 版式：标题头 + 可折叠分组（自定义置顶、其余四组默认收起，只展开当前预设
/// 所在组）；当前项用中性药丸底 + 勾标，行尾只留一个「更多」菜单。
class PresetSheet extends StatefulWidget {
  const PresetSheet({
    super.key,
    required this.state,
    required this.onSelect,
    required this.onCreate,
    required this.onDuplicate,
    required this.onDelete,
  });

  final TuningState state;
  final ValueChanged<TuningPreset> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<TuningPreset> onDuplicate;
  final ValueChanged<TuningPreset> onDelete;

  @override
  State<PresetSheet> createState() => _PresetSheetState();
}

class _PresetSheetState extends State<PresetSheet> {
  /// 内置四组的展示顺序。
  static const List<TuningGroup> _groups = [
    TuningGroup.standardDown,
    TuningGroup.drop,
    TuningGroup.open,
    TuningGroup.special,
  ];

  /// 展开的分组 key：自定义固定为 `custom`，内置组为 `group:<enum>`。
  final Set<String> _open = {};

  static String _groupKey(TuningGroup g) => 'group:${g.name}';
  static const String _customKey = 'custom';

  @override
  void initState() {
    super.initState();
    // 默认展开「自定义」（空组也展开，好让新用户看到提示与「新建」入口）
    // 与当前预设所在组，其余收起。
    _open.add(_customKey);
    _open.add(_groupKey(widget.state.current.group));
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
      child: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) {
          final sections = _sections(context);
          return Column(children: [
            _header(context),
            Divider(height: 1, thickness: 1, color: p.rule),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                children: sections,
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _header(BuildContext context) {
    final p = context.palette;
    final total = widget.state.custom.length + builtinTunings.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('调弦预设',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                      height: 1.1,
                      color: p.ink)),
              const SizedBox(height: 3),
              Text('共 $total 种 · 选择后立即生效',
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

  /// 组装分组：自定义 → 四个内置组；组间用 1px 发丝线分隔。
  List<Widget> _sections(BuildContext context) {
    final p = context.palette;
    final out = <Widget>[];
    var first = true;

    void section(String key, String label, int count,
        {bool action = false, required List<Widget> rows}) {
      if (!first) out.add(Divider(height: 1, thickness: 1, color: p.rule));
      first = false;
      final expanded = _open.contains(key);
      out.add(_sectionHeader(
        label,
        count: count,
        expanded: expanded,
        action: action,
        onToggle: () => setState(
            () => expanded ? _open.remove(key) : _open.add(key)),
      ));
      if (expanded) out.addAll(rows);
    }

    final custom = widget.state.custom;
    section(
      _customKey,
      '自定义',
      custom.length,
      action: true,
      rows: [
        if (custom.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
            child: Text(
              '还没有自定义调弦。点右上「新建」，命名后六根弦逐个选音高。',
              style: TextStyle(fontSize: 12, height: 1.5, color: p.muted),
            ),
          ),
        for (final t in custom) _row(t, isCustom: true),
      ],
    );

    for (final g in _groups) {
      final items = builtinTunings.where((x) => x.group == g).toList();
      section(
        _groupKey(g),
        g.label,
        items.length,
        rows: [for (final t in items) _row(t, isCustom: false)],
      );
    }
    return out;
  }

  /// 分组标题行：整行可点（折叠/展开）；右侧可带「新建」动作。
  Widget _sectionHeader(
    String label, {
    required int count,
    required bool expanded,
    required VoidCallback onToggle,
    bool action = false,
  }) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(children: [
                AnimatedRotation(
                  turns: expanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Icons.keyboard_arrow_down,
                      size: 18, color: p.muted),
                ),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 15,
                        color: p.ink)),
                const SizedBox(width: 8),
                Text('$count',
                    style: TextStyle(
                        fontSize: 11,
                        color: p.muted,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
          ),
        ),
        if (action)
          TextButton.icon(
            onPressed: widget.onCreate,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('新建'),
            style: TextButton.styleFrom(
              foregroundColor: p.ink,
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ]),
    );
  }

  /// 预设行：名称 + 六根弦音名；当前项整行药丸底、勾标，行尾「更多」菜单。
  Widget _row(TuningPreset t, {required bool isCustom}) {
    final p = context.palette;
    final current = widget.state.current.id == t.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: current ? p.activePill : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => widget.onSelect(t),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 17,
                            color: p.ink)),
                    const SizedBox(height: 3),
                    Text(
                      t.strings.map((n) => n.name).join('  '),
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.6,
                          color: p.muted,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
              ),
              if (current)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.check_circle_rounded,
                      size: 18, color: p.positive),
                )
              else
                PopupMenuButton<String>(
                  tooltip: '更多',
                  icon: Icon(Icons.more_horiz, size: 18, color: p.muted),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  itemBuilder: (context) => [
                    if (isCustom)
                      const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除这个预设',
                              style: TextStyle(fontSize: 14)))
                    else
                      const PopupMenuItem(
                          value: 'copy',
                          child: Text('复制为新预设',
                              style: TextStyle(fontSize: 14))),
                  ],
                  onSelected: (v) =>
                      v == 'delete' ? widget.onDelete(t) : widget.onDuplicate(t),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
