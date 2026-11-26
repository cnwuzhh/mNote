import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// Horizontal mind map of a study set: root on the left, cards branching to
/// the right. Long-press a card to drag it onto another card (becomes its
/// child) or onto the root (back to the first level).
class MindMapView extends StatelessWidget {
  const new({
    super.key,
    required this.set,
    required this.nodeKeys,
    required this.onOpen,
    required this.onJump,
    required this.onMove,
    this.flashId,
    this.masked,
    this.onReveal,
    this.fill = false,
    this.selectedId,
  });

  final StudySet set;

  /// One key per card id, used to find node positions (fly-in animation).
  final Map<String, GlobalKey> nodeKeys;
  final void Function(MCard card) onOpen;
  final void Function(MCard card) onJump;
  final void Function(MCard card, String? newParentId) onMove;
  final String? flashId;
  final String? selectedId;

  /// Recall mode: ids of cards whose content is hidden; tapping one calls
  /// [onReveal] instead of opening it.
  final Set<String>? masked;
  final void Function(MCard card)? onReveal;

  /// Full-screen use (organize / recall): centre the tree and let it grow a
  /// little so it reads comfortably; in the narrow overlay it only shrinks.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    final rootChildren = set.childrenOf(null);
    // Re-fit when the tree's shape changes (cards added, moved, retitled).
    final signature = Object.hashAll([
      for (final c in set.mapCards) Object.hash(c.id, c.parentId, c.title),
    ]);
    return _FitToWidthViewer(
      signature: signature,
      fill: fill,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DragTarget<String>(
              onWillAcceptWithDetails: (d) => set.cardById(d.data) != null,
              onAcceptWithDetails: (d) {
                final c = set.cardById(d.data);
                if (c != null) onMove(c, null);
              },
              builder: (context, candidates, _) => Container(
                key: const ValueKey('mindmap-root'),
                constraints: const BoxConstraints(maxWidth: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: p.ink,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: candidates.isNotEmpty
                        ? p.accent
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Text(
                  set.name,
                  style: serifStyle(p.paper, size: 15, weight: FontWeight.w600),
                ),
              ),
            ),
            if (rootChildren.isNotEmpty)
              _Children(parent: this, cards: rootChildren),
          ],
        ),
      ),
    );
  }
}

class _Children extends StatelessWidget {
  const new({required this.parent, required this.cards});

  final MindMapView parent;
  final List<MCard> cards;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    return CustomPaint(
      painter: _StubPainter(p.ink3.withValues(alpha: 0.6)),
      child: Padding(
        padding: const EdgeInsets.only(left: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++)
              CustomPaint(
                painter: _BranchPainter(
                  color: cards[i].color
                      .ink(dark: p.dark)
                      .withValues(alpha: 0.7),
                  isFirst: i == 0,
                  isLast: i == cards.length - 1,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 22, top: 5, bottom: 5),
                  child: _Subtree(parent: parent, card: cards[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Short horizontal line from a parent node to its children's spine.
class _StubPainter extends CustomPainter {
  new(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    canvas.drawLine(
      Offset(0, cy),
      Offset(18, cy),
      Paint()
        ..color = color
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(_StubPainter old) => old.color != color;
}

class _Subtree extends StatelessWidget {
  const new({required this.parent, required this.card});

  final MindMapView parent;
  final MCard card;

  @override
  Widget build(BuildContext context) {
    final children = parent.set.childrenOf(card.id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Node(parent: parent, card: card),
        if (children.isNotEmpty) _Children(parent: parent, cards: children),
      ],
    );
  }
}

class _Node extends StatelessWidget {
  const new({required this.parent, required this.card});

  final MindMapView parent;
  final MCard card;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    final key = parent.nodeKeys.putIfAbsent(card.id, GlobalKey.new);
    final flashing = parent.flashId == card.id;
    final selected = parent.selectedId == card.id;
    final isMasked = parent.masked?.contains(card.id) ?? false;

    // Recall mode: only colour and position are visible.
    Widget masked() => Container(
      key: key,
      width: 176,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: p.line,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          Container(height: 3, color: card.color.ink(dark: p.dark)),
        ],
      ),
    );

    Widget node(bool hovered) => AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 260),
      constraints: const BoxConstraints(minWidth: 110, maxWidth: 176),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(8),
        // Flutter only paints rounded borders with one uniform colour, so the
        // excerpt colour is drawn as a bar below the content instead.
        border: Border.all(
          color: hovered ? p.accent : p.line,
          width: hovered ? 1.5 : 1,
        ),
        boxShadow: [
          if (flashing)
            BoxShadow(
              color: p.accent.withValues(alpha: 0.55),
              blurRadius: 16,
              spreadRadius: 3,
            ),
          if (selected && !flashing)
            BoxShadow(
              color: card.color.ink(dark: p.dark).withValues(alpha: 0.35),
              blurRadius: 8,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (card.image != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.crop_original, size: 15, color: p.ink3),
                  ),
                Flexible(
                  child: Text(
                    card.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: serifStyle(p.ink, size: 14),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: '回到原文 ${card.pageLabel}',
                  child: InkResponse(
                    key: ValueKey('mindmap-jump-${card.id}'),
                    radius: 18,
                    onTap: () => parent.onJump(card),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.subdirectory_arrow_left,
                        size: 16,
                        color: p.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 3, color: card.color.ink(dark: p.dark)),
        ],
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          d.data != card.id && !parent.set.isInSubtree(d.data, card.id),
      onAcceptWithDetails: (d) {
        final moved = parent.set.cardById(d.data);
        if (moved != null) parent.onMove(moved, card.id);
      },
      builder: (context, candidates, _) => LongPressDraggable<String>(
        data: card.id,
        feedback: Material(
          color: Colors.transparent,
          // In recall mode the dragged copy must not reveal the content.
          child: Opacity(
            opacity: 0.85,
            child: _feedback(context, masked: isMasked),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.35,
          child: isMasked ? masked() : node(false),
        ),
        child: GestureDetector(
          key: ValueKey('mindmap-node-${card.id}'),
          onTap: () =>
              isMasked ? parent.onReveal?.call(card) : parent.onOpen(card),
          child: isMasked ? masked() : node(candidates.isNotEmpty),
        ),
      ),
    );
  }

  Widget _feedback(BuildContext context, {bool masked = false}) {
    final p = MnotePalette.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.accent, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12)],
      ),
      child: masked
          ? Container(
              key: const ValueKey('mindmap-drag-masked'),
              width: 140,
              height: 10,
              decoration: BoxDecoration(
                color: p.line,
                borderRadius: BorderRadius.circular(5),
              ),
            )
          : Text(card.title, style: serifStyle(p.ink, size: 14)),
    );
  }
}

/// Draws the elbow connecting a child row to its parent's vertical spine.
class _BranchPainter extends CustomPainter {
  new({required this.color, required this.isFirst, required this.isLast});

