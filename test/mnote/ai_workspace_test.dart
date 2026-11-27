import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/mnote/ai/ai_client.dart';
import 'package:saber/mnote/ai/ai_config.dart';
import 'package:saber/mnote/ai/ai_settings_page.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/workspace_page.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// UC-03 translate/explain markers in the real workspace, against a fake
/// OpenAI-compatible service that streams slowly.
void main() {
  late HttpServer server;
  late String base;
  final release = <Completer<void>>[];

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      await utf8.decodeStream(req);
      final r = req.response;
      r.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      r.bufferOutput = false;
      if (req.uri.path.startsWith('/fail')) {
        r.statusCode = 500;
        r.write('{"error":{"message":"server exploded"}}');
        await r.close();
        return;
      }
      void sse(String t) => r.write(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': t},
            },
          ],
        })}\n\n',
      );
      sse('在十七个快速系统中，');
      await r.flush();
      final gate = Completer<void>();
      release.add(gate);
      await gate.future; // the test decides when the rest arrives
      sse('结论是一致的。');
      r.write('data: [DONE]\n\n');
      await r.close();
    });
  });
  tearDownAll(() async {
    for (final g in release) {
      if (!g.isCompleted) g.complete();
    }
    await server.close(force: true);
  });

  testWidgets(
    'translate: loading marker, streaming panel, collapse, reopen, card, hide, error',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      aiHttpClientFactory = () =>
          HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
      addTearDown(() => aiHttpClientFactory = HttpClient.new);
      aiConfigStore = MemoryAiConfigStore(
        AiConfig.parse(
          jsonEncode({
            'default': 'a',
            'providers': [
              {
                'id': 'a',
                'name': 'Service A',
                'baseUrl': '$base/ok',
                'apiKey': 'k',
                'model': 'm',
              },
              {
                'id': 'f',
                'name': 'Broken',
                'baseUrl': '$base/fail',
                'apiKey': 'k',
                'model': 'm',
              },
            ],
            'tasks': {'explain': 'f'},
          }),
        ),
      );
      addTearDown(() => aiConfigStore = AiConfigStore());

      late Directory dir;
      late StudyStore store;
      late StudySet set;
      late StudyDoc doc;
      await tester.runAsync(() async {
        await pdfrxInitialize();
        dir = Directory.systemTemp.createTempSync('mnote_ai_ws');
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
          await tester.pump(const Duration(milliseconds: 40));
        }
      }

      final controller = tester
          .widget<PdfViewer>(find.byType(PdfViewer))
          .controller!;
      for (var i = 0; i < 40 && !controller.isReady; i++) {
        await frames(1);
      }
      await frames(6);

      // The first abstract sentence (as UC-01's first card).
      const rects = [PageRect(1, 72, 560, 290, 548)];
      final dynamic state = tester.state(find.byType(WorkspacePage));
      final AiNote note = state.startAiNote(
        AiNote.translate,
        rects,
        'System One models choose an agent’s next action…',
      );
      await frames(10);

      // Streaming: first part shown, marker in loading state.
      expect(find.byKey(const ValueKey('ai-panel')), findsOneWidget);
      expect(find.textContaining('在十七个快速系统中，'), findsOneWidget);
      expect(find.byTooltip('AI 翻译（生成中）'), findsOneWidget);
      expect(find.byKey(ValueKey('ai-marker-${note.id}')), findsOneWidget);

      release.last.complete();
      await frames(10);
      expect(find.textContaining('在十七个快速系统中，结论是一致的。'), findsOneWidget);
      expect(find.textContaining('AI 生成 · Service A · 可能有误'), findsOneWidget);
      expect(note.result, '在十七个快速系统中，结论是一致的。');
      expect(note.providerName, 'Service A');

      // The panel sits above the passage when there is room (does not cover it).
      final panel = tester.getRect(find.byKey(const ValueKey('ai-panel')));
      final marker = tester.getRect(
        find.byKey(ValueKey('ai-marker-${note.id}')),
      );
      expect(
        panel.bottom,
        lessThan(marker.top + 30),
        reason: 'panel above the passage',
      );

      // Tap elsewhere: collapses into the 「译」 marker.
      await tester.tapAt(
        const Offset(950, 640),
      ); // on the page, away from panel and toolbar
      await frames(2);
      expect(find.byKey(const ValueKey('ai-panel')), findsNothing);
      expect(find.text('译'), findsOneWidget);

      // Tap the marker: opens again, no new request.
      final before = release.length;
      await tester.tap(find.byKey(ValueKey('ai-marker-${note.id}')));
      await frames(2);
      expect(find.textContaining('结论是一致的。'), findsOneWidget);
      expect(release.length, before, reason: 'saved result reused');

      // 摘录为卡片（附译文）.
      await tester.tap(find.byKey(const ValueKey('ai-make-card')));
      await frames(4);
      final card = set.mapCards.single;
      expect(card.note, contains('【AI 译文】在十七个快速系统中'));
      expect(card.rects.single.page, 1);

      // Hide all markers.
      await tester.tap(find.byKey(const ValueKey('btn-ai-marks')));
      await frames(2);
      expect(find.byKey(ValueKey('ai-marker-${note.id}')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('btn-ai-marks')));
      await frames(2);
      expect(find.byKey(ValueKey('ai-marker-${note.id}')), findsOneWidget);

      // Explain routed to the broken service: marker shows "!", panel the error + retry.
      final AiNote bad = state.startAiNote(AiNote.explain, const [
        PageRect(1, 72, 470, 290, 460),
      ], 'most wrong actions follow correct reading');
      await frames(10);
      expect(find.byKey(const ValueKey('ai-panel-error')), findsOneWidget);
      expect(find.textContaining('server exploded'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-regenerate')), findsOneWidget);
      expect(find.byTooltip('AI 解释（失败，点开重试）'), findsOneWidget);

      // Delete it from the panel.
      await tester.tap(find.byKey(const ValueKey('ai-delete')));
      await frames(2);
      expect(set.aiNotes.map((n) => n.id), [note.id]);
      expect(find.byKey(ValueKey('ai-marker-${bad.id}')), findsNothing);

      // Saved with the set.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      final saved = jsonDecode(
        File('${dir.path}/sets/${set.id}/set.json').readAsStringSync(),
      ) as Map;
      expect((saved['aiNotes'] as List).single['result'], '在十七个快速系统中，结论是一致的。');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    },
  );
}

class _RealHttp extends HttpOverrides;
