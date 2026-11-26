import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/mnote/import/url_import.dart';
import 'package:saber/mnote/store/study_store.dart';

const _samplePdf = 'test/samples/usecases/arxiv-2610.18579v1.pdf';

void main() {
  group('normalizePdfUrl', () {
    test('arXiv abstract pages become their PDF', () {
      expect(normalizePdfUrl('https://arxiv.org/abs/2610.18579v1').toString(), 'https://arxiv.org/pdf/2610.18579v1');
      expect(normalizePdfUrl('arxiv.org/abs/2610.18579').toString(), 'https://arxiv.org/pdf/2610.18579');
      expect(normalizePdfUrl('  http://export.arxiv.org/abs/2610.18579v2/ ').toString(), 'https://export.arxiv.org/pdf/2610.18579v2');
      expect(normalizePdfUrl('https://arxiv.org/abs/2610.18579v1#section').toString(), 'https://arxiv.org/pdf/2610.18579v1');
    });

    test('other links are kept; https is added when missing', () {
      expect(normalizePdfUrl('https://arxiv.org/pdf/2610.18579v1').toString(), 'https://arxiv.org/pdf/2610.18579v1');
      expect(normalizePdfUrl('example.com/papers/a.pdf').toString(), 'https://example.com/papers/a.pdf');
      expect(normalizePdfUrl('http://10.0.0.2:8080/x.pdf').toString(), 'http://10.0.0.2:8080/x.pdf');
      expect(normalizePdfUrl('https://example.com/abs/123').toString(), 'https://example.com/abs/123');
    });

    test('rejects empty, malformed and non-http links', () {
      for (final bad in ['', '   ', 'ftp://example.com/a.pdf', 'file:///sdcard/a.pdf', 'https://']) {
        expect(() => normalizePdfUrl(bad), throwsA(isA<UrlImportException>()), reason: bad);
      }
    });
  });

  group('downloadPdf', () {
    late HttpServer server;
    late Directory tmp;
    late List<int> pdfBytes;
    late Uri base;
    final stall = Completer<void>();

    setUpAll(() async {
      pdfBytes = File(_samplePdf).readAsBytesSync();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://${server.address.host}:${server.port}');
      server.listen((req) async {
        final r = req.response;
        switch (req.uri.path) {
          case '/paper':
            r.headers.contentType = ContentType('application', 'pdf');
            r.headers.set('content-disposition', 'inline; filename="Reading Right, Acting Wrong.pdf"');
            r.contentLength = pdfBytes.length;
            r.add(pdfBytes);
          case '/utf8':
            r.headers.set('content-disposition', "attachment; filename*=UTF-8''%E6%B5%8B%E8%AF%95%E8%AE%BA%E6%96%87.pdf");
            r.add(pdfBytes);
          case '/files/paper-v2.pdf':
            r.add(pdfBytes); // chunked, no length, no disposition
          case '/redirect':
            r.statusCode = HttpStatus.found;
            r.headers.set('location', '/paper');
          case '/html':
            r.headers.contentType = ContentType.html;
            r.write('<!doctype html><html><body>Not a PDF</body></html>');
          case '/missing':
            r.statusCode = HttpStatus.notFound;
            r.write('nope');
          case '/huge':
            r.contentLength = 5000;
            r.add(List.filled(5000, 32));
          case '/slow':
            r.bufferOutput = false;
            r.add('%PDF-1.5\n'.codeUnits);
            await r.flush();
            await stall.future; // never sends the rest until the test ends
        }
        await r.close().catchError((_) {});
      });
    });
    tearDownAll(() async {
      if (!stall.isCompleted) stall.complete();
      await server.close(force: true);
    });
    setUp(() => tmp = Directory.systemTemp.createTempSync('mnote_dl'));
    tearDown(() => tmp.deleteSync(recursive: true));

    bool tempEmpty() => tmp.listSync().isEmpty;

    test('downloads a PDF with progress; title from Content-Disposition', () async {
      final progress = <(int, int?)>[];
      final got = await downloadPdf(base.resolve('/paper'), tempDir: tmp, onProgress: (r, t) => progress.add((r, t)));
      expect(got.file.readAsBytesSync(), pdfBytes);
      expect(got.title, 'Reading Right, Acting Wrong');
      expect(got.bytes, pdfBytes.length);
      expect(progress.last, (pdfBytes.length, pdfBytes.length));
    });

    test('title from filename* (UTF-8) and from the URL path', () async {
      expect((await downloadPdf(base.resolve('/utf8'), tempDir: tmp)).title, '测试论文');
      expect((await downloadPdf(base.resolve('/files/paper-v2.pdf'), tempDir: tmp)).title, 'paper-v2');
    });

    test('follows redirects', () async {
      final got = await downloadPdf(base.resolve('/redirect'), tempDir: tmp);
      expect(got.bytes, pdfBytes.length);
    });

    test('a web page is rejected as "not a PDF" and leaves no file', () async {
      await expectLater(
        downloadPdf(base.resolve('/html'), tempDir: tmp),
        throwsA(isA<UrlImportException>().having((e) => e.message, 'message', '这个链接不是 PDF')),
      );
      expect(tempEmpty(), isTrue);
    });

    test('HTTP errors are reported with the status code', () async {
      await expectLater(
        downloadPdf(base.resolve('/missing'), tempDir: tmp),
        throwsA(isA<UrlImportException>().having((e) => e.message, 'message', contains('404'))),
      );
      expect(tempEmpty(), isTrue);
    });

    test('files over the size limit are refused', () async {
      await expectLater(
        downloadPdf(base.resolve('/huge'), tempDir: tmp, maxBytes: 1000),
        throwsA(isA<UrlImportException>().having((e) => e.message, 'message', contains('文件太大'))),
      );
      await expectLater(
        downloadPdf(base.resolve('/files/paper-v2.pdf'), tempDir: tmp, maxBytes: 1000),
        throwsA(isA<UrlImportException>().having((e) => e.message, 'message', contains('文件太大'))),
        reason: 'also without Content-Length',
      );
      expect(tempEmpty(), isTrue);
    });

    test('cancel stops the download and leaves no file', () async {
      final cancel = DownloadCancelToken();
      final f = downloadPdf(base.resolve('/slow'), tempDir: tmp, cancel: cancel, onProgress: (_, _) => cancel.cancel());
      await expectLater(f, throwsA(isA<UrlImportCancelled>()));
      expect(tempEmpty(), isTrue);
    });

    test('a stalled connection times out and leaves no file', () async {
      await expectLater(
        downloadPdf(base.resolve('/slow'), tempDir: tmp, idleTimeout: const Duration(milliseconds: 400)),
        throwsA(isA<UrlImportException>().having((e) => e.message, 'message', contains('下载中断'))),
      );
      expect(tempEmpty(), isTrue);
    });

    test('an unreachable host is reported', () async {
      await expectLater(
        downloadPdf(Uri.parse('http://127.0.0.1:1/x.pdf'), tempDir: tmp),
        throwsA(isA<UrlImportException>().having((e) => e.message, 'message', contains('无法连接'))),
      );
      expect(tempEmpty(), isTrue);
    });

    test('imported document keeps its source link across a restart', () async {
      final got = await downloadPdf(base.resolve('/paper'), tempDir: tmp);
      final dir = Directory.systemTemp.createTempSync('mnote_dl_store');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = await StudyStore.open(dir);
      final set = await store.createSet('S');
      final doc = await store.importPdf(set, got.file.path, title: got.title, pageCount: 33, sourceUrl: got.url.toString());
      await store.flush();
      final back = (await StudyStore.open(dir)).byId(set.id)!.docById(doc.id)!;
      expect(back.sourceUrl, got.url.toString());
      expect(back.title, 'Reading Right, Acting Wrong');
      expect(File('${dir.path}/sets/${set.id}/docs/${back.fileName}').readAsBytesSync(), pdfBytes);
    });
  });
}
