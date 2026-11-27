import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:saber/mnote/model/text_clean.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// What an internal link points at, judged from the words just before it
/// and from where it lands.
enum LinkKind { reference, figure, table, section, page }

/// A resolved internal link: what it is and the area of the target page to
/// preview (page space, PDF points, top-left origin).
class LinkTarget {
  new(this.kind, this.page, this.region, {this.text = ''});
  final LinkKind kind;
  final int page;
  final Rect region;

  /// Readable text of the target (for references), empty otherwise.
  final String text;

  String get label => switch (kind) {
    LinkKind.reference => '参考文献',
    LinkKind.figure => '图',
    LinkKind.table => '表',
    LinkKind.section => '章节',
    LinkKind.page => '跳转目标',
  };
}

/// Classifies [link] (tapped on [fromPage]) and computes the preview area.
/// [referencesFrom] is the first page of the bibliography, if known.
Future<LinkTarget?> resolveLink(
  PdfDocument doc,
  PdfLink link, {
  required int? fromPage,
  int? referencesFrom,
}) async {
  final dest = link.dest;
  if (dest == null || dest.pageNumber < 1 || dest.pageNumber > doc.pages.length)
    return null;
  final page = doc.pages[dest.pageNumber - 1];
  final w = page.width, h = page.height;

  // Words right before the link on the page it was tapped on.
  var before = '';
  var linkText = '';
  if (fromPage != null &&
      fromPage >= 1 &&
      fromPage <= doc.pages.length &&
      link.rects.isNotEmpty) {
    try {
      final t = await doc.pages[fromPage - 1].loadStructuredText();
      final r = link.rects.first;
      var first = -1;
      final inLink = StringBuffer();
      for (var i = 0; i < t.charRects.length; i++) {
        final c = t.charRects[i];
        final cx = (c.left + c.right) / 2, cy = (c.top + c.bottom) / 2;
        if (cx >= r.left && cx <= r.right && cy <= r.top && cy >= r.bottom) {
          if (first < 0) first = i;
          inLink.write(t.fullText[i]);
        }
      }
      linkText = inLink.toString().trim();
      if (first > 0)
        before = t.fullText.substring((first - 14).clamp(0, first), first);
    } catch (_) {}
  }
  final b = before.replaceAll(RegExp(r'\s+'), ' ').trimRight();

  final kind = RegExp(r'(Figure|Fig\.)\s*$', caseSensitive: false).hasMatch(b)
      ? LinkKind.figure
      : RegExp(r'Table\s*$', caseSensitive: false).hasMatch(b)
      ? LinkKind.table
      : RegExp(
          r'(§|Section|Sec\.|Appendix|App\.)\s*$',
          caseSensitive: false,
        ).hasMatch(b)
      ? LinkKind.section
      // Section / figure / table links are short numbers ("4", "5.1",
      // "A.2"); citations are names or four-digit years ("TypeSafe AI", "2026").
      : (linkText.isNotEmpty &&
                !RegExp(r'^([A-Z]|\d{1,3})(\.\d+)*$').hasMatch(linkText)) ||
            (referencesFrom != null && dest.pageNumber >= referencesFrom)
      ? LinkKind.reference
      : LinkKind.section;

  // XYZ destinations give the target's left and top (PDF y-up).
  final p = dest.params;
  final x = (p != null && p.isNotEmpty && p[0] != null) ? p[0]! : 0.0;
  final yUp = (p != null && p.length > 1 && p[1] != null) ? p[1]! : h;
  final top = (h - yUp).clamp(0.0, h);
  // Column: links into a two-column page start at a column's left edge.
  final colLeft = x > w * 0.45 ? w * 0.5 - 4 : (x - 8).clamp(0.0, w);
  final colRight = x > w * 0.45
      ? w - (w * 0.08)
      : (x < w * 0.2 ? w * 0.5 + 4 : w);
  final height = switch (kind) {
    LinkKind.reference => 64.0,
    LinkKind.figure || LinkKind.table => h * 0.42,
    LinkKind.section || LinkKind.page => 120.0,
  };
  final region = switch (kind) {
    // Figures usually span the page width and the target is the figure's top.
    LinkKind.figure || LinkKind.table => Rect.fromLTRB(
      w * 0.06,
      (top - 6).clamp(0.0, h),
      w * 0.94,
      (top + height).clamp(0.0, h),
    ),
    _ => Rect.fromLTRB(
      colLeft,
      (top - 4).clamp(0.0, h),
      colRight,
      (top + height).clamp(0.0, h),
    ),
  };

  var text = '';
  if (kind == LinkKind.reference) {
    try {
      final t = await page.loadStructuredText();
      final buf = StringBuffer();
      // One bibliography entry: from the target down to the next entry,
      // which starts at the same left edge after a line break.
      double? lastBottom;
      for (var i = 0; i < t.charRects.length; i++) {
        final c = t.charRects[i];
        final cy = h - (c.top + c.bottom) / 2;
        final cx = (c.left + c.right) / 2;
        if (cx < region.left ||
            cx > region.right ||
            cy < region.top ||
            cy > region.bottom)
          continue;
        if (lastBottom != null &&
            cy - lastBottom > 13 &&
            c.left <= x + 2 &&
            buf.length > 40)
          break;
        buf.write(t.fullText[i]);
        lastBottom = cy;
      }
      text = cleanExcerptText(buf.toString());
    } catch (_) {}
  }
  return LinkTarget(kind, dest.pageNumber, region, text: text);
}

