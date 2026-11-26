import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/mnote/ink/ink_document.dart';
import 'package:saber/mnote/ink/ink_paint.dart';
import 'package:saber/mnote/reader/pdf_geometry.dart';
import 'package:sbn/tool_id.dart';

/// Converts between viewer-local coordinates and PDF page space
/// (PDF points, origin at the page's top-left).
class PageSpace {
  new(this.controller);
  final PdfViewerController controller;

  /// Page under [local], or null if [local] is in the gap between pages.
  int? pageAt(Offset local) => controller
      .getPdfPageHitTestResult(local, useDocumentLayoutCoordinates: false)
      ?.page
      .pageNumber;

  Rect pageRectInDocument(int page) => controller.layout.pageLayouts[page - 1];

  Size pageSize(int page) {
    final p = controller.pages[page - 1];
    return Size(p.width, p.height);
  }

  /// [local] -> page space of [page] (may lie outside the page).
  Offset toPage(int page, Offset local) {
    final doc = controller.localToDocument(local);
    final r = pageRectInDocument(page);
    final k = pageSize(page).width / r.width;
    return (doc - r.topLeft) * k;
  }

  /// Transforms [canvas] (in viewer-local coordinates) to page space of [page].
  void applyTo(Canvas canvas, int page) {
    canvas.transform(controller.value.storage);
    final r = pageRectInDocument(page);
    canvas.translate(r.left, r.top);
    final k = r.width / pageSize(page).width;
    canvas.scale(k, k);
  }
}

/// What the user is doing with the current pointer.
enum _Gesture { none, stroke, erase, lasso }

/// Overlay above the PDF viewer that turns pen (and optionally finger)
/// input into ink. Touches it does not claim fall through to the viewer.
class InkInputLayer extends StatefulWidget {
  const new({
    super.key,
    required this.controller,
    required this.ink,
    required this.tool,
    required this.color,
    required this.width,
    required this.fingerDrawing,
    required this.onChanged,
    required this.onLasso,
    this.dark = false,
  });

  final PdfViewerController controller;
  final InkDocument ink;
  final InkTool tool;
  final Color color;
  final InkWidth width;
  final bool fingerDrawing;
  final bool dark;

  /// Ink was added or erased (save + repaint pages).
  final VoidCallback onChanged;

  /// A lasso was closed on [page]; [path] is in page space.
  final void Function(int page, Path path) onLasso;

  @override
  State<InkInputLayer> createState() => _InkInputLayerState();
}

class _InkInputLayerState extends State<InkInputLayer> {
  late var space = PageSpace(widget.controller);
  _Gesture gesture = _Gesture.none;
  int? page;
  Stroke? current;
  final List<Offset> lassoPoints = [];
  Offset? eraserLocal;
  Eraser? eraser;

