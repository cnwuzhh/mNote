import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:saber/mnote/ai/ai_config.dart';

class AiException implements Exception {
  new(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiCancelled implements Exception {
  @override
  String toString() => '已取消';
}

class AiCancelToken {
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
}

class AiResult {
  new(this.text, this.provider);
  final String text;
  final AiProvider provider;
}

/// Creates HTTP clients; tests use a real client inside flutter_test.
@visibleForTesting
HttpClient Function() aiHttpClientFactory = () =>
    HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;

/// OpenAI-compatible chat completions with streaming (SSE).
class AiClient {
  const new();

  /// Streams the answer of [p] to [messages]. Reasoning ("thinking") deltas
  /// are ignored; only the answer text is yielded.
  Stream<String> stream(
    AiProvider p,
    List<Map<String, String>> messages, {
    Map<String, dynamic> extraBody = const {},
    AiCancelToken? cancel,
  }) async* {
    final http = aiHttpClientFactory();
    http.connectionTimeout = const Duration(seconds: 15);
    final uri = Uri.parse('${p.baseUrl}/chat/completions');
    try {
      final HttpClientRequest req;
      try {
        req = await http.postUrl(uri);
      } on SocketException catch (e) {
        throw AiException(
          '无法连接 ${uri.host}：${e.osError?.message ?? e.message}',
        );
      } on TimeoutException {
        throw AiException('连接 ${uri.host} 超时');
      }
      cancel?._listeners.add(req.abort);
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${p.apiKey}')
        ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
        ..set(HttpHeaders.acceptHeader, 'text/event-stream');
      req.add(
        utf8.encode(
          jsonEncode({
            'model': p.model,
            'messages': messages,
            'temperature': p.temperature,
            'max_tokens': p.maxTokens,
            'stream': true,
            ...extraBody,
          }),
        ),
      );
      final HttpClientResponse res;
      try {
        res = await req.close().timeout(Duration(seconds: p.timeoutSeconds));
      } on TimeoutException {
        throw AiException('${p.name} 响应超时');
      } on SocketException catch (e) {
        if (cancel?.isCancelled ?? false) throw AiCancelled();
        throw AiException('连接中断：${e.message}');
      } on HttpException catch (e) {
        if (cancel?.isCancelled ?? false) throw AiCancelled();
        throw AiException('请求失败：${e.message}');
      }
      if (res.statusCode != 200) {
        final body = await utf8.decodeStream(res).catchError((_) => '');
        String detail = body;
        try {
          final e = (jsonDecode(body) as Map)['error'];
          detail = e is Map ? '${e['message'] ?? e['code'] ?? body}' : '$e';
        } catch (_) {}
        if (res.statusCode == 401 || res.statusCode == 403) {
          throw AiException('${p.name}：API Key 无效或没有权限（${res.statusCode}）');
        }
        throw AiException(
          '${p.name} 返回错误 ${res.statusCode}：${detail.length > 120 ? '${detail.substring(0, 120)}…' : detail}',
        );
      }
      final lines = res
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(
            Duration(seconds: p.timeoutSeconds),
            onTimeout: (sink) =>
                sink.addError(AiException('${p.name} 长时间没有返回内容')),
          );
      await for (final line in lines) {
        if (cancel?.isCancelled ?? false) throw AiCancelled();
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') break;
        if (data.isEmpty) continue;
        final Map<String, dynamic> j;
        try {
          j = (jsonDecode(data) as Map).cast<String, dynamic>();
        } catch (_) {
          continue;
        }
        final choices = j['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final delta = (choices.first as Map)['delta'];
        final content = delta is Map ? delta['content'] : null;
        if (content is String && content.isNotEmpty) yield content;
      }
    } on AiException {
      rethrow;
    } on AiCancelled {
      rethrow;
    } catch (e) {
      if (cancel?.isCancelled ?? false) throw AiCancelled();
      throw AiException('请求失败：$e');
    } finally {
      http.close(force: true);
    }
  }

  /// Runs [task] with [config]'s route: the task's provider first, then the
  /// fallback when the first fails or returns an empty answer.
  /// [onDelta] receives the text so far (for streaming display).
  Future<AiResult> run(
    AiConfig config,
    String task,
    List<Map<String, String>> messages, {
    void Function(String textSoFar, AiProvider provider)? onDelta,
    AiCancelToken? cancel,
  }) async {
    final routes = config.routeFor(task);
    if (routes.isEmpty) throw AiException('没有可用的 AI 服务');
    final errors = <String>[];
    for (final (p, extra) in routes) {
      final buf = StringBuffer();
      try {
        await for (final d in stream(
          p,
          messages,
          extraBody: extra,
          cancel: cancel,
        )) {
          buf.write(d);
          onDelta?.call(buf.toString(), p);
        }
        final text = buf.toString().trim();
        if (text.isNotEmpty) return AiResult(text, p);
        errors.add('${p.name} 返回了空结果');
      } on AiCancelled {
        rethrow;
      } on AiException catch (e) {
        errors.add(e.message);
      }
    }
    throw AiException(errors.join('；'));
  }
}
