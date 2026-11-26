import 'package:material_ui/material_ui.dart';

import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/margin_rail.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

const overlayHeaderHeight = 52.0;

/// Shell shared by the cards and mind-map overlays: a floating sheet over the
/// right part of the PDF with a 卡片 / 脑图 switch, a subtitle and close.
class OverlayPanel extends StatelessWidget {
  const new({
    super.key,
    required this.panel,
    required this.subtitle,
    required this.onPanel,
    required this.onClose,
    required this.child,
  });

  final String panel; // 'cards' | 'map'
  final String subtitle;
  final ValueChanged<String> onPanel;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    Widget seg(String id, String label) {
      final on = panel == id;
      return Material(
        color: on ? p.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey('panel-tab-$id'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => onPanel(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: on ? p.paper : p.ink2,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      key: ValueKey('panel-$panel'),
      color: p.paper,
      elevation: 14,
      shadowColor: Colors.black38,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: overlayHeaderHeight,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    border: Border.all(color: p.line),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [seg('cards', '卡片'), seg('map', '脑图')]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    subtitle,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: p.ink3),
                  ),
                ),
                IconButton(
                  key: const ValueKey('panel-close'),
                  tooltip: '收起',
                  icon: Icon(Icons.chevron_right, color: p.ink2),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.line),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Body of the cards overlay: cards at the height of their source text
/// (same coordinates as the reader), plus "↑ 上方 n 张" / "↓ 下方 n 张"
/// for cards whose source is scrolled out of view.
class CardsOverlayBody extends StatelessWidget {
  const new({
    super.key,
    required this.positions,
    required this.bodyTop,
    required this.selectedId,
    required this.cardKeys,
    required this.onOpen,
    required this.onJump,
  });

  /// Every card of the document with its source rect in reader coordinates.
  final List<(MCard, Rect)> positions;

  /// Where this body starts, in reader coordinates (header height).
  final double bodyTop;
  final String? selectedId;
  final Map<String, GlobalKey> cardKeys;
  final void Function(MCard) onOpen;
  final void Function(MCard) onJump;

  static const _hint = 36.0;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    return LayoutBuilder(
      builder: (context, cons) {
        final h = cons.maxHeight;
        // Positions relative to this body.
        final rel = [
          for (final (c, r) in positions) (c, r.shift(Offset(0, -bodyTop))),
        ];
        final above = rel.where((e) => e.$2.bottom < 0).toList()
          ..sort((a, b) => b.$2.bottom.compareTo(a.$2.bottom));
        final placed = placeCards(
          rel.where((e) => e.$2.bottom >= 0 && e.$2.top <= h).toList(),
        );
        final visible = <PlacedCard>[];
        final below = <(MCard, Rect)>[...rel.where((e) => e.$2.top > h)];
        for (final pc in placed) {
          final top = pc.top < _hint ? _hint : pc.top;
          if (top + marginCardHeight > h - _hint) {
            below.add((pc.card, pc.source));
          } else {
            visible.add(PlacedCard(pc.card, top, pc.source));
          }
        }
        below.sort((a, b) => a.$2.top.compareTo(b.$2.top));

        Widget hint(String key, String text, List<(MCard, Rect)> cards) =>
            Material(
              color: p.paper2,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: ValueKey(key),
                borderRadius: BorderRadius.circular(10),
                onTap: () => onJump(cards.first.$1),
                child: Container(
                  height: _hint - 8,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.line),
                  ),
                  child: Row(
                    children: [
                      Text(text, style: TextStyle(fontSize: 13, color: p.ink2)),
                      const SizedBox(width: 6),
                      for (final (c, _) in cards.take(6))
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: c.color.ink(dark: p.dark),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );

        if (positions.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              '在页面上选中文字，选颜色后「摘录为卡片」。卡片会出现在这里，与原文同高。',
              style: TextStyle(fontSize: 14, color: p.ink3, height: 1.6),
            ),
          );
        }

        return Stack(
          children: [
            for (final pc in visible)
              Positioned(
                key: ValueKey('panel-card-${pc.card.id}'),
                left: 12,
                right: 12,
                top: pc.top,
                child: MarginCardTile(
                  key: cardKeys.putIfAbsent(pc.card.id, GlobalKey.new),
                  card: pc.card,
                  selected: pc.card.id == selectedId,
                  onTap: () => onOpen(pc.card),
                ),
              ),
            if (above.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                top: 4,
                child: hint('panel-above', '↑ 上方 ${above.length} 张', above),
              ),
            if (below.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: 4,
                child: hint('panel-below', '↓ 下方 ${below.length} 张', below),
              ),
          ],
        );
      },
    );
  }
}
