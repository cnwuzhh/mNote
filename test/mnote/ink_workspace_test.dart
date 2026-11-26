import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/mnote/ink/ink_document.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/workspace_page.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// UC-02 steps 1–3, B1 on the real paper: the stylus writes at the right PDF
/// coordinates, a finger does not (until finger drawing is turned on), and
/// the ink is saved per document.
void main() {
  testWidgets('handwrite mode: stylus writes, finger scrolls, ink persists', (
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
      dir = Directory.systemTemp.createTempSync('mnote_ink_test');
      store = await StudyStore.open(dir);
      set = await store.createSet('Ink');
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
    Future<void> settle([int n = 20]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    await settle(30);
    final controller = tester
        .widget<PdfViewer>(find.byType(PdfViewer))
        .controller!;
    expect(controller.isReady, isTrue);

    // Global position of a point given in page-1 space (PDF points, top-left origin).
    final viewerTopLeft = tester.getTopLeft(find.byType(PdfViewer));
    Offset globalOf(Offset pagePt) {
      final r = controller.layout.pageLayouts[0];
      final k = r.width / controller.pages[0].width;
      return viewerTopLeft + controller.documentToLocal(r.topLeft + pagePt * k);
    }

    Future<void> drag(Offset fromPagePt, PointerDeviceKind kind) async {
      final start = globalOf(fromPagePt);
      final g = await tester.startGesture(start, kind: kind);
      for (var i = 1; i <= 6; i++) {
        await g.moveTo(start + Offset(10.0 * i, 2.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump();
    }

    bool undoEnabled() =>
        tester
            .widget<InkWell>(
              find.descendant(
                of: find.byKey(const ValueKey('ink-undo')),
                matching: find.byType(InkWell),
              ),
            )
            .onTap !=
        null;

    await tester.tap(find.byKey(const ValueKey('mode-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('mode-menu-handwrite')).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(5);
    // Icon-only tools carry their names as tooltips.
    expect(find.byTooltip('钢笔'), findsOneWidget);
    expect(find.byTooltip('套索'), findsOneWidget);
    expect(find.byTooltip('手指书写：关'), findsOneWidget);
    // The whole tool group fits: the last control is on screen.
    expect(
      tester.getRect(find.byKey(const ValueKey('ink-finger'))).right,
      lessThan(1280 - 200),
    );
    expect(undoEnabled(), isFalse);

    // 1) Stylus writes.
    await drag(const Offset(400, 160), PointerDeviceKind.stylus);
    expect(undoEnabled(), isTrue, reason: 'a stroke was added');

    // 2) Finger does not write (it scrolls the PDF instead).
    await drag(const Offset(400, 300), PointerDeviceKind.touch);
    await settle(3);

    // 3) With finger drawing on, a finger writes too.
    await tester.tap(find.byKey(const ValueKey('ink-finger')));
    await tester.pump();
    expect(find.byTooltip('手指书写：开'), findsOneWidget);
    expect(store.fingerDrawing, isTrue);
    await drag(const Offset(400, 250), PointerDeviceKind.touch);

    // Undo / redo.
    await tester.tap(find.byKey(const ValueKey('ink-undo')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ink-redo')));
    await tester.pump();

    // The 600 ms save debounce fires, and dispose saves anything pending.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    // Saving runs in the widget's (fake-async) zone: keep pumping while
    // giving real IO time, then read the file.
    InkDocument? saved;
    for (var i = 0; i < 50 && (saved?.strokeCount ?? 0) < 2; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      saved = await tester.runAsync<InkDocument?>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final f = store.inkFile(set, doc);
        if (!f.existsSync()) return null;
        return InkDocument.load(f);
      });
    }
    expect(saved, isNotNull, reason: 'ink file written');
    final strokes = saved!.strokesOn(1);
    expect(
      strokes.length,
      2,
      reason: 'stylus stroke + finger stroke with finger drawing on',
    );

    // The first stroke starts where the stylus touched, in PDF page space
    // (within a few points: the finger drag may have scrolled the view, but
    // the stylus stroke was recorded before that).
    final first = strokes.first.highQualityPolygon;
    final b = first.reduce(
      (a, c) => Offset(a.dx < c.dx ? a.dx : c.dx, a.dy < c.dy ? a.dy : c.dy),
    );
    expect((b.dx - 400).abs(), lessThan(6), reason: 'x of stroke start ($b)');
    expect((b.dy - 160).abs(), lessThan(6), reason: 'y of stroke start ($b)');

    // Setting persisted.
    final reopened = await tester.runAsync(() => StudyStore.open(dir));
    expect(reopened!.fingerDrawing, isTrue);
  });

  testWidgets('lasso around ink -> image card in margin and mind map', (
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
      dir = Directory.systemTemp.createTempSync('mnote_lasso_test');
      store = await StudyStore.open(dir);
      set = await store.createSet('Lasso');
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
    Future<void> settle([int n = 20]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    await settle(30);
    final controller = tester
        .widget<PdfViewer>(find.byType(PdfViewer))
        .controller!;
    final viewerTopLeft = tester.getTopLeft(find.byType(PdfViewer));
    Offset globalOf(Offset pagePt) {
      final r = controller.layout.pageLayouts[0];
      final k = r.width / controller.pages[0].width;
      return viewerTopLeft + controller.documentToLocal(r.topLeft + pagePt * k);
    }

    Future<void> stylusPath(List<Offset> pagePts) async {
      final g = await tester.startGesture(
        globalOf(pagePts.first),
        kind: PointerDeviceKind.stylus,
      );
      for (final pt in pagePts.skip(1)) {
        await g.moveTo(globalOf(pt));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump();
    }

    await tester.tap(find.byKey(const ValueKey('mode-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('mode-menu-handwrite')).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(5);
    // A short stroke in the right margin area of the abstract.
    await stylusPath([for (var x = 430.0; x <= 490; x += 10) Offset(x, 200)]);

    // Lasso tool, loop around the stroke.
    await tester.tap(find.byKey(const ValueKey('ink-lasso')));
    await tester.pump();
    await stylusPath(const [
      Offset(415, 180),
      Offset(505, 180),
      Offset(505, 220),
      Offset(415, 220),
      Offset(415, 182),
    ]);
    expect(
      find.byKey(const ValueKey('lasso-to-card')),
      findsOneWidget,
      reason: 'lasso menu',
    );

    await tester.tap(find.byKey(const ValueKey('lasso-to-card')));
    await settle(20);

    final cards = set.mapCards.toList();
    expect(cards, hasLength(1));
    final card = cards.single;
    expect(card.title, '手写摘录 p.1');
    expect(card.image, isNotNull);
    expect(store.imageFile(set, card.image!).existsSync(), isTrue);
    // Source rect (PDF coords, y up) covers the stroke at y = 200 from the top.
    final r = card.rects.single;
    final pageH = controller.pages[0].height;
    expect(r.left, lessThan(430));
    expect(r.right, greaterThan(490));
    expect(pageH - r.top, lessThan(200));
    expect(pageH - r.bottom, greaterThan(200));
    expect(
      find.byKey(ValueKey('rail-${card.id}')),
      findsOneWidget,
      reason: 'card in margin rail',
    );
    expect(
      find.byKey(const ValueKey('lasso-to-card')),
      findsNothing,
      reason: 'menu closed',
    );

    // Lasso around nothing -> no menu.
    await stylusPath(const [
      Offset(60, 700),
      Offset(120, 700),
      Offset(120, 740),
      Offset(60, 740),
      Offset(60, 702),
    ]);
    expect(find.byKey(const ValueKey('lasso-to-card')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