  @override
  void didUpdateWidget(InkInputLayer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller)
      space = PageSpace(widget.controller);
  }

  bool _accepts(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus ||
      (widget.fingerDrawing && kind == PointerDeviceKind.touch) ||
      // Mouse lets the desktop build and widget tests draw too.
      kind == PointerDeviceKind.mouse;

  static double? _pressure(PointerEvent e) {
    if (e.kind != PointerDeviceKind.stylus &&
        e.kind != PointerDeviceKind.invertedStylus)
      return null;
    if (e.pressureMin == e.pressureMax) return null;
    return ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin))
        .clamp(0.0, 1.0);
  }

  void _start(PointerDownEvent e) {
    if (!hasPageLayout(widget.controller)) return;
    final p = space.pageAt(e.localPosition);
    if (p == null) return;
    page = p;
    // The stylus eraser end always erases.
    final tool = e.kind == PointerDeviceKind.invertedStylus
        ? InkTool.eraser
        : widget.tool;
    final pt = space.toPage(p, e.localPosition);
    switch (tool) {
      case InkTool.pen:
      case InkTool.highlighter:
        final hl = tool == InkTool.highlighter;
        current = Stroke(
          color: hl ? widget.color.withAlpha(255) : widget.color,
          pressureEnabled: !hl,
          options: StrokeOptions(
            size: hl ? widget.width.highlighter : widget.width.pen,
            thinning: hl ? 0 : 0.5,
            smoothing: 0.5,
            streamline: 0.5,
            isComplete: false,
          ),
          pageIndex: p - 1,
          page: widget.ink.pageSize(p, space.pageSize(p)),
          toolId: hl ? ToolId.highlighter : ToolId.fountainPen,
        )..addPoint(pt, _pressure(e));
        gesture = _Gesture.stroke;
      case InkTool.eraser:
        eraser = Eraser(size: 6);
        gesture = _Gesture.erase;
        _erase(e.localPosition);
      case InkTool.lasso:
        lassoPoints
          ..clear()
          ..add(pt);
        gesture = _Gesture.lasso;
    }
    setState(() {});
  }

  void _move(PointerMoveEvent e) {
    final p = page;
    if (p == null) return;
    switch (gesture) {
      case _Gesture.stroke:
        current?.addPoint(space.toPage(p, e.localPosition), _pressure(e));
      case _Gesture.erase:
        _erase(e.localPosition);
      case _Gesture.lasso:
        lassoPoints.add(space.toPage(p, e.localPosition));
      case _Gesture.none:
        return;
    }
    setState(() {});
  }

  void _erase(Offset local) {
    final p = space.pageAt(local) ?? page;
    eraserLocal = local;
    if (p == null) return;
    final hits = eraser!.checkForOverlappingStrokes(
      space.toPage(p, local),
      widget.ink.strokesOn(p).toList(),
    );
    if (hits.isNotEmpty) {
      widget.ink.remove(p, hits);
      widget.onChanged();
    }
  }

  void _end() {
    final p = page;
    switch (gesture) {
      case _Gesture.stroke:
        final s = current;
        if (p != null && s != null && !s.isEmpty) {
          s.options.isComplete = true;
          s.markPolygonNeedsUpdating();
          widget.ink.add(p, s);
          widget.onChanged();
        }
      case _Gesture.erase:
        eraser?.onDragEnd();
      case _Gesture.lasso:
        if (p != null && lassoPoints.length > 2) {
          widget.onLasso(p, Path()..addPolygon(lassoPoints, true));
        }
      case _Gesture.none:
        break;
    }
    _reset();
  }

  void _reset() {
    setState(() {
      gesture = _Gesture.none;
      current = null;
      lassoPoints.clear();
      eraserLocal = null;
      eraser = null;
      page = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _InkRecognizer: GestureRecognizerFactoryWithHandlers<_InkRecognizer>(
          () => _InkRecognizer(),
          (r) => r
            ..accepts = _accepts
            ..onStart = _start
            ..onMove = _move
            ..onEnd = _end
            ..onCancel = _reset,
        ),
      },
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _LivePainter(
            space: space,
            page: page,
            stroke: current,
            lasso: List.of(lassoPoints),
            eraserLocal: eraserLocal,
            dark: widget.dark,
          ),
        ),
      ),
    );
  }
}

/// Claims the pointer as soon as it goes down, so the PDF viewer does not
/// also scroll while the user writes. Only pointer kinds allowed by
/// [accepts] enter the arena; everything else goes to the viewer.
class _InkRecognizer extends OneSequenceGestureRecognizer {
  bool Function(PointerDeviceKind kind) accepts = (_) => false;
  void Function(PointerDownEvent e) onStart = (_) {};
  void Function(PointerMoveEvent e) onMove = (_) {};
  VoidCallback onEnd = () {};
  VoidCallback onCancel = () {};
  int? _pointer;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      _pointer == null && accepts(event.kind) && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointer = event.pointer;
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onStart(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      onMove(event);
    } else if (event is PointerUpEvent) {
      onEnd();
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      onCancel();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == _pointer) onCancel();
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) => _pointer = null;

  @override
  String get debugDescription => 'mNote ink';
}

class _LivePainter extends CustomPainter {
  new({
    required this.space,
    required this.page,
    required this.stroke,
    required this.lasso,
    required this.eraserLocal,
    required this.dark,
  });

  final PageSpace space;
  final int? page;
  final Stroke? stroke;
  final List<Offset> lasso;
  final Offset? eraserLocal;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final p = page;
    if (eraserLocal != null) {
      canvas.drawCircle(
        eraserLocal!,
        12,
        Paint()
          ..color = Colors.grey
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    if (p == null || !hasPageLayout(space.controller)) return;
    canvas.save();
    space.applyTo(canvas, p);
    final s = stroke;
    if (s != null && !s.isEmpty) {
      s.markPolygonNeedsUpdating();
      paintInk(
        canvas,
        [s],
        bounds: Offset.zero & space.pageSize(p),
        dark: dark,
      );
    }
    if (lasso.length > 1) {
      final path = Path()..addPolygon(lasso, false);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFB4532A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LivePainter old) => true;
}

/// Strokes on [page] at least 70% inside [lasso] (Saber's rule).
List<Stroke> strokesInLasso(InkDocument ink, int page, Path lasso) => [
  for (final s in ink.strokesOn(page))
    if (Select.polygonPercentInside(lasso, s.lowQualityPolygon) >=
        Select.minPercentInside)
      s,
];
