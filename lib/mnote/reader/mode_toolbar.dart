import 'package:material_ui/material_ui.dart';

import 'package:saber/mnote/ink/ink_paint.dart';
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

/// State and callbacks of the handwrite tool group.
class InkControls {
  const new({
    required this.tool,
    required this.onTool,
    required this.color,
    required this.onColor,
    required this.width,
    required this.onWidth,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.fingerDrawing,
    required this.onFingerDrawing,
  });

  final InkTool tool;
  final ValueChanged<InkTool> onTool;
  final Color color;
  final ValueChanged<Color> onColor;
  final InkWidth width;
  final ValueChanged<InkWidth> onWidth;
  final bool canUndo, canRedo;
  final VoidCallback onUndo, onRedo;
  final bool fingerDrawing;
  final ValueChanged<bool> onFingerDrawing;
}

/// Floating toolbar at the bottom of the reader. Switching mode swaps the
/// whole tool group. Excerpt and handwrite are functional; organize and
/// recall show their tools disabled.
class ModeToolbar extends StatelessWidget {
  const new({
    super.key,
    required this.mode,
    required this.onMode,
    required this.color,
    required this.onColor,
    required this.tool,
    required this.onTool,
    this.ink,
    this.onRevealAll,
    this.onRemask,
  });

  final WorkMode mode;
  final ValueChanged<WorkMode> onMode;
  final ExcerptColor color;
  final ValueChanged<ExcerptColor> onColor;
  final ExcerptTool tool;
  final ValueChanged<ExcerptTool> onTool;
  final InkControls? ink;

  /// Recall mode actions.
  final VoidCallback? onRevealAll, onRemask;

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
              // Modes as one chip (layout v2): leaves room for the tools.
              PopupMenuButton<WorkMode>(
                key: const ValueKey('mode-menu'),
                tooltip: '切换模式',
                initialValue: mode,
                onSelected: onMode,
                itemBuilder: (_) => [
                  for (final m in WorkMode.values)
                    PopupMenuItem(
                      key: ValueKey('mode-menu-${m.name}'),
                      value: m,
                      child: Text(m.label),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: p.ink,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        mode.label,
                        style: TextStyle(
                          fontSize: 15,
                          color: p.paper,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, size: 18, color: p.paper),
                    ],
                  ),
                ),
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
        final k = ink;
        if (k == null) return const [];
        final drawing = k.tool == InkTool.pen || k.tool == InkTool.highlighter;
        final palette = k.tool == InkTool.highlighter
            ? highlighterColors
            : penColors;
        return [
          for (final (t, icon) in const [
            (InkTool.pen, Icons.edit_outlined),
            (InkTool.highlighter, Icons.brush_outlined),
            (InkTool.eraser, Icons.cleaning_services_outlined),
            (InkTool.lasso, Icons.gesture),
          ])
            _Tool(
              key: ValueKey('ink-${t.name}'),
              icon: icon,
              label: t.label,
              selected: k.tool == t,
              onTap: () => k.onTool(t),
              iconOnly: true,
            ),
          if (drawing) ...[
            const SizedBox(width: 6),
            for (final w in InkWidth.values)
              _Seg(
                key: ValueKey('ink-width-${w.name}'),
                label: w.label,
                selected: k.width == w,
                onTap: () => k.onWidth(w),
              ),
            const SizedBox(width: 6),
            for (final c in palette)
              InkResponse(
                key: ValueKey('ink-color-${c.toARGB32()}'),
                radius: 18,
                onTap: () => k.onColor(c),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.toARGB32() == k.color.toARGB32()
                          ? p.ink
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(width: 6),
          _Tool(
            key: const ValueKey('ink-undo'),
            icon: Icons.undo,
            label: '撤销',
            selected: false,
            onTap: k.canUndo ? k.onUndo : null,
            iconOnly: true,
          ),
          _Tool(
            key: const ValueKey('ink-redo'),
            icon: Icons.redo,
            label: '重做',
            selected: false,
            onTap: k.canRedo ? k.onRedo : null,
            iconOnly: true,
          ),
          const SizedBox(width: 6),
          _Tool(
            key: const ValueKey('ink-finger'),
            icon: k.fingerDrawing
                ? Icons.touch_app
                : Icons.do_not_touch_outlined,
            label: k.fingerDrawing ? '手指书写：开' : '手指书写：关',
            selected: k.fingerDrawing,
            onTap: () => k.onFingerDrawing(!k.fingerDrawing),
            iconOnly: true,
          ),
        ];
      case WorkMode.organize:
        return [
          // Dragging cards in the mind map always works in this mode.
          const _Tool(
            key: ValueKey('org-drag'),
            icon: Icons.open_with,
            label: '拖拽',
            selected: true,
            onTap: _noop,
          ),
          ..._soon(p, const [
            (Icons.merge_type, '合并'),
            (Icons.format_list_bulleted, '大纲'),
            (Icons.auto_awesome_mosaic_outlined, '自动排版'),
          ]),
        ];
      case WorkMode.recall:
        return [
          const _Tool(
            key: ValueKey('recall-mask'),
            icon: Icons.horizontal_rule,
            label: '遮挡',
            selected: true,
            onTap: _noop,
          ),
          _Tool(
            key: const ValueKey('recall-reveal-all'),
            icon: Icons.visibility_outlined,
            label: '全部揭示',
            selected: false,
            onTap: onRevealAll,
          ),
          _Tool(
            key: const ValueKey('recall-remask'),
            icon: Icons.add,
            label: '重新遮挡',
            selected: false,
            onTap: onRemask,
          ),
        ];
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
    this.iconOnly = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Show only the icon; [label] becomes the tooltip (and accessibility label).
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    final enabled = onTap != null;
    final fg = !enabled
        ? p.ink3.withValues(alpha: 0.55)
        : (selected ? p.accent : p.ink2);
    final button = Material(
      color: selected ? p.accent.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: iconOnly ? 8 : 10,
            vertical: 8,
          ),
          child: iconOnly
              ? Icon(icon, size: 20, color: fg)
              : Row(
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
    return iconOnly ? Tooltip(message: label, child: button) : button;
  }
}

void _noop() {}
