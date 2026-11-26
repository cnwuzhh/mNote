import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/mnote/export/pdf_export.dart';
import 'package:saber/mnote/ink/ink_document.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:sbn/tool_id.dart';

/// UC-02 step 11 / TC-EXP-01: export the 33-page paper with a highlight and
/// ink; the result has the same page count and sizes, and the ink is in the
/// rendered page at the right place.
void main() {
  testWidgets('export annotated PDF', (tester) async {
    await tester.runAsync(() async {
      await pdfrxInitialize();
      final pdf = await PdfDocument.openFile(
        'test/samples/usecases/arxiv-2610.18579v1.pdf',
      );
      final p1 = pdf.pages[0];
      final ink = InkDocument();
      final s = Stroke(
        color: const Color(0xFFB4532A),
        pressureEnabled: false,
        options: StrokeOptions(size: 6, isComplete: true),
        pageIndex: 0,
        page: ink.pageSize(1, Size(p1.width, p1.height)),
        toolId: ToolId.fountainPen,
      );
      for (var x = 400.0; x <= 520; x += 4) {
        s.addPoint(Offset(x, 150));
      }
      ink.add(1, s);
      final cards = [
        MCard(
          id: 'c',
          docId: 'd',
          title: 't',
          text: 't',
          color: ExcerptColor.definition,
          rects: const [PageRect(1, 72, 560, 290, 548)],
        ),
      ];

      // One page: ink pixels are red-ish where the stroke is.
      final jpeg = await renderAnnotatedPage(
        p1,
        cards: cards,
        ink: ink,
        scale: 2,
      );
      final img = im.decodeJpg(jpeg)!;
      expect(img.width, (p1.width * 2).round());
      final px = img.getPixel(460 * 2, 150 * 2);
      expect(px.r, greaterThan(140), reason: 'stroke colour at its position');
      expect(px.g, lessThan(130));
      final blank = img.getPixel(460 * 2, 20 * 2); // top margin
      expect(blank.r, greaterThan(230));
      expect(blank.g, greaterThan(230));

      // Whole document.
      final sw = Stopwatch()..start();
      var lastProgress = 0;
      final bytes = await exportAnnotatedPdf(
        document: pdf,
        cards: cards,
        ink: ink,
        onProgress: (d, t) => lastProgress = d,
      );
      sw.stop();
      expect(lastProgress, 33);
      final out = await PdfDocument.openData(bytes);
      expect(out.pages.length, 33);
      for (var i = 0; i < 33; i++) {
        expect(out.pages[i].width, closeTo(pdf.pages[i].width, 0.5));
        expect(out.pages[i].height, closeTo(pdf.pages[i].height, 0.5));
      }
      // ignore: avoid_print
      print(
        'export: ${bytes.length ~/ 1024} KB in ${sw.elapsedMilliseconds} ms (host)',
      );
      expect(bytes.length, lessThan(60 * 1024 * 1024));
      await out.dispose();
      await pdf.dispose();
    });
  });
}
