import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/mnote/model/text_clean.dart';
import 'package:saber/mnote/reader/pdf_geometry.dart';

/// UC-01 steps 4–5 and 8 against the real sample paper
/// (test/samples/usecases/arxiv-2610.18579v1.pdf, two-column layout).
void main() {
  late PdfDocument pdf;

  setUpAll(() async {
    await pdfrxInitialize();
    pdf = await PdfDocument.openFile(
      'test/samples/usecases/arxiv-2610.18579v1.pdf',
    );
  });

  tearDownAll(() => pdf.dispose());

  Future<PdfPageTextRange> rangeOf(
    int pageNumber,
    String from,
    String to,
  ) async {
    final text = await pdf.pages[pageNumber - 1].loadStructuredText();
    final start = text.fullText.indexOf(from);
    expect(start, isNonNegative, reason: '"$from" on page $pageNumber');
    final end = text.fullText.indexOf(to, start) + to.length;
    expect(end, greaterThan(start));
    return PdfPageTextRange(pageText: text, start: start, end: end);
  }

  test('paper has 33 pages and an outline', () async {
    expect(pdf.pages.length, 33);
    final outline = await pdf.loadOutline();
    expect(outline.map((n) => n.title), contains('Introduction'));
  });

  test(
    'step 4–5: abstract sentence in the left column, de-hyphenated',
    () async {
      final range = await rangeOf(
        1,
        'System One models choose',
        'single pass.',
      );
      expect(
        cleanExcerptText(range.text),
        'System One models choose an agent’s next action by scoring a supplied set of options in a single pass.',
      );

      final rects = lineRectsForRanges([range]);
      expect(
        rects.length,
        greaterThanOrEqualTo(2),
        reason: 'one rect per printed line',
      );
      final page = pdf.pages[0];
      for (final r in rects) {
        expect(r.page, 1);
        expect(
          r.right,
          lessThan(page.width * 0.55),
          reason: 'stays in the left column',
        );
        expect(r.top, greaterThan(r.bottom));
      }
    },
  );

  test('step 8: evidence sentence keeps 73–85% and §5.1', () async {
    final range = await rangeOf(2, 'For the six most accurate', '(§5.1).');
    final text = cleanExcerptText(range.text);
    expect(
      text,
      startsWith(
        'For the six most accurate systems, 73–85% of decision errors',
      ),
    );
    expect(text, endsWith('the share grows with accuracy (§5.1).'));
    expect(text.contains('\n'), isFalse);
    expect(lineRectsForRanges([range]).every((r) => r.page == 2), isTrue);
  });

  test('step 10: U1D0 notation survives', () async {
    final range = await rangeOf(3, 'U1D0 does not show', 'a shortcut.');
    final text = cleanExcerptText(range.text);
    expect(text, contains('U1D0'));
    expect(text, contains('U0D1'));
  });

  test('step 12: "probe-then-decide" is found on pages 13 and 20', () async {
    final hits = <int>[];
    for (final page in pdf.pages) {
      final t = await page.loadStructuredText();
      if (t.fullText.replaceAll('-\n', '-').contains('probe-then-decide'))
        hits.add(page.pageNumber);
    }
    expect(hits, containsAll([13, 20]));
  });
}
