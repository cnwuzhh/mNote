import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:sbn/tool_id.dart';

/// Ink tools of the handwrite mode.
enum InkTool {
  pen('钢笔'),
  highlighter('荧光笔'),
  eraser('橡皮'),
  lasso('套索');

  new(this.label);
  final String label;
}

/// Three widths per drawing tool, in PDF points.
enum InkWidth {
  thin('细', 1.2, 10),
  medium('中', 2.0, 15),
  thick('粗', 3.4, 22);

  new(this.label, this.pen, this.highlighter);
  final String label;
  final double pen, highlighter;
}

const penColors = <Color>[
  Color(0xFF1F1B16), // ink
  Color(0xFFB4532A), // vermilion
  Color(0xFF2F5FA8), // blue
  Color(0xFF3F7F33), // green
];

const highlighterColors = <Color>[
  Color(0xFFF2CE3C), // yellow
  Color(0xFF8CCB6E), // green
  Color(0xFF7FB2E8), // blue
  Color(0xFFF29AB0), // pink
];

/// Paints [strokes] in page space (the caller has already transformed the
/// canvas so that 1 unit = 1 PDF point, origin at the page's top-left).
///
/// Highlighters are drawn in a darken (or, in night mode, lighten) layer like
/// Saber does, so text underneath stays fully readable.
void paintInk(
  Canvas canvas,
  Iterable<Stroke> strokes, {
  required Rect bounds,
  bool dark = false,
  Set<Stroke> selected = const {},
  Color? selectionColor,
}) {
  final list = strokes.toList(growable: false);
  if (list.isEmpty) return;
  final layerBounds = bounds.inflate(200);

  Color? lastColor;
  var layerOpen = false;
  for (final s in list) {
    if (s.toolId != ToolId.highlighter) continue;
    final color = s.color.withValues(alpha: 1).withInversion(dark);
    if (color != lastColor) {
      if (layerOpen) canvas.restore();
      canvas.saveLayer(
        layerBounds,
        Paint()
          ..blendMode = dark ? BlendMode.lighten : BlendMode.darken
          ..color = Colors.white.withAlpha(110),
      );
      layerOpen = true;
      lastColor = color;
    }
    canvas.drawPath(s.highQualityPath, Paint()..color = color);
  }
  if (layerOpen) canvas.restore();

  final paint = Paint();
  for (final s in list) {
    if (s.toolId == ToolId.highlighter) continue;
    var color = s.color.withInversion(dark);
    if (selected.contains(s) && selectionColor != null) {
      color = Color.lerp(color, selectionColor, 0.6)!;
    }
    paint.color = color;
    canvas.drawPath(s.highQualityPath, paint);
  }
  // Selected highlighters get an outline so they visibly change too.
  if (selectionColor != null) {
    final outline = Paint()
      ..color = selectionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (final s in list) {
      if (s.toolId == ToolId.highlighter && selected.contains(s)) {
        canvas.drawPath(s.lowQualityPath, outline);
      }
    }
  }
}

/// Bounds of a stroke's outline polygon in page space.
Rect strokeBounds(Stroke s) {
  final poly = s.lowQualityPolygon;
  if (poly.isEmpty) return Rect.zero;
  var l = poly.first.dx, r = l, t = poly.first.dy, b = t;
  for (final p in poly) {
    if (p.dx < l) l = p.dx;
    if (p.dx > r) r = p.dx;
    if (p.dy < t) t = p.dy;
    if (p.dy > b) b = p.dy;
  }
  return Rect.fromLTRB(l, t, r, b);
}

/// Draws [image] (a rendering of [region] of a page at [scale] px per point)
/// and the [strokes] on top into a new image.
Future<ui.Image> composeRegion(
  ui.Image image,
  Rect region,
  double scale,
  Iterable<Stroke> strokes,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(image, Offset.zero, Paint());
  canvas.scale(scale);
  canvas.translate(-region.left, -region.top);
  paintInk(canvas, strokes, bounds: region);
  final picture = recorder.endRecording();
  return picture.toImage(image.width, image.height);
}
