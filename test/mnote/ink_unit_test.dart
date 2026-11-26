import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/mnote/ink/ink_document.dart';
import 'package:saber/mnote/ink/ink_input_layer.dart';
import 'package:sbn/tool_id.dart';

const _page = Size(612, 792); // US Letter in PDF points

Stroke _line(
  InkDocument ink,
  Offset a,
  Offset b, {
  int page = 1,
  ToolId tool = ToolId.fountainPen,
}) {
  final s = Stroke(
    color: Colors.black,
    pressureEnabled: true,
    options: StrokeOptions(size: 2, isComplete: true),
    pageIndex: page - 1,
    page: ink.pageSize(page, _page),
    toolId: tool,
  );
  for (var i = 0; i <= 10; i++) {
    s.addPoint(Offset.lerp(a, b, i / 10)!, 0.5);
  }
  return s;
}

void main() {
  group('InkDocument', () {
    test('add, remove, undo, redo', () {
      final ink = InkDocument();
      final a = _line(ink, const Offset(10, 10), const Offset(100, 10));
      final b = _line(ink, const Offset(10, 30), const Offset(100, 30));
      final c = _line(ink, const Offset(10, 50), const Offset(100, 50));
      ink
        ..add(1, a)
        ..add(1, b)
        ..add(1, c);
      expect(ink.strokesOn(1), [a, b, c]);

      expect(ink.undo(), isTrue);
      expect(ink.undo(), isTrue);
      expect(ink.strokesOn(1), [a]);
      expect(ink.history.canRedo, isTrue);
      expect(ink.redo(), isTrue);
      expect(ink.strokesOn(1), [a, b]);

      // A new action clears the redo stack (C does not come back).
      final d = _line(ink, const Offset(10, 70), const Offset(100, 70));
      ink.add(1, d);
      expect(ink.history.canRedo, isFalse);
      expect(ink.strokesOn(1), [a, b, d]);

      // Removing (erase) is undoable and restores the original order.
      ink.remove(1, [b]);
      expect(ink.strokesOn(1), [a, d]);
      ink.undo();
      expect(ink.strokesOn(1), [a, b, d]);
    });

    test('BSON round trip keeps pages, points, tools and colours', () {
      final ink = InkDocument();
      ink.add(1, _line(ink, const Offset(10, 10), const Offset(100, 20)));
      ink.add(
        3,
        _line(
          ink,
          const Offset(5, 5),
          const Offset(50, 60),
          page: 3,
          tool: ToolId.highlighter,
        ),
      );
      final back = InkDocument.fromBson(ink.toBson());
      expect(back.pagesWithInk.toSet(), {1, 3});
      final s1 = back.strokesOn(1).single;
      expect(s1.toolId, ToolId.fountainPen);
      expect(s1.length, 11);
      expect(s1.page.size, _page);
      expect(s1.highQualityPolygon, isNotEmpty);
      expect(back.strokesOn(3).single.toolId, ToolId.highlighter);
      expect(back.strokeCount, 2);
    });

    test('lasso selects strokes mostly inside the loop', () {
      final ink = InkDocument();
      final inside = _line(ink, const Offset(110, 110), const Offset(150, 120));
      final outside = _line(
        ink,
        const Offset(300, 300),
        const Offset(350, 310),
      );
      ink
        ..add(1, inside)
        ..add(1, outside);
      final lasso = Path()..addRect(const Rect.fromLTRB(100, 100, 200, 200));
      expect(strokesInLasso(ink, 1, lasso), [inside]);
      expect(
        strokesInLasso(
          ink,
          1,
          Path()..addRect(const Rect.fromLTRB(400, 400, 500, 500)),
        ),
        isEmpty,
      );
    });

    test('eraser hits only strokes it touches', () {
      final ink = InkDocument();
      final a = _line(ink, const Offset(10, 10), const Offset(100, 10));
      final b = _line(ink, const Offset(10, 200), const Offset(100, 200));
      final hits = Eraser(size: 6)
          .checkForOverlappingStrokes(const Offset(50, 11), [a, b]);
      expect(hits, [a]);
    });
  });
}
