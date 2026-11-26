import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/pdf_geometry.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// Side sheet shown in organize mode when a card's "回到原文" is tapped:
/// the card's paragraph, zoomed in, with its highlight — without leaving the
/// mind map. "去阅读" switches to the reader at that spot.
class SourceSheet extends StatelessWidget {
  const new({
    super.key,
    required this.store,
    required this.set,
    required this.card,
    required this.page,
    required this.onRead,
    required this.onClose,
  });

  final StudyStore store;
  final StudySet set;
  final MCard card;

  /// The PDF page the card comes from (null when the PDF is not loaded yet).
  final PdfPage? page;
  final VoidCallback onRead, onClose;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    final doc = set.docById(card.docId);
    return Material(
      key: const ValueKey('source-sheet'),
      color: p.paper,
      elevation: 14,
      shadowColor: Colors.black38,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: serifStyle(
                          p.ink,
                          size: 17,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${doc?.title ?? '文档'}，第 ${card.page} 页',
                        style: TextStyle(fontSize: 13, color: p.ink3),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey('source-read'),
                  style: FilledButton.styleFrom(backgroundColor: p.accent),
                  onPressed: onRead,
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('去阅读'),
                ),
                IconButton(
                  key: const ValueKey('source-close'),
                  tooltip: '关闭',
                  icon: Icon(Icons.close, color: p.ink2),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.line),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (card.image != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      store.imageFile(set, card.image!),
                      fit: BoxFit.contain,
                    ),
                  )
                else if (page != null)
                  _ZoomedParagraph(page: page!, card: card)
                else
                  Text('文档加载中…', style: TextStyle(color: p.ink3)),
                const SizedBox(height: 14),
                if (card.text.isNotEmpty)
                  Text(
                    card.text,
                    style: serifStyle(p.ink2, size: 15, height: 1.6),
                  ),
                if (card.note.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '批注：${card.note}',
                    style: TextStyle(fontSize: 14, color: p.ink2),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The part of [page] around [card]'s source (its lines, the column width,
/// two lines of context above and below), rendered sharply, with the
/// highlight drawn on top.
class _ZoomedParagraph extends StatefulWidget {
  const new({required this.page, required this.card});
  final PdfPage page;
  final MCard card;

  @override
  State<_ZoomedParagraph> createState() => _ZoomedParagraphState();
}

class _ZoomedParagraphState extends State<_ZoomedParagraph> {
  late final Rect region = _region();
  late final Future<ui.Image?> _image = _render();
  static const _scale = 3.0;

  /// Source lines in page space (top-left origin).
  List<Rect> get _lines => [
    for (final r in widget.card.rects)
      if (r.page == widget.card.page) r.toPdfRect().toRect(page: widget.page),
  ];

  Rect _region() {
    final lines = _lines;
    final pw = widget.page.width, ph = widget.page.height;
    if (lines.isEmpty) return Rect.fromLTWH(0, 0, pw, math.min(ph, 200));
    final b = lines.reduce((a, c) => a.expandToInclude(c));
    final lineH = lines.map((r) => r.height).reduce(math.max);
    return Rect.fromLTRB(
      math.max(0, b.left - 12),
      math.max(0, b.top - 2.6 * lineH),
      math.min(pw, b.right + 12),
      math.min(ph, b.bottom + 2.6 * lineH),
    );
  }

  Future<ui.Image?> _render() => widget.page.renderForDisplay(
    x: (region.left * _scale).round(),
    y: (region.top * _scale).round(),
    width: (region.width * _scale).round(),
    height: (region.height * _scale).round(),
    fullWidth: widget.page.width * _scale,
    fullHeight: widget.page.height * _scale,
    backgroundColor: 0xFFFFFFFF,
  );

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    return AspectRatio(
      aspectRatio: region.width / region.height,
      child: FutureBuilder<ui.Image?>(
        future: _image,
        builder: (context, snap) {
          final img = snap.data;
          if (img == null) return ColoredBox(color: p.paper2);
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CustomPaint(
              key: const ValueKey('source-zoom'),
              painter: _ZoomPainter(
                img,
                region,
                _lines,
                widget.card.color.highlight(),
                widget.card.color.ink(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ZoomPainter extends CustomPainter {
  new(this.image, this.region, this.lines, this.fill, this.ink);
  final ui.Image image;
  final Rect region;
  final List<Rect> lines;
  final Color fill, ink;

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
    final k = size.width / region.width;
    for (final l in lines) {
      final r = l.shift(-region.topLeft).inflate(0.8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(r.left * k, r.top * k, r.right * k, r.bottom * k),
          const Radius.circular(3),
        ),
        Paint()..color = fill,
      );
    }
    if (lines.isNotEmpty) {
      final first = lines.first.shift(-region.topLeft);
      canvas.drawRect(
        Rect.fromLTWH(
          2,
          first.top * k,
          3,
          (lines.last.bottom - lines.first.top) * k,
        ),
        Paint()..color = ink,
      );
    }
  }

  @override
  bool shouldRepaint(_ZoomPainter old) => old.image != image;
}
