import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/mnote/reader/link_preview.dart';

/// Internal links of the real paper resolve to the right kind and content.
void main() {
  testWidgets('citations, figures and sections on page 1', (tester) async {
    await tester.runAsync(() async {
      await pdfrxInitialize();
      final pdf = await PdfDocument.openFile(
        'test/samples/usecases/arxiv-2610.18579v1.pdf',
      );
      final refs = await findReferencesPage(pdf);
      expect(
        refs,
        inInclusiveRange(20, 22),
        reason: 'bibliography starts around p.21',
      );

      final links = await pdf.pages[0].loadLinks(
        enableAutoLinkDetection: false,
      );
      Future<LinkTarget?> resolveTo(int page, double y) async {
        final l = links.firstWhere(
          (l) =>
              l.dest?.pageNumber == page &&
              (l.dest!.params?[1] ?? 0).round() == y.round(),
        );
        return resolveLink(pdf, l, fromPage: 1, referencesFrom: refs);
      }

      final typeSafe = (await resolveTo(24, 719.8))!;
      expect(typeSafe.kind, LinkKind.reference);
      expect(typeSafe.page, 24);
      expect(typeSafe.text, startsWith('TypeSafe AI. 2026.'));
      expect(typeSafe.text, contains('Jev'));
      expect(
        typeSafe.text.length,
        lessThan(260),
        reason: 'only this entry, not the next one',
      );

      // The year half of a citation ("2026") is a reference too, not a section.
      final yearHalf = links
          .where(
            (l) =>
                l.dest?.pageNumber == 24 && l.dest!.params![1]!.round() == 720,
          )
          .toList();
      for (final l in yearHalf) {
        expect(
          (await resolveLink(pdf, l, fromPage: 1))!.kind,
          LinkKind.reference,
          reason: 'without knowing the bibliography page',
        );
      }

      final turpin = (await resolveTo(24, 90.97))!;
      expect(turpin.text, startsWith('Miles Turpin'));

      final fig = (await resolveTo(2, 777.8))!;
      expect(fig.kind, LinkKind.figure);
      expect(fig.region.height, greaterThan(200));

      final sec = (await resolveTo(4, 163.9))!;
      expect(sec.kind, LinkKind.section);
      expect(sec.page, 4);

      final url = links
          .where((l) => l.url != null)
          .map((l) => l.url.toString());
      expect(url, contains('https://arxiv.org/abs/2610.18579v1'));
      await pdf.dispose();
    });
  });
}
