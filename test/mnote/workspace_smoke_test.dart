import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/workspace_page.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// Layout v2 (design/layout-v2, option D) end to end on the real paper at the
/// tablet's landscape size: reading with the edge rail, the cards and mind-map
/// overlays (the PDF never moves), hiding the rail, organize mode with the
/// source sheet, and recall mode — without layout or paint exceptions.
void main() {
  testWidgets('layout v2: reading, overlays, organize, recall', (tester) async {
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

    // A card on page 1 (abstract), as created in UC-01 step 5.
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
    Future<void> settle([int n = 6]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    Future<void> selectMode(String name) async {
      await tester.tap(find.byKey(const ValueKey('mode-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(ValueKey('mode-menu-$name')).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settle(3);
    }

    // Let pdfium open the file and lay out pages.
    for (var i = 0; i < 30; i++) {
      await settle(1);
      if (find.byKey(const ValueKey('rail-c1')).evaluate().isNotEmpty) break;
    }

    // ---- reading: PDF fills the width, narrow rail with one bar ----
    expect(find.textContaining('第 1 / 33 页'), findsOneWidget);
    final pdfRect = tester.getRect(find.byType(PdfViewer));
    expect(
      pdfRect.width,
      greaterThan(1200),
      reason: 'PDF nearly full width (was ~640 with three columns)',
    );
    expect(find.byKey(const ValueKey('rail-count')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('rail-count'))).data,
      '1',
    );
    final bar = tester.getRect(find.byKey(const ValueKey('rail-c1')));
    expect(
      bar.left,
      greaterThan(1236),
      reason: 'bar is on the 44 px edge rail',
    );
    expect(bar.top, greaterThan(56));
    expect(bar.top, lessThan(800));
    expect(find.text('摘录'), findsOneWidget, reason: 'mode chip');

    // ---- cards overlay: covers the PDF, which stays where it is ----
    await tester.tap(find.byKey(const ValueKey('rail-cards')));
    await settle(3);
    expect(find.byKey(const ValueKey('panel-cards')), findsOneWidget);
    expect(find.byKey(const ValueKey('panel-card-c1')), findsOneWidget);
    expect(
      tester.getRect(find.byType(PdfViewer)),
      pdfRect,
      reason: 'PDF does not move',
    );
    // The card sits at the height of its bar (same source).
    final cardTop = tester
        .getTopLeft(find.byKey(const ValueKey('panel-card-c1')))
        .dy;
    expect((cardTop - bar.top).abs(), lessThan(40));

    // Switch to the mind map inside the overlay.
    await tester.tap(find.byKey(const ValueKey('panel-tab-map')));
    await settle(3);
    expect(find.byKey(const ValueKey('panel-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('mindmap-root')), findsOneWidget);
    expect(tester.getRect(find.byType(PdfViewer)), pdfRect);
    // Tap outside closes it.
    await tester.tapAt(const Offset(150, 400));
    await settle(2);
    expect(find.byKey(const ValueKey('panel-map')), findsNothing);

    // ---- hide / show the rail ----
    await tester.tap(find.byKey(const ValueKey('rail-hide')));
    await settle(2);
    expect(find.byKey(const ValueKey('rail-count')), findsNothing);
    expect(find.byKey(const ValueKey('rail-handle')), findsOneWidget);
    expect(
      tester.getRect(find.byType(PdfViewer)),
      pdfRect,
      reason: 'PDF keeps its layout',
    );
    await tester.tap(find.byKey(const ValueKey('rail-handle')));
    await settle(2);
    expect(find.byKey(const ValueKey('rail-count')), findsOneWidget);

    // ---- box select still works in the new layout ----
    await tester.tap(find.byKey(const ValueKey('tool-box')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('box-select-layer')), findsOneWidget);
    // The hint floats above the toolbar, which stays usable.
    final hint = tester.getRect(find.text('在页面上拖出一个矩形来截取区域'));
    final chip = tester.getRect(find.byKey(const ValueKey('mode-menu')));
    expect(
      hint.bottom,
      lessThanOrEqualTo(chip.top),
      reason: 'hint does not cover the toolbar',
    );
    await tester.tap(find.byKey(const ValueKey('tool-text')));
    await tester.pump();

    // ---- organize: mind map fills the screen; source sheet ----
    await selectMode('organize');
    expect(find.byKey(const ValueKey('map-view-organize')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rail-count')),
      findsNothing,
      reason: 'no rail outside reading',
    );
    await tester.tap(find.byKey(const ValueKey('mindmap-jump-c1')));
    await settle(8);
    expect(find.byKey(const ValueKey('source-sheet')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('source-zoom')),
      findsOneWidget,
      reason: 'zoomed paragraph rendered',
    );
    // "去阅读" goes back to the reader.
    await tester.tap(find.byKey(const ValueKey('source-read')));
    await settle(6);
    expect(find.byKey(const ValueKey('map-view-organize')), findsNothing);
    expect(find.byKey(const ValueKey('rail-count')), findsOneWidget);

    // ---- recall: contents hidden until tapped ----
    await selectMode('recall');
    expect(find.byKey(const ValueKey('map-view-recall')), findsOneWidget);
    expect(
      find.text('System One 模型'),
      findsNothing,
      reason: 'card title hidden',
    );
    expect(find.textContaining('未揭开 1 张'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mindmap-node-c1')));
    await tester.pump();
    expect(find.text('System One 模型'), findsOneWidget, reason: 'revealed');
    expect(find.text('已全部揭开'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recall-remask')));
    await tester.pump();
    expect(find.text('System One 模型'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('recall-reveal-all')));
    await tester.pump();
    expect(find.text('System One 模型'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // Drain pdfrx's background page-loading timers after disposal.
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => store.flush());
  });
}
