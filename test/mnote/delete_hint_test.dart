import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/workspace_page.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// Deleting a card shows 「已删除…」 with 撤销; the hint must go away by itself
/// (Flutter keeps snack bars that have an action until tapped by default).
void main() {
  testWidgets('delete-card hint offers undo and disappears by itself', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Directory dir;
    late StudyStore store;
    late StudySet set;
    late StudyDoc doc;
    await tester.runAsync(() async {
      await pdfrxInitialize();
      dir = Directory.systemTemp.createTempSync('mnote_snack_test');
      store = await StudyStore.open(dir);
      set = await store.createSet('S');
      doc = await store.importPdf(
        set,
        'test/samples/usecases/arxiv-2610.18579v1.pdf',
        pageCount: 33,
      );
    });
    // A deferred save may still be writing into it; never fail the test on
    // cleaning up a temp folder.
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    store.addCard(
      set,
      MCard(
        id: 'c1',
        docId: doc.id,
        title: 'System One 模型',
        text: 'System One models choose…',
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
    Future<void> frames([int n = 6]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    for (
      var i = 0;
      i < 30 && find.byKey(const ValueKey('rail-c1')).evaluate().isEmpty;
      i++
    ) {
      await frames(1);
    }
    // Open the card from the cards overlay and delete it.
    await tester.tap(find.byKey(const ValueKey('rail-cards')));
    await frames(3);
    await tester.tap(find.byKey(const ValueKey('panel-card-c1')));
    await frames(4);
    await tester.tap(find.byTooltip('删除卡片'));
    await frames(3);

    expect(set.cardById('c1'), isNull);
    expect(find.text('已删除「System One 模型」及其高亮'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    // Advance time in frames, like a device does (the dismiss timer starts
    // once the slide-in animation has finished and the screen redrawn).
    Future<void> advance(Duration d) async {
      for (
        var t = Duration.zero;
        t < d;
        t += const Duration(milliseconds: 100)
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // Still there after 3 s (time to press 撤销) ...
    await advance(const Duration(seconds: 3));
    expect(find.text('已删除「System One 模型」及其高亮'), findsOneWidget);
    // ... and gone by itself shortly after the 5 s duration.
    await advance(const Duration(seconds: 3));
    expect(
      find.text('已删除「System One 模型」及其高亮'),
      findsNothing,
      reason: 'hint dismissed without tapping',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
