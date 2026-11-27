import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/workspace_page.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// UC-03: immersive reading (scroll hides bars, tap restores) and the
/// three reading themes.
void main() {
  testWidgets('immersive reading and 日间 / 护眼纸色 / 夜读', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => mnoteReadingTheme.value = ReadingTheme.day);

    late Directory dir;
    late StudyStore store;
    late StudySet set;
    late StudyDoc doc;
    await tester.runAsync(() async {
      await pdfrxInitialize();
      dir = Directory.systemTemp.createTempSync('mnote_imm');
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
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    final controller = tester
        .widget<PdfViewer>(find.byType(PdfViewer))
        .controller!;
    for (var i = 0; i < 40 && !controller.isReady; i++) {
      await frames(1);
    }
    await frames(6);
    expect(find.byKey(const ValueKey('btn-outline')), findsOneWidget);
    final pdfWidth = tester.getSize(find.byType(PdfViewer)).width;

    // Scroll down by dragging the page up (touch scrolls in excerpt mode).
    await tester.timedDragFrom(
      const Offset(640, 600),
      const Offset(0, -300),
      const Duration(milliseconds: 400),
    );
    await frames(8);
    expect(
      find.byKey(const ValueKey('btn-outline')),
      findsNothing,
      reason: 'top bar hidden',
    );
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('toolbar-slide')),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isTrue,
    );
    expect(
      tester.getSize(find.byType(PdfViewer)).width,
      pdfWidth,
      reason: 'the page does not re-flow',
    );

    // A tap brings the bars back.
    await tester.tapAt(const Offset(640, 400));
    await frames(8);
    expect(find.byKey(const ValueKey('btn-outline')), findsOneWidget);
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('toolbar-slide')),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isFalse,
    );

    // A jump made by the app (to a card, link target, search hit) is not
    // the user scrolling: the bars stay.
    controller.goToPage(pageNumber: 5).ignore();
    await frames(10);
    expect(controller.pageNumber, 5);
    expect(
      find.byKey(const ValueKey('btn-outline')),
      findsOneWidget,
      reason: 'no immersive on programmatic jumps',
    );

    // Theme menu: three choices; 护眼纸色 tints the surfaces.
    await tester.tap(find.byKey(const ValueKey('btn-theme')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('日间'), findsOneWidget);
    expect(find.text('护眼纸色'), findsOneWidget);
    expect(find.text('夜读'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('theme-paper')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await frames(2);
    expect(mnoteReadingTheme.value, ReadingTheme.paper);
    final pal = MnotePalette.of(tester.element(find.byType(PdfViewer)));
    expect(pal.paperTint, isTrue);
    expect(pageFilterFor(pal), isNotNull);
    expect(mnoteNight.value, isFalse);

    await tester.tap(find.byKey(const ValueKey('btn-theme')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('theme-night')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await frames(2);
    expect(mnoteNight.value, isTrue);
    expect(
      MnotePalette.of(tester.element(find.byType(PdfViewer))).dark,
      isTrue,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'cards overlay slides the page so the right column stays readable',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      late Directory dir;
      late StudyStore store;
      late StudySet set;
      late StudyDoc doc;
      await tester.runAsync(() async {
        await pdfrxInitialize();
        dir = Directory.systemTemp.createTempSync('mnote_shift');
        store = await StudyStore.open(dir);
        set = await store.createSet('S');
        doc = await store.importPdf(
          set,
          'test/samples/usecases/arxiv-2610.18579v1.pdf',
          pageCount: 33,
        );
      });
      addTearDown(() => dir.deleteSync(recursive: true));
      // A card in the right column of page 1 ("When such a model picks the wrong action…").
      store.addCard(
        set,
        MCard(
          id: 'r1',
          docId: doc.id,
          title: 'Right column',
          text: 't',
          color: ExcerptColor.evidence,
          rects: const [PageRect(1, 320, 640, 520, 628)],
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
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pump(const Duration(milliseconds: 60));
        }
      }

      final controller = tester
          .widget<PdfViewer>(find.byType(PdfViewer))
          .controller!;
      for (
        var i = 0;
        i < 40 && find.byKey(const ValueKey('rail-r1')).evaluate().isEmpty;
        i++
      ) {
        await frames(1);
      }
      await frames(4);
      final x0 = controller.value.getTranslation().x;

      await tester.tap(find.byKey(const ValueKey('rail-cards')));
      await frames(10);
      final x1 = controller.value.getTranslation().x;
      expect(
        x0 - x1,
        inInclusiveRange(120, 260),
        reason: 'page slid left (design: about 182 px)',
      );
      // The card's source text now ends left of the overlay.
      final overlayLeft = tester
          .getTopLeft(find.byKey(const ValueKey('panel-cards')))
          .dx;
      final bar = tester.getRect(find.byKey(const ValueKey('rail-r1')));
      final card = tester.getRect(find.byKey(const ValueKey('panel-card-r1')));
      expect(
        (card.top - bar.top).abs(),
        lessThan(40),
        reason: 'card still level with its source',
      );
      expect(overlayLeft, greaterThan(800));

      // Dragging still scrolls the page with the overlay open.
      final y0 = controller.value.getTranslation().y;
      await tester.timedDragFrom(
        const Offset(300, 600),
        const Offset(0, -200),
        const Duration(milliseconds: 400),
      );
      await frames(4);
      expect(controller.value.getTranslation().y, lessThan(y0 - 50));
      expect(find.byKey(const ValueKey('panel-cards')), findsOneWidget);

      // A tap outside closes it and slides the page back.
      await tester.tapAt(const Offset(300, 400));
      await frames(10);
      expect(find.byKey(const ValueKey('panel-cards')), findsNothing);
      expect(
        (controller.value.getTranslation().x - x0).abs(),
        lessThan(2),
        reason: 'slid back',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'organize: source sheet shows the column and the map stays clear of it',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      late Directory dir;
      late StudyStore store;
      late StudySet set;
      late StudyDoc doc;
      await tester.runAsync(() async {
        await pdfrxInitialize();
        dir = Directory.systemTemp.createTempSync('mnote_org');
        store = await StudyStore.open(dir);
        set = await store.createSet('Agent 决策失败');
        doc = await store.importPdf(
          set,
          'test/samples/usecases/arxiv-2610.18579v1.pdf',
          pageCount: 33,
        );
      });
      addTearDown(() => dir.deleteSync(recursive: true));
      // A one-word excerpt ("System", as in the device test) plus a few more cards.
      store
        ..addCard(
          set,
          MCard(
            id: 'w',
            docId: doc.id,
            title: 'CardA',
            text: 'System',
            color: ExcerptColor.definition,
            rects: const [PageRect(1, 72, 560, 110, 548)],
          ),
        )
        ..addCard(
          set,
          MCard(
            id: 'b',
            docId: doc.id,
            title: 'CardB',
            text: 'b',
            color: ExcerptColor.evidence,
            rects: const [PageRect(1, 72, 470, 290, 460)],
            parentId: 'w',
          ),
        )
        ..addCard(
          set,
          MCard(
            id: 'c',
            docId: doc.id,
            title: 'CardC',
            text: 'c',
            color: ExcerptColor.application,
            rects: const [PageRect(1, 320, 640, 520, 628)],
            parentId: 'w',
          ),
        )
        ..addCard(
          set,
          MCard(
            id: 'd',
            docId: doc.id,
            title: 'CardD',
            text: 'd',
            color: ExcerptColor.pitfall,
            rects: const [PageRect(1, 320, 600, 520, 588)],
            parentId: 'b',
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
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pump(const Duration(milliseconds: 60));
        }
      }

      final controller = tester
          .widget<PdfViewer>(find.byType(PdfViewer))
          .controller!;
      for (var i = 0; i < 40 && !controller.isReady; i++) {
        await frames(1);
      }
      await frames(4);
      await tester.tap(find.byKey(const ValueKey('mode-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('mode-menu-organize')).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await frames(4);

      await tester.tap(find.byKey(const ValueKey('mindmap-jump-w')));
      await frames(12);
      expect(find.byKey(const ValueKey('source-sheet')), findsOneWidget);
      final zoom = tester.getSize(find.byKey(const ValueKey('source-zoom')));
      expect(
        zoom.width / zoom.height,
        greaterThan(2.5),
        reason: 'a whole column is shown, not a few enlarged letters',
      );

      final sheetLeft = tester
          .getTopLeft(find.byKey(const ValueKey('source-sheet')))
          .dx;
      for (final id in ['w', 'b', 'c', 'd']) {
        expect(
          tester.getRect(find.byKey(ValueKey('mindmap-node-$id'))).right,
          lessThan(sheetLeft),
          reason: 'node $id not under the sheet',
        );
      }

      // Closing the sheet gives the map the full width again.
      await tester.tap(find.byKey(const ValueKey('source-close')));
      await frames(6);
      expect(find.byKey(const ValueKey('source-sheet')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    },
  );
}
