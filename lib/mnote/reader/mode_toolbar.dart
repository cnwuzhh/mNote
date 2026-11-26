import 'package:material_ui/material_ui.dart';

import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

enum WorkMode {
  excerpt('摘录'),
  handwrite('手写'),
  organize('整理'),
  recall('回忆');

  new(this.label);
  final String label;
}

/// Tools of the excerpt mode.
enum ExcerptTool { text, box, highlight }

/// Floating toolbar at the bottom of the reader. Switching mode swaps the
/// whole tool group. In M1 only the excerpt mode is functional; the other
/// modes show their tools disabled.
class ModeToolbar extends StatelessWidget {
  const new({
    super.key,
    required this.mode,
    required this.onMode,
    required this.color,
    required this.onColor,
    required this.tool,
    required this.onTool,
  });

  final WorkMode mode;
  final ValueChanged<WorkMode> onMode;
  final ExcerptColor color;
  final ValueChanged<ExcerptColor> onColor;
  final ExcerptTool tool;
  final ValueChanged<ExcerptTool> onTool;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    return Material(
      color: p.paper2,
      elevation: 2,
      shadowColor: Colors.black12,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.line),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in WorkMode.values)
                _Seg(
                  key: ValueKey('mode-${m.name}'),
                  label: m.label,
                  selected: m == mode,
                  onTap: () => onMode(m),
                ),
              Container(
                width: 1,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: p.line,
              ),
              ..._tools(context, p),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _tools(BuildContext context, MnotePalette p) {
    switch (mode) {
      case WorkMode.excerpt:
        return [
          for (final c in ExcerptColor.values)
            Tooltip(
              message: c.label,
              child: InkResponse(
                key: ValueKey('tool-color-${c.name}'),
                radius: 18,
                onTap: () => onColor(c),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c.ink(dark: p.dark),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c == color ? p.ink : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          _Tool(
            key: const ValueKey('tool-text'),
            icon: Icons.text_fields,
            label: '文字',
            selected: tool == ExcerptTool.text,
            onTap: () => onTool(ExcerptTool.text),
          ),
          _Tool(
            key: const ValueKey('tool-box'),
            icon: Icons.crop_free,
            label: '框选',
            selected: tool == ExcerptTool.box,
            onTap: () => onTool(ExcerptTool.box),
          ),
          _Tool(
            key: const ValueKey('tool-highlight'),
            icon: Icons.border_color_outlined,
            label: '高亮',
            selected: tool == ExcerptTool.highlight,
            onTap: () => onTool(ExcerptTool.highlight),
          ),
        ];
      case WorkMode.handwrite:
        return _soon(p, const [
          (Icons.edit_outlined, '钢笔'),
          (Icons.brush_outlined, '荧光笔'),
          (Icons.cleaning_services_outlined, '橡皮'),
          (Icons.gesture, '套索'),
        ]);
      case WorkMode.organize:
        return _soon(p, const [
          (Icons.open_with, '拖拽'),
          (Icons.merge_type, '合并'),
          (Icons.format_list_bulleted, '大纲'),
          (Icons.auto_awesome_mosaic_outlined, '自动排版'),
        ]);
      case WorkMode.recall:
        return _soon(p, const [
          (Icons.visibility_off_outlined, '遮挡'),
          (Icons.visibility_outlined, '揭示'),
          (Icons.event_repeat, '加入复习'),
        ]);
    }
  }

  List<Widget> _soon(MnotePalette p, List<(IconData, String)> tools) => [
    for (final (icon, label) in tools)
      _Tool(icon: icon, label: label, selected: false, onTap: null),
    Padding(
      padding: const EdgeInsets.only(left: 6, right: 6),
      child: Text('后续版本', style: TextStyle(fontSize: 12, color: p.ink3)),
    ),
  ];
}

class _Seg extends StatelessWidget {
  const new({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    return Material(
      color: selected ? p.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: selected ? p.paper : p.ink2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const new({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    final enabled = onTap != null;
    final fg = !enabled
        ? p.ink3.withValues(alpha: 0.55)
        : (selected ? p.accent : p.ink2);
    return Material(
      color: selected ? p.accent.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 14, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
