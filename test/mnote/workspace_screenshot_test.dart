import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/mnote/ink/ink_document.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/pdf_geometry.dart';
import 'package:saber/mnote/reader/workspace_page.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';
import 'package:sbn/tool_id.dart';

/// Renders the workspace to test/mnote/screenshots/*.png for visual review.
/// Not a regression test (fonts depend on the machine); run with:
///   MNOTE_SCREENSHOTS=1 flutter test --update-goldens test/mnote/workspace_screenshot_test.dart
Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    if (File(p).existsSync()) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(p).readAsBytesSync())),
      );
    }
  }
  await loader.load();
}

void main() {
  for (final variant in [
    'day',
    'night',
    'handwrite',
    'cards',
    'map',
    'organize',
    'recall',
    'ai',
    'cite',
    'paper',
    'immersive',
    'shift',
  ]) {
    final night = variant == 'night';
    testWidgets(
      'workspace screenshot $variant',
      skip: Platform.environment['MNOTE_SCREENSHOTS'] != '1',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        late Directory dir;
        late StudyStore store;
        late StudySet set;
        late StudyDoc doc;
        await tester.runAsync(() async {
          const noto = '/usr/share/fonts/opentype/noto';
          final flutterRoot =
              Platform.environment['FLUTTER_ROOT'] ?? 'submodules/flutter';
          final mat = '$flutterRoot/bin/cache/artifacts/material_fonts';
          await _loadFont('Roboto', [
            '$noto/NotoSansCJK-Regular.ttc',
            '$noto/NotoSansCJK-Bold.ttc',
          ]);
          await _loadFont('Noto Serif CJK SC', [
            '$noto/NotoSerifCJK-Regular.ttc',
            '$noto/NotoSerifCJK-Bold.ttc',
          ]);
          await _loadFont('MaterialIcons', ['$mat/MaterialIcons-Regular.otf']);
          await pdfrxInitialize();
          dir = Directory.systemTemp.createTempSync('mnote_shot');
          store = await StudyStore.open(dir);
          set = await store.createSet('Agent 决策失败');
          doc = await store.importPdf(
            set,
            'test/samples/usecases/arxiv-2610.18579v1.pdf',
            pageCount: 33,
          );
        });
        addTearDown(() => dir.deleteSync(recursive: true));

        // Cards from UC-01 steps 5 and 8 (positions read from the paper's text layer).
        final pdf = await tester.runAsync(
          () => PdfDocument.openFile(store.docFile(set, doc).path),
        );
        Future<List<PageRect>> rectsOf(int page, String from, String to) async {
          final t = (await tester.runAsync(
            () => pdf!.pages[page - 1].loadStructuredText(),
          ))!;
          // Words may be separated by line breaks or PDFium hyphen markers.
          RegExp loose(String phrase) => RegExp(
            phrase.split(' ').map(RegExp.escape).join(r'[\s\u0002-]+'),
          );
          final m1 = loose(from).firstMatch(t.fullText)!;
          final m2 = loose(to)
              .allMatches(t.fullText)
              .firstWhere((m) => m.start >= m1.start);
          return lineRectsForRanges([
            PdfPageTextRange(pageText: t, start: m1.start, end: m2.end),
          ]);
        }

        final a = MCard(
          id: 'a',
          docId: doc.id,
          title: 'System One 模型',
          text: 'System One models choose an agent’s next action by scoring a supplied set of options in a single pass.',
          color: ExcerptColor.definition,
          rects: await rectsOf(1, 'System One models choose', 'single pass.'),
        );
        final b = MCard(
          id: 'b',
          docId: doc.id,
          title: '多数错误发生在读对之后',
          text: 'most wrong actions follow correct reading',
          color: ExcerptColor.evidence,
          rects: await rectsOf(
            1,
            'most wrong actions follow',
            'correct reading',
          ),
          parentId: 'a',
        );
        final c = MCard(
          id: 'c',
          docId: doc.id,
          title: '缺的是下一个子目标',
          text: 'what is missing is often not a fact but the next sub-goal.',
          color: ExcerptColor.application,
          rects: await rectsOf(1, 'what is missing is often', 'sub-goal.'),
        );
        store
          ..addCard(set, a)
          ..addCard(set, b)
          ..addCard(set, c);
        if (variant == 'ai') {
          // Real DeepSeek Flash outputs for this sentence (2026-11-27 test).
          final rs = await rectsOf(
            1,
            'Across seventeen fast',
            'take this form.',
          );
          const src =
              'Across seventeen fast systems and a reasoning model, the answer is consistent: most wrong actions follow correct reading, and the more accurate a system, the more of its errors take this form.';
          set.aiNotes
            ..add(
              AiNote(
                id: 'tr',
                docId: doc.id,
                kind: AiNote.translate,
                rects: rs,
                source: src,
                providerName: '腾讯 TokenHub · DeepSeek Flash',
                result: '在十七个快速系统和一个推理模型中，结论是一致的：大多数错误动作都发生在正确读取之后，而且系统越准确，其错误中属于这种形式的比例就越高。',
              ),
            )
            ..add(
              AiNote(
                id: 'ex',
                docId: doc.id,
                kind: AiNote.explain,
                rects: rs,
                source: src,
                providerName: '腾讯 TokenHub · DeepSeek Flash',
                result: '句子意为：在17个快速系统和1个推理模型上结论一致——多数错误行动发生在"正确读取"之后；系统越准确，其错误中这类"读对却做错"的比例越高。重要性在于：错误未必源于理解失败，高准确系统尤其需关注从正确理解到正确行动的转化环节，评测应区分读取与行动。',
              ),
            );
        }
        // Handwriting on page 1: an underline, a circle and a highlighter pass.
        final ink = InkDocument();
        final p1 = pdf!.pages[0];
        final size = Size(p1.width, p1.height);
        Stroke stroke(
          List<Offset> pts, {
          bool hl = false,
          Color color = const Color(0xFFB4532A),
        }) {
          final s = Stroke(
            color: color,
            pressureEnabled: !hl,
            options: StrokeOptions(
              size: hl ? 15 : 2.0,
              thinning: hl ? 0 : 0.5,
              isComplete: true,
            ),
            pageIndex: 0,
            page: ink.pageSize(1, size),
            toolId: hl ? ToolId.highlighter : ToolId.fountainPen,
          );
          for (var i = 0; i < pts.length; i++) {
            s.addPoint(pts[i], 0.35 + 0.3 * (i % 5) / 5);
          }
          return s;
        }

        ink
          ..add(
            1,
            stroke([
              for (var x = 330.0; x <= 560; x += 6)
                Offset(x, 312 + (x % 18) / 9),
            ]),
          )
          ..add(
            1,
            stroke([
              for (var a = 0.0; a <= 6.6; a += 0.2)
                Offset(470 + 52 * math.cos(a), 410 + 16 * math.sin(a)),
            ]),
          )
          ..add(
            1,
            stroke(
              [for (var x = 100.0; x <= 296; x += 8) Offset(x, 443)],
              hl: true,
              color: const Color(0xFFF2CE3C),
            ),
          );
        await tester.runAsync(() => ink.save(store.inkFile(set, doc)));
        await tester.runAsync(() => pdf.dispose());

        mnoteReadingTheme.value = night
            ? ReadingTheme.night
            : (variant == 'paper' ? ReadingTheme.paper : ReadingTheme.day);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.light().copyWith(
              textTheme: ThemeData.light().textTheme.apply(
                fontFamily: 'Roboto',
              ),
            ),
            home: MnoteThemed(
              child: WorkspacePage(store: store, set: set, doc: doc),
            ),
          ),
        );
        for (var i = 0; i < 40; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        Future<void> frames([int n = 10]) async {
          for (var i = 0; i < n; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
        }

        Future<void> mode(String name) async {
          await tester.tap(find.byKey(const ValueKey('mode-menu')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.byKey(ValueKey('mode-menu-$name')).last);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await frames();
        }

        if (variant == 'ai') {
          final ctl = tester
              .widget<PdfViewer>(find.byType(PdfViewer))
              .controller!;
          ctl
              .goTo(Matrix4.translationValues(0, -330, 0)..multiply(ctl.value))
              .ignore();
          await frames(8);
          await tester.tap(find.byKey(const ValueKey('ai-marker-tr')));
          await frames(4);
        }
        if (variant == 'cite') {
          final ctl = tester
              .widget<PdfViewer>(find.byType(PdfViewer))
              .controller!;
          final links = await tester.runAsync(
            () => ctl.pages[0].loadLinks(enableAutoLinkDetection: false),
          );
          final l = links!
              .where(
                (l) =>
                    l.dest?.pageNumber == 24 &&
                    l.dest!.params![1]!.round() == 720,
              )
              .reduce((x, y) => x.rects.first.top > y.rects.first.top ? x : y);
          final r = ctl.calcRectForRectInsidePage(
            pageNumber: 1,
            rect: l.rects.first,
          );
          await tester.tapAt(
            tester.getTopLeft(find.byType(PdfViewer)) +
                ctl.documentToLocal(r.center),
          );
          await frames(10);
        }
        if (variant == 'immersive') {
          await tester.timedDragFrom(
            const Offset(640, 620),
            const Offset(0, -160),
            const Duration(milliseconds: 400),
          );
          await frames(10);
        }
        if (variant == 'shift') {
          await tester.tap(find.byKey(const ValueKey('rail-cards')));
          await frames(10);
        }
        if (variant == 'cards' || variant == 'map') {
          await tester.tap(
            find.byKey(
              ValueKey(variant == 'cards' ? 'rail-cards' : 'rail-map'),
            ),
          );
          await frames();
        }
        if (variant == 'organize') {
          await mode('organize');
          await tester.tap(find.byKey(const ValueKey('mindmap-jump-b')));
          await frames(15);
        }
        if (variant == 'recall') {
          await mode('recall');
          await tester.tap(find.byKey(const ValueKey('mindmap-node-c')));
          await frames(3);
        }
        if (variant == 'handwrite') {
          await tester.tap(find.byKey(const ValueKey('mode-menu')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(
            find.byKey(const ValueKey('mode-menu-handwrite')).last,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          for (var i = 0; i < 10; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
        }
        await expectLater(
          find.byType(WorkspacePage),
          matchesGoldenFile('screenshots/workspace_$variant.png'),
        );
        mnoteReadingTheme.value = ReadingTheme.day;
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }
}
