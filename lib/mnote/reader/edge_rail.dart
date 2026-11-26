import 'package:material_ui/material_ui.dart';

import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

const edgeRailWidth = 44.0;

/// A card's position along the reader, in viewer-local coordinates.
class RailMark {
  new(this.card, this.top, this.height);
  final MCard card;
  final double top, height;
}

/// Narrow edge rail on the right of the reader (layout v2, option D):
/// card count, entries to the cards and mind-map overlays, a thin coloured
/// bar at the height of each excerpt, and a button to tuck the rail away.
class EdgeRail extends StatelessWidget {
  const new({
    super.key,
    required this.count,
    required this.marks,
    required this.barKeys,
    required this.panel,
    required this.onCards,
    required this.onMap,
    required this.onHide,
    required this.onDragOpen,
  });

  final int count;
  final List<RailMark> marks;

  /// One key per card id (fly-in animation target).
  final Map<String, GlobalKey> barKeys;

  /// Which overlay is open: 'cards', 'map' or null.
  final String? panel;
  final VoidCallback onCards, onMap, onHide, onDragOpen;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    Widget entry(
      String key,
      IconData icon,
      String tip,
      bool on,
      VoidCallback tap,
    ) => Tooltip(
      message: tip,
      child: Material(
        color: on ? p.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(8),
          onTap: tap,
          child: SizedBox(
            width: 36,
            height: 34,
            child: Icon(icon, size: 19, color: on ? p.accent : p.ink2),
          ),
        ),
      ),
    );

    return GestureDetector(
      // Pull from the right edge towards the page to open the cards overlay.
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) onDragOpen();
      },
      child: Container(
        width: edgeRailWidth,
        decoration: BoxDecoration(
          color: p.paper,
          border: Border(left: BorderSide(color: p.line)),
        ),
        child: Stack(
          children: [
            // Excerpt bars at the height of their source text.
            for (final m in marks)
              Positioned(
                key: ValueKey('rail-${m.card.id}'),
                top: m.top,
                right: 8,
                width: 5,
                height: m.height,
                child: GestureDetector(
                  onTap: onCards,
                  child: Container(
                    key: barKeys.putIfAbsent(m.card.id, GlobalKey.new),
                    decoration: BoxDecoration(
                      color: m.card.color.ink(dark: p.dark),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: p.paper,
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Column(
                  children: [
                    Text(
                      '$count',
                      key: const ValueKey('rail-count'),
                      style: serifStyle(
                        p.ink,
                        size: 16,
                        weight: FontWeight.w700,
                      ),
                    ),
                    Text('卡片', style: TextStyle(fontSize: 12, color: p.ink3)),
                    const SizedBox(height: 8),
                    entry(
                      'rail-cards',
                      Icons.view_agenda_outlined,
                      '卡片',
                      panel == 'cards',
                      onCards,
                    ),
                    const SizedBox(height: 4),
                    entry(
                      'rail-map',
                      Icons.account_tree_outlined,
                      '脑图',
                      panel == 'map',
                      onMap,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 6,
              left: 0,
              right: 0,
              child: Center(
                child: entry(
                  'rail-hide',
                  Icons.chevron_right,
                  '收起边栏',
                  false,
                  onHide,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What is left of the rail when it is tucked away: a small grip at the edge.
class EdgeHandle extends StatelessWidget {
  const new({super.key, required this.onShow});

  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    return Tooltip(
      message: '展开边栏',
      child: GestureDetector(
        key: const ValueKey('rail-handle'),
        onTap: onShow,
        onHorizontalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -100) onShow();
        },
        child: Container(
          width: 18,
          height: 72,
          decoration: BoxDecoration(
            color: p.ink.withValues(alpha: 0.85),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(9),
            ),
          ),
          child: Center(
            child: Container(
              width: 3,
              height: 28,
              decoration: BoxDecoration(
                color: p.paper.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
