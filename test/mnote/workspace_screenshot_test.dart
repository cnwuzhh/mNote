import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/pdf_geometry.dart';
import 'package:saber/mnote/reader/workspace_page.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

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
  for (final night in [false, true]) {
    testWidgets(
      'workspace screenshot ${night ? 'night' : 'day'}',
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
        await tester.runAsync(() => pdf!.dispose());

        mnoteNight.value = night;
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
        await expectLater(
          find.byType(WorkspacePage),
          matchesGoldenFile(
            'screenshots/workspace_${night ? 'night' : 'day'}.png',
          ),
        );
        mnoteNight.value = false;
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }
}
