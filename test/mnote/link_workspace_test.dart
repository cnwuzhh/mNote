import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/workspace_page.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// Tap the real "(TypeSafe AI, 2026)" citation on page 1: preview with the
/// bibliography entry, 「跳到参考文献」 to p.24, 「返回第 1 页」 back.
void main() {
  testWidgets('citation preview, follow, return', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Directory dir;
    late StudyStore store;
    late StudySet set;
    late StudyDoc doc;
    await tester.runAsync(() async {
      await pdfrxInitialize();
      dir = Directory.systemTemp.createTempSync('mnote_link_ws');
      store = await StudyStore.open(dir);
      set = await store.createSet('S');
      doc = await store.importPdf(
        set,
        'test/samples/usecases/arxiv-2610.18579v1.pdf',
        pageCount: 33,
      );
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: MnoteThemed(
          child: WorkspacePage(store: store, set: set, doc: doc),
        ),
      ),
    );
    Future<void> frames([int n = 6]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final controller = tester
        .widget<PdfViewer>(find.byType(PdfViewer))
        .controller!;
    for (var i = 0; i < 40 && !controller.isReady; i++) {
      await frames(1);
    }
    await frames(8);

    // Where the first "TypeSafe AI" citation is on screen.
    final links = await tester.runAsync(
      () => controller.pages[0].loadLinks(enableAutoLinkDetection: false),
    );
    // Two citations point there; take the upper one (abstract, right column).
    final link = links!
        .where(
          (l) => l.dest?.pageNumber == 24 && l.dest!.params![1]!.round() == 720,
        )
        .reduce((a, b) => a.rects.first.top > b.rects.first.top ? a : b);
    final docRect = controller.calcRectForRectInsidePage(
      pageNumber: 1,
      rect: link.rects.first,
    );
    final viewer = tester.getTopLeft(find.byType(PdfViewer));
    final at = viewer + controller.documentToLocal(docRect.center);
    expect(
      at.dy,
      inInclusiveRange(60, 760),
      reason: 'citation visible on the first screen',
    );

    await tester.tapAt(at);
    await frames(10);
    expect(find.byKey(const ValueKey('link-preview')), findsOneWidget);
    expect(find.text('参考文献，第 24 页'), findsOneWidget);
    expect(find.textContaining('TypeSafe AI. 2026.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('link-go')));
    await frames(12);
    expect(controller.pageNumber, 24);
    expect(find.byKey(const ValueKey('link-preview')), findsNothing);
    expect(find.text('返回第 1 页'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('btn-return')));
    await frames(12);
    expect(controller.pageNumber, 1);
    expect(find.byKey(const ValueKey('btn-return')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
