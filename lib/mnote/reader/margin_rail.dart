import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/pdf_geometry.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

const marginCardHeight = 66.0;
const marginGap = 8.0;

/// A card placed in the margin rail.
class PlacedCard {
  new(this.card, this.top, this.source);
  final MCard card;

  /// Top of the card in viewer-local coordinates.
  final double top;

  /// Source text bounds in viewer-local coordinates.
  final Rect source;

  double get centerY => top + marginCardHeight / 2;
}

/// Lays out margin cards so each sits at the height of its source text,
/// pushed down only as much as needed to avoid overlapping the card above.
/// Cards whose source is far outside the viewport are skipped.
List<PlacedCard> layoutMarginCards(
  PdfViewerController controller,
  Iterable<MCard> cards, {
  required double viewHeight,
}) {
  final withPos = <(MCard, Rect)>[];
  for (final c in cards) {
    final r = cardBoundsInViewer(controller, c);
    if (r == null) continue;
    if (r.bottom < -viewHeight || r.top > viewHeight * 2) continue;
    withPos.add((c, r));
  }
  return placeCards(withPos);
}

/// Pure placement: sorts by source top and pushes each card down just enough
/// to clear the previous one. Each card's [PlacedCard.top] is never above its
/// source text.
List<PlacedCard> placeCards(List<(MCard, Rect)> withPos) {
  final sorted = [...withPos]..sort((a, b) => a.$2.top.compareTo(b.$2.top));
  final placed = <PlacedCard>[];
  var nextFree = double.negativeInfinity;
  for (final (card, rect) in sorted) {
    final top = rect.top < nextFree ? nextFree : rect.top;
    placed.add(PlacedCard(card, top, rect));
    nextFree = top + marginCardHeight + marginGap;
  }
  return placed;
}

/// Compact margin card: title, colour dot with its meaning, page.
class MarginCardTile extends StatelessWidget {
  const new({
    super.key,
    required this.card,
    required this.onTap,
    this.selected = false,
  });

  final MCard card;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    return SizedBox(
      height: marginCardHeight,
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? card.color.ink(dark: p.dark) : p.line,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  card.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: serifStyle(p.ink, size: 15, weight: FontWeight.w600),
                ),
                Row(
                  children: [
                    if (card.image != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.crop_original,
                          size: 13,
                          color: p.ink3,
                        ),
                      ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: card.color.ink(dark: p.dark),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        card.color.label,
                        style: TextStyle(fontSize: 12, color: p.ink3),
                      ),
                    ),
                    Text(
                      card.pageLabel,
                      style: TextStyle(fontSize: 12, color: p.accent),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dotted lead lines from each highlight's right edge to its margin card.
class LeadLinePainter extends CustomPainter {
  new({required this.placed, required this.railLeft, required this.dark});

  final List<PlacedCard> placed;
  final double railLeft;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    for (final pc in placed) {
      final paint = Paint()
        ..color = pc.card.color.ink(dark: dark).withValues(alpha: 0.75)
        ..strokeWidth = 1.1
        ..style = PaintingStyle.stroke;
      final start = Offset(pc.source.right + 2, pc.source.top + 8);
      final end = Offset(railLeft + 2, pc.centerY);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          (start.dx + end.dx) / 2,
          start.dy,
          (start.dx + end.dx) / 2,
          end.dy,
          end.dx,
          end.dy,
        );
      _drawDashed(canvas, path, paint);
      canvas.drawCircle(start, 2.2, paint..style = PaintingStyle.fill);
    }
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
        d += 6;
      }
    }
  }

  @override
  bool shouldRepaint(LeadLinePainter old) => true;
}
