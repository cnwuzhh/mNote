import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Creates the HTTP client for downloads. Widget tests replace HTTP with a
/// fake that answers 400; tests can set this to get a real client.
@visibleForTesting
HttpClient Function() httpClientFactory = HttpClient.new;

/// Largest PDF accepted from a link.
const maxPdfDownloadBytes = 200 * 1024 * 1024;

/// Why a link could not be imported. [message] is shown to the user.
class UrlImportException implements Exception {
  new(this.message);
  final String message;
  @override
  String toString() => message;
}

class UrlImportCancelled implements Exception {
  @override
  String toString() => '已取消';
}

/// Turns what the user pasted into the URL to download:
/// * adds `https://` when no scheme is given;
/// * only http and https are accepted;
/// * arXiv abstract pages (`arxiv.org/abs/<id>`, with or without a version)
///   become their PDF (`arxiv.org/pdf/<id>`).
Uri normalizePdfUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) throw UrlImportException('请输入链接');
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(s)) s = 'https://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) throw UrlImportException('链接格式不正确');
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw UrlImportException('只支持 http 或 https 链接');
  }
  final host = uri.host.toLowerCase();
  if (host == 'arxiv.org' || host.endsWith('.arxiv.org')) {
    final m = RegExp(r'^/abs/(.+?)/?$').firstMatch(uri.path);
    if (m != null) {
      return Uri(scheme: 'https', host: uri.host, path: '/pdf/${m.group(1)}');
    }
  }
  return uri;
}

/// Cancels a running [downloadPdf].
class DownloadCancelToken {
  var _cancelled = false;
  final _listeners = <void Function()>[];
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void _onCancel(void Function() l) => _listeners.add(l);
}

class DownloadedPdf {
  new(this.file, this.title, this.url, this.bytes);

  /// Complete PDF in the temporary folder; the caller moves or deletes it.
  final File file;

  /// From Content-Disposition, else the last part of the URL, without `.pdf`.
  final String title;

  /// The URL the PDF was downloaded from (after normalization).
  final Uri url;
  final int bytes;
}

/// Downloads [url] into [tempDir] and checks it really is a PDF.
///
/// On any failure or cancellation no file is left behind.
Future<DownloadedPdf> downloadPdf(
  Uri url, {
  required Directory tempDir,
  void Function(int received, int? total)? onProgress,
  DownloadCancelToken? cancel,
  int maxBytes = maxPdfDownloadBytes,
  HttpClient? client,
  Duration connectTimeout = const Duration(seconds: 20),
  Duration idleTimeout = const Duration(seconds: 30),
}) async {
  final http = client ?? httpClientFactory();
  http.connectionTimeout = connectTimeout;
  http.userAgent = 'mNote';
  await tempDir.create(recursive: true);
  final tmp = File(
    '${tempDir.path}/download-${DateTime.now().microsecondsSinceEpoch}.part',
  );
  IOSink? sink;
  StreamSubscription<List<int>>? sub;

  Future<void> cleanup() async {
    await sub?.cancel();
    try {
      await sink?.close();
    } catch (_) {}
    if (tmp.existsSync()) {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }

  try {
    if (cancel?.isCancelled ?? false) throw UrlImportCancelled();
    final HttpClientRequest req;
    try {
      req = await http.getUrl(url);
    } on SocketException catch (e) {
      throw UrlImportException(
        '无法连接到 ${url.host}：${e.osError?.message ?? e.message}',
      );
    } on HandshakeException {
      throw UrlImportException('与 ${url.host} 的安全连接失败');
    } on TimeoutException {
      throw UrlImportException('连接 ${url.host} 超时');
    }
    req.followRedirects = true;
    req.maxRedirects = 8;
    req.headers.set(HttpHeaders.acceptHeader, 'application/pdf,*/*;q=0.8');
    cancel?._onCancel(req.abort);
    final HttpClientResponse res;
    try {
      res = await req.close();
    } on SocketException catch (e) {
      if (cancel?.isCancelled ?? false) throw UrlImportCancelled();
      throw UrlImportException(
        '无法连接到 ${url.host}：${e.osError?.message ?? e.message}',
      );
    } on HttpException catch (e) {
      if (cancel?.isCancelled ?? false) throw UrlImportCancelled();
      throw UrlImportException('下载失败：${e.message}');
    }
    if (res.statusCode != HttpStatus.ok) {
      await res.drain<void>().catchError((_) {});
      throw UrlImportException(
        '服务器返回错误 ${res.statusCode}${res.reasonPhrase.isEmpty ? '' : '（${res.reasonPhrase}）'}',
      );
    }
    final total = res.contentLength >= 0 ? res.contentLength : null;
    if (total != null && total > maxBytes) {
      await res.drain<void>().catchError((_) {});
      throw UrlImportException('文件太大（${_mb(total)}），最多 ${_mb(maxBytes)}');
    }

    sink = tmp.openWrite();
    var received = 0;
    final head = BytesBuilder(copy: false);
    final done = Completer<void>();
    Timer? idle;
    void armIdle() {
      idle?.cancel();
      idle = Timer(idleTimeout, () {
        if (!done.isCompleted)
          done.completeError(UrlImportException('下载中断：长时间没有收到数据'));
      });
    }

    cancel?._onCancel(() {
      if (!done.isCompleted) done.completeError(UrlImportCancelled());
    });
    armIdle();
    sub = res.listen(
      (chunk) {
        received += chunk.length;
        if (received > maxBytes) {
          if (!done.isCompleted)
            done.completeError(UrlImportException('文件太大，最多 ${_mb(maxBytes)}'));
          return;
        }
        if (head.length < 1024)
          head.add(chunk.length > 1024 ? chunk.sublist(0, 1024) : chunk);
        sink!.add(chunk);
        onProgress?.call(received, total);
        armIdle();
      },
      onError: (Object e) {
        if (!done.isCompleted) {
          done.completeError(
            cancel?.isCancelled ?? false
                ? UrlImportCancelled()
                : UrlImportException('下载中断：$e'),
          );
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    try {
      await done.future;
    } finally {
      idle?.cancel();
    }
    await sink.flush();
    await sink.close();
    sink = null;

    // A PDF starts with "%PDF-" (the spec allows it anywhere in the first KB).
    final start = latin1.decode(head.takeBytes(), allowInvalid: true);
    if (!start.contains('%PDF-')) throw UrlImportException('这个链接不是 PDF');

    return DownloadedPdf(tmp, _title(res, url), url, received);
  } catch (e) {
    await cleanup();
    rethrow;
  } finally {
    if (client == null) http.close(force: true);
  }
}

String _mb(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';

/// Title from `Content-Disposition` (RFC 6266, incl. `filename*=UTF-8''…`),
/// else from the last path segment of [url].
String _title(HttpClientResponse res, Uri url) {
  String? name;
  final cd = res.headers.value('content-disposition');
  if (cd != null) {
    final star = RegExp(
      r"filename\*\s*=\s*([^']*)'[^']*'([^;]+)",
      caseSensitive: false,
    ).firstMatch(cd);
    final plain = RegExp(
      r'filename\s*=\s*"?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(cd);
    if (star != null) {
      try {
        name = Uri.decodeComponent(star.group(2)!.trim());
      } catch (_) {}
    }
    name ??= plain?.group(1)?.trim();
  }
  if (name == null || name.isEmpty) {
    final segs = url.pathSegments.where((s) => s.isNotEmpty);
    name = segs.isEmpty ? url.host : segs.last;
  }
  final t = name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '').trim();
  return t.isEmpty ? url.host : t;
}
