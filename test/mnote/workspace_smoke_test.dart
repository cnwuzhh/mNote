import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/workspace_page.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// Renders the full workspace with the 33-page sample paper at the tablet's
/// landscape size and checks the three columns, rail card placement and the
/// mind map, without layout or paint exceptions.
void main() {
  testWidgets('workspace renders the sample paper with a card', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Directory dir;
    late StudyStore store;
    late StudySet set;
    late StudyDoc doc;
    await tester.runAsync(() async {
      await pdfrxInitialize();
      dir = Directory.systemTemp.createTempSync('mnote_ws_test');
      store = await StudyStore.open(dir);
      set = await store.createSet('Agent 决策失败');
      doc = await store.importPdf(
        set,
        'test/samples/usecases/arxiv-2610.18579v1.pdf',
        pageCount: 33,
      );
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    // A card on page 1, left column (abstract), as created in UC-01 step 5.
    store.addCard(
      set,
      MCard(
        id: 'c1',
        docId: doc.id,
        title: 'System One 模型',
        text: 'System One models choose an agent’s next action…',
        color: ExcerptColor.definition,
        rects: const [PageRect(1, 72, 560, 290, 548)],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: MnoteThemed(
          child: WorkspacePage(store: store, set: set, doc: doc),
        ),
      ),
    );
    // Let pdfium open the file and lay out pages.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.textContaining('/ 33 页').evaluate().isNotEmpty &&
          find.byKey(const ValueKey('rail-c1')).evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.textContaining('第 1 / 33 页'), findsOneWidget);
    expect(
      find.text('Agent 决策失败，1 张卡片'),
      findsOneWidget,
      reason: 'mind map header',
    );
    expect(
      find.byKey(const ValueKey('rail-c1')),
      findsOneWidget,
      reason: 'card placed in the margin rail',
    );
    expect(
      find.text('System One 模型'),
      findsWidgets,
      reason: 'rail card + mind-map node',
    );
    expect(find.text('摘录'), findsWidgets, reason: 'bottom mode toolbar');

    // The rail card sits at (or just below) the height of its source text.
    final railTop = tester.getTopLeft(find.byKey(const ValueKey('rail-c1'))).dy;
    expect(railTop, greaterThan(56), reason: 'below the top bar');
    expect(railTop, lessThan(800));

    // Collapse and expand the mind map.
    await tester.tap(find.byKey(const ValueKey('map-collapse')));
    await tester.pump();
    expect(find.byKey(const ValueKey('map-expand')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-expand')));
    await tester.pump();
    expect(find.text('Agent 决策失败，1 张卡片'), findsOneWidget);

    // Switch to box-select: the capture layer appears.
    await tester.tap(find.byKey(const ValueKey('tool-box')));
    await tester.pump();
    expect(find.byKey(const ValueKey('box-select-layer')), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // Drain pdfrx's background page-loading timers after disposal.
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => store.flush());
  });
}
