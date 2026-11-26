import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:saber/mnote/model/models.dart';

/// Converts selected text ranges into one rectangle per printed line, so the
/// stored highlight follows the text instead of covering a whole block
/// (important for two-column papers).
List<PageRect> lineRectsForRanges(List<PdfPageTextRange> ranges) {
  final out = <PageRect>[];
  for (final range in ranges) {
    final rects = range.pageText.charRects;
    final end = range.end.clamp(0, rects.length);
    PdfRect? line;
    for (var i = range.start.clamp(0, end); i < end; i++) {
      final r = rects[i];
      if (r.right - r.left <= 0 && r.top - r.bottom <= 0) continue; // spaces
      if (line == null) {
        line = r;
        continue;
      }
      final sameLine =
          _verticalOverlap(line, r) > 0.5 && r.left >= line.left - 2;
      if (sameLine) {
        line = PdfRect(
          r.left < line.left ? r.left : line.left,
          r.top > line.top ? r.top : line.top,
          r.right > line.right ? r.right : line.right,
          r.bottom < line.bottom ? r.bottom : line.bottom,
        );
      } else {
        out.add(_toPageRect(range.pageNumber, line));
        line = r;
      }
    }
    if (line != null) out.add(_toPageRect(range.pageNumber, line));
  }
  return out;
}

double _verticalOverlap(PdfRect a, PdfRect b) {
  final top = a.top < b.top ? a.top : b.top;
  final bottom = a.bottom > b.bottom ? a.bottom : b.bottom;
  final overlap = top - bottom;
  final h = (b.top - b.bottom).abs();
  if (h <= 0) return 1;
  return overlap / h;
}

PageRect _toPageRect(int page, PdfRect r) =>
    PageRect(page, r.left, r.top, r.right, r.bottom);

extension PageRectPdf on PageRect {
  PdfRect toPdfRect() => PdfRect(left, top, right, bottom);
}

/// Whether [c] has both its document and its page layout. pdfrx reports
/// `isReady` as soon as the document is open, slightly before the first
/// layout, and asking for page positions in between throws.
bool hasPageLayout(PdfViewerController c) {
  if (!c.isReady) return false;
  try {
    return c.layout.pageLayouts.length == c.pageCount;
  } catch (_) {
    return false;
  }
}

/// Where a card's source sits in the viewer's local coordinates, or null if
/// the viewer is not ready.
Rect? cardRectInViewer(PdfViewerController c, MCard card) {
  if (!hasPageLayout(c) || card.rects.isEmpty) return null;
  final first = card.rects.first;
  if (first.page < 1 || first.page > c.pageCount) return null;
  final docRect = c.calcRectForRectInsidePage(
    pageNumber: first.page,
    rect: first.toPdfRect(),
  );
  final tl = c.documentToLocal(docRect.topLeft);
  final br = c.documentToLocal(docRect.bottomRight);
  return Rect.fromPoints(tl, br);
}

/// Union of all rects of [card] on its first page, in viewer local coords.
Rect? cardBoundsInViewer(PdfViewerController c, MCard card) {
  if (!hasPageLayout(c) || card.rects.isEmpty) return null;
  Rect? acc;
  for (final r in card.rects.where((r) => r.page == card.page)) {
    final d = c.calcRectForRectInsidePage(
      pageNumber: r.page,
      rect: r.toPdfRect(),
    );
    final rr = Rect.fromPoints(
      c.documentToLocal(d.topLeft),
      c.documentToLocal(d.bottomRight),
    );
    acc = acc == null ? rr : acc.expandToInclude(rr);
  }
  return acc;
}

/// Scrolls the viewer so that [card]'s source is visible.
Future<void> goToCard(PdfViewerController c, MCard card) async {
  if (!hasPageLayout(c) || card.rects.isEmpty) return;
  final first = card.rects.first;
  await c.goToRectInsidePage(
    pageNumber: first.page,
    rect: first.toPdfRect(),
    anchor: PdfPageAnchor.center,
  );
}