/// Popover with the target's preview: the rendered area (and, for
/// references, its text), 「跳过去」 and 「复制」.
class LinkPreviewCard extends StatelessWidget {
  const new({
    super.key,
    required this.target,
    required this.page,
    required this.onGo,
    required this.onCopy,
    required this.onClose,
  });

  final LinkTarget target;
  final PdfPage page;
  final VoidCallback onGo, onCopy, onClose;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    final isRef = target.kind == LinkKind.reference && target.text.isNotEmpty;
    final width =
        target.kind == LinkKind.figure || target.kind == LinkKind.table
        ? 520.0
        : 420.0;
    return Material(
      key: const ValueKey('link-preview'),
      color: p.paper,
      elevation: 12,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  switch (target.kind) {
                    LinkKind.reference => Icons.menu_book_outlined,
                    LinkKind.figure || LinkKind.table => Icons.image_outlined,
                    _ => Icons.segment,
                  },
                  size: 16,
                  color: p.ink3,
                ),
                const SizedBox(width: 6),
                Text(
                  '${target.label}，第 ${target.page} 页',
                  key: const ValueKey('link-preview-label'),
                  style: TextStyle(fontSize: 13, color: p.ink3),
                ),
                const Spacer(),
                IconButton(
                  key: const ValueKey('link-preview-close'),
                  tooltip: '关闭',
                  iconSize: 18,
                  onPressed: onClose,
                  icon: Icon(Icons.close, color: p.ink3),
                ),
              ],
            ),
            if (isRef)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: SelectableText(
                  target.text,
                  key: const ValueKey('link-preview-text'),
                  style: TextStyle(fontSize: 15, height: 1.55, color: p.ink),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _RegionImage(page: page, region: target.region),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  key: const ValueKey('link-go'),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onGo,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text(isRef ? '跳到参考文献' : '跳过去'),
                ),
                if (isRef) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('link-copy'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.ink2,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('复制'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RegionImage extends StatefulWidget {
  const new({required this.page, required this.region});
  final PdfPage page;
  final Rect region;
  @override
  State<_RegionImage> createState() => _RegionImageState();
}

class _RegionImageState extends State<_RegionImage> {
  static const _s = 2.5;
  late final Future<ui.Image?> img = widget.page.renderForDisplay(
    x: (widget.region.left * _s).round(),
    y: (widget.region.top * _s).round(),
    width: (widget.region.width * _s).round(),
    height: (widget.region.height * _s).round(),
    fullWidth: widget.page.width * _s,
    fullHeight: widget.page.height * _s,
    backgroundColor: 0xFFFFFFFF,
  );

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: widget.region.width / widget.region.height,
    child: FutureBuilder<ui.Image?>(
      future: img,
      builder: (context, s) => s.data == null
          ? ColoredBox(color: MnotePalette.of(context).paper2)
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: RawImage(
                key: const ValueKey('link-preview-image'),
                image: s.data,
                fit: BoxFit.fill,
              ),
            ),
    ),
  );
}

/// First page of the bibliography: from the outline ("References",
/// "Bibliography", "参考文献"), else the last page whose text starts a line
/// with such a heading. Null if not found.
Future<int?> findReferencesPage(PdfDocument doc) async {
  final heading = RegExp(
    r'^\s*(References|Bibliography|参考文献)\s*$',
    multiLine: true,
    caseSensitive: false,
  );
  try {
    final outline = await doc.loadOutline();
    int? walk(List<PdfOutlineNode> nodes) {
      for (final n in nodes) {
        if (heading.hasMatch(n.title.trim()) && n.dest != null)
          return n.dest!.pageNumber;
        final c = walk(n.children);
        if (c != null) return c;
      }
      return null;
    }

    final fromOutline = walk(outline);
    if (fromOutline != null) return fromOutline;
  } catch (_) {}
  for (var i = doc.pages.length; i >= 1; i--) {
    try {
      final t = await doc.pages[i - 1].loadStructuredText();
      if (heading.hasMatch(t.fullText)) return i;
    } catch (_) {}
  }
  return null;
}
