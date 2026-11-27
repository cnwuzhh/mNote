import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/mnote/bookshelf/bookshelf_page.dart';
import 'package:saber/mnote/import/url_import.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/store/study_store.dart';

import '../utils/test_mock_channel_handlers.dart';

/// UI flow of "从网络链接" import against a local HTTP server.
void main() {
  late HttpServer server;
  late Uri base;

  setUpAll(() async {
    final pdf = File('test/samples/usecases/arxiv-2610.18579v1.pdf')
        .readAsBytesSync();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://${server.address.host}:${server.port}');
    server.listen((req) async {
      final r = req.response;
      if (req.uri.path == '/paper.pdf') {
        r.headers.set(
          'content-disposition',
          'inline; filename="2610.18579v1.pdf"',
        );
        r.contentLength = pdf.length;
        r.add(pdf);
      } else {
        r.headers.contentType = ContentType.html;
        r.write('<html>hello</html>');
      }
      await r.close();
    });
  });
  tearDownAll(() => server.close(force: true));

  Future<(StudyStore, StudySet, Directory)> setUpStore(
    WidgetTester tester,
  ) async {
    late StudyStore store;
    late StudySet set;
    late Directory dir;
    setupMockPathProvider(); // getTemporaryDirectory for the download
    await tester.runAsync(() async {
      await pdfrxInitialize();
      dir = Directory.systemTemp.createTempSync('mnote_url_ui');
      store = await StudyStore.open(dir);
      set = await store.createSet('Agent');
    });
    // flutter_test fakes all HTTP inside a test; use a real client for the local server.
    httpClientFactory = () =>
        HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
    addTearDown(() => httpClientFactory = HttpClient.new);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: StudySetPage(store: store, set: set),
      ),
    );
    await tester.pump();
    return (store, set, dir);
  }

  Future<void> enterLink(WidgetTester tester, String link) async {
    await tester.tap(find.byKey(const ValueKey('btn-import-pdf')));
    await tester.pumpAndSettle();
    expect(find.text('从本机选择'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-url')));
    await tester.pumpAndSettle();
    // The dialog opens after the clipboard was read (to prefill a link).
    for (
      var i = 0;
      i < 40 && find.byKey(const ValueKey('url-field')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.enterText(find.byKey(const ValueKey('url-field')), link);
    await tester.tap(find.byKey(const ValueKey('url-ok')));
    await tester.pump();
  }

  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 80 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('link -> download -> document with source', (tester) async {
    final (store, set, dir) = await setUpStore(tester);
    // A deferred save may still be writing into it; never fail the test on
    // cleaning up a temp folder.
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    await enterLink(tester, base.resolve('/paper.pdf').toString());
    await waitFor(tester, () => set.docs.isNotEmpty);

    expect(set.docs, hasLength(1));
    final doc = set.docs.single;
    expect(doc.title, '2610.18579v1');
    expect(doc.pageCount, 33);
    expect(doc.sourceUrl, base.resolve('/paper.pdf').toString());
    expect(
      File('${dir.path}/sets/${set.id}/docs/${doc.fileName}').existsSync(),
      isTrue,
    );

    // (The reader opens next; its own tests cover it.) Show the set page
    // again and check the list shows where the document came from.
    await tester.pumpWidget(const SizedBox()); // drop the reader route
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(
      MaterialApp(
        home: StudySetPage(store: store, set: set),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('来自 127.0.0.1/paper.pdf'), findsOneWidget);

    // Long-press to rename.
    await tester.longPress(find.byKey(ValueKey('doc-${doc.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-field')),
      'Reading Right',
    );
    await tester.tap(find.byKey(const ValueKey('prompt-ok')));
    await tester.pumpAndSettle();
    expect(doc.title, 'Reading Right');

    // Let the debounced save run on the test clock (store.flush from
    // runAsync would wait for writes queued on the fake clock).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a web page link shows "这个链接不是 PDF" and adds nothing', (
    tester,
  ) async {
    final (store, set, dir) = await setUpStore(tester);
    // A deferred save may still be writing into it; never fail the test on
    // cleaning up a temp folder.
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    await enterLink(tester, base.resolve('/page').toString());
    await waitFor(
      tester,
      () => find.byKey(const ValueKey('url-error')).evaluate().isNotEmpty,
    );
    expect(find.text('这个链接不是 PDF'), findsOneWidget);
    expect(set.docs, isEmpty);
    // Let the debounced save run on the test clock (store.flush from
    // runAsync would wait for writes queued on the fake clock).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  });

  testWidgets('an invalid link is rejected in the dialog', (tester) async {
    final (store, set, dir) = await setUpStore(tester);
    // A deferred save may still be writing into it; never fail the test on
    // cleaning up a temp folder.
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    await enterLink(tester, 'ftp://example.com/a.pdf');
    await tester.pump();
    expect(find.text('只支持 http 或 https 链接'), findsOneWidget);
    expect(find.byKey(const ValueKey('url-progress')), findsNothing);
    // Let the debounced save run on the test clock (store.flush from
    // runAsync would wait for writes queued on the fake clock).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  });
}

class _RealHttp extends HttpOverrides;
