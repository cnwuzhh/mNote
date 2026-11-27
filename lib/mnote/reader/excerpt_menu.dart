import 'package:material_ui/material_ui.dart';

import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// What the user picked in the excerpt menu.
enum ExcerptAction { card, highlight, copy, translate, explain }

/// The dark rounded menu shown above a text selection:
/// four colours | 摘录为卡片 仅高亮 | 翻译 解释 | 更多 (复制).
class ExcerptMenu extends StatefulWidget {
  const new({super.key, required this.initialColor, required this.onAction});

  final ExcerptColor initialColor;
  final void Function(ExcerptAction action, ExcerptColor color) onAction;

  @override
  State<ExcerptMenu> createState() => _ExcerptMenuState();
}

class _ExcerptMenuState extends State<ExcerptMenu> {
  late ExcerptColor color = widget.initialColor;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    const bg = Color(0xFF2A251E);
    return Material(
      color: bg,
      elevation: 8,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in ExcerptColor.values)
              Tooltip(
                message: c.label,
                child: InkResponse(
                  key: ValueKey('excerpt-color-${c.name}'),
                  radius: 20,
                  onTap: () => setState(() => color = c),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: c.ink(),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c == color ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
              ),
            Container(
              width: 1,
              height: 26,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.white24,
            ),
            _MenuButton(
              key: const ValueKey('excerpt-to-card'),
              icon: Icons.note_add_outlined,
              label: '摘录为卡片',
              filled: p.accent,
              onTap: () => widget.onAction(ExcerptAction.card, color),
            ),
            _MenuButton(
              key: const ValueKey('excerpt-highlight'),
              icon: Icons.border_color_outlined,
              label: '仅高亮',
              onTap: () => widget.onAction(ExcerptAction.highlight, color),
            ),
            Container(
              width: 1,
              height: 26,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: Colors.white24,
            ),
            _MenuButton(
              key: const ValueKey('excerpt-translate'),
              icon: Icons.translate,
              label: '翻译',
              onTap: () => widget.onAction(ExcerptAction.translate, color),
            ),
            _MenuButton(
              key: const ValueKey('excerpt-explain'),
              icon: Icons.lightbulb_outline,
              label: '解释',
              onTap: () => widget.onAction(ExcerptAction.explain, color),
            ),
            Container(
              width: 1,
              height: 26,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: Colors.white24,
            ),
            PopupMenuButton<ExcerptAction>(
              key: const ValueKey('excerpt-more'),
              tooltip: '更多',
              color: bg,
              onSelected: (a) => widget.onAction(a, color),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  key: ValueKey('excerpt-copy'),
                  value: ExcerptAction.copy,
                  child: Row(
                    children: [
                      Icon(Icons.copy_outlined, size: 18, color: Colors.white),
                      SizedBox(width: 10),
                      Text('复制', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.more_horiz, size: 18, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      '更多',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const new({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? filled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: filled ?? Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