  final Color color;
  final bool isFirst, isLast;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final cy = size.height / 2;
    const x = 0.0;
    final top = isFirst ? cy : 0.0;
    final bottom = isLast ? cy : size.height;
    if (bottom > top) canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    final path = Path()
      ..moveTo(x, cy)
      ..lineTo(20, cy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BranchPainter old) =>
      old.color != color || old.isFirst != isFirst || old.isLast != isLast;
}

/// InteractiveViewer that scales its (unconstrained) child down to fit the
/// available width whenever [signature] changes, so a wide tree stays fully
/// visible in the side panel. Users can still pinch to zoom and pan.
class _FitToWidthViewer extends StatefulWidget {
  const new({required this.signature, required this.child, this.fill = false});

  final int signature;
  final bool fill;
  final Widget child;

  @override
  State<_FitToWidthViewer> createState() => _FitToWidthViewerState();
}

class _FitToWidthViewerState extends State<_FitToWidthViewer> {
  final transform = TransformationController();
  final contentKey = GlobalKey();
  int? fittedFor;
  double? fittedWidth;
  double? fittedHeight;

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  void _fit(double viewportWidth, double viewportHeight) {
    final box = contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final w = box.size.width, h = box.size.height;
    double scale;
    if (widget.fill) {
      // Fill most of the screen, up to 1.6x, never below the overlay's floor.
      scale = math
          .min((viewportWidth * 0.9) / w, (viewportHeight * 0.8) / h)
          .clamp(0.78, 1.6);
    } else {
      scale = w <= viewportWidth ? 1.0 : (viewportWidth / w).clamp(0.78, 1.0);
    }
    final dx = widget.fill
        ? math.max(0.0, (viewportWidth - w * scale) / 2)
        : 0.0;
    final dy = widget.fill
        ? math.max(0.0, (viewportHeight - h * scale) / 2 - 24)
        : 0.0;
    transform.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    fittedFor = widget.signature;
    fittedWidth = viewportWidth;
    fittedHeight = viewportHeight;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        if (fittedFor != widget.signature ||
            fittedWidth != cons.maxWidth ||
            fittedHeight != cons.maxHeight) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fit(cons.maxWidth, cons.maxHeight);
          });
        }
        return InteractiveViewer(
          transformationController: transform,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(400),
          minScale: 0.4,
          maxScale: 2.0,
          child: KeyedSubtree(key: contentKey, child: widget.child),
        );
      },
    );
  }
}
