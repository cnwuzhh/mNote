import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/mnote/ai/ai_client.dart';
import 'package:saber/mnote/ai/ai_config.dart';
import 'package:saber/mnote/ai/ai_prompts.dart';
import 'package:saber/mnote/model/models.dart';

String _cfg(String base, {String? fallbackBase}) => jsonEncode({
  'version': 1,
  'default': 'a',
  if (fallbackBase != null) 'fallback': 'b',
  'providers': [
    {
      'id': 'a',
      'name': 'Service A',
      'type': 'openai-compatible',
      'baseUrl': base,
      'apiKey': 'sk-secret-AAAA',
      'model': 'm-a',
    },
    if (fallbackBase != null)
      {
        'id': 'b',
        'name': 'Service B',
        'type': 'openai-compatible',
        'baseUrl': fallbackBase,
        'apiKey': 'sk-secret-BBBB',
        'model': 'm-b',
      },
  ],
  'tasks': {
    'translate': {
      'provider': 'a',
      'extraBody': {'reasoning_effort': 'minimal'},
    },
    'explain': 'a',
  },
  'translation': {'targetLanguage': 'zh-CN'},
});

void main() {
  group('AiConfig', () {
    test('parses the template format, masks keys, routes tasks', () {
      final c = AiConfig.parse(
        _cfg('https://x.example/v1', fallbackBase: 'https://y.example/v3/'),
      );
      expect(c.providers.map((p) => p.id), ['a', 'b']);
      expect(c.provider('a')!.maskedKey, '••••AAAA');
      expect(
        c.provider('b')!.baseUrl,
        'https://y.example/v3',
        reason: 'trailing slash removed',
      );
      final r = c.routeFor('translate');
      expect(r.map((e) => e.$1.id), ['a', 'b']);
      expect(r.first.$2, {'reasoning_effort': 'minimal'});
      expect(
        c.routeFor('summary').first.$1.id,
        'a',
        reason: 'unknown task uses default',
      );
      // round trip through encode() (what is kept in secure storage)
      final back = AiConfig.parse(c.encode());
      expect(back.routeFor('translate').first.$2, {
        'reasoning_effort': 'minimal',
      });
      expect(back.provider('b')!.apiKey, 'sk-secret-BBBB');
    });

    test('rejects broken configs with a readable message', () {
      void bad(String json, String expected) => expect(
        () => AiConfig.parse(json),
        throwsA(
          isA<AiConfigException>().having(
            (e) => e.message,
            'm',
            contains(expected),
          ),
        ),
      );
      bad('{', 'JSON');
      bad('{"providers": []}', 'providers');
      bad(
        '{"providers":[{"id":"a","baseUrl":"https://x","model":"m"}]}',
        'apiKey',
      );
      bad(
        '{"providers":[{"id":"a","baseUrl":"ftp://x","apiKey":"k","model":"m"}]}',
        'baseUrl',
      );
      bad(
        '{"default":"z","providers":[{"id":"a","baseUrl":"https://x","apiKey":"k","model":"m"}]}',
        'default',
      );
      bad(
        '{"tasks":{"translate":"z"},"providers":[{"id":"a","baseUrl":"https://x","apiKey":"k","model":"m"}]}',
        'tasks.translate',
      );
    });
  });

  group('AiClient (fake OpenAI-compatible server)', () {
    late HttpServer server;
    late String base;
    final requests = <Map<String, dynamic>>[];

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        final body =
            jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        requests.add({
          ...body,
          '_path': req.uri.path,
          '_auth': req.headers.value('authorization'),
        });
        final r = req.response;
        r.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        void sse(Map<String, dynamic> delta) => r.write(
          'data: ${jsonEncode({
            'choices': [
              {'delta': delta},
            ],
          })}\n\n',
        );
        switch (req.uri.path) {
          case '/ok/chat/completions':
            sse({'reasoning_content': 'thinking about it…'});
            for (final part in ['在十七个', '快速系统中，', '结论一致。']) {
              sse({'content': part});
            }
            r.write('data: [DONE]\n\n');
          case '/empty/chat/completions':
            sse({'reasoning_content': 'only thinking, no answer'});
            r.write('data: [DONE]\n\n');
          case '/unauth/chat/completions':
            r.statusCode = 401;
            r.write(
              jsonEncode({
                'error': {'message': 'bad key'},
              }),
            );
          case '/notfound/chat/completions':
            r.statusCode = 404;
            r.write(
              jsonEncode({
                'error': {
                  'code': 'InvalidEndpointOrModel.NotFound',
                  'message': 'The model does not exist',
                },
              }),
            );
        }
        await r.close();
      });
    });
    tearDownAll(() => server.close(force: true));
    setUp(requests.clear);

    test(
      'streams the answer, ignores reasoning text, sends key and extra body',
      () async {
        final c = AiConfig.parse(_cfg('$base/ok'));
        final seen = <String>[];
        final r = await const AiClient().run(
          c,
          taskTranslate,
          translateMessages('x', targetLanguage: 'zh-CN'),
          onDelta: (t, _) => seen.add(t),
        );
        expect(r.text, '在十七个快速系统中，结论一致。');
        expect(r.provider.id, 'a');
        expect(seen, [
          '在十七个',
          '在十七个快速系统中，',
          '在十七个快速系统中，结论一致。',
        ], reason: 'incremental');
        expect(requests.single['_auth'], 'Bearer sk-secret-AAAA');
        expect(requests.single['model'], 'm-a');
        expect(requests.single['stream'], isTrue);
        expect(requests.single['reasoning_effort'], 'minimal');
      },
    );

    test('an empty answer falls back to the backup service', () async {
      final c = AiConfig.parse(_cfg('$base/empty', fallbackBase: '$base/ok'));
      final r = await const AiClient().run(
        c,
        taskExplain,
        explainMessages('x', targetLanguage: 'zh-CN'),
      );
      expect(r.provider.id, 'b');
      expect(requests.map((e) => e['_path']), [
        '/empty/chat/completions',
        '/ok/chat/completions',
      ]);
    });

    test(
      'errors fall back too; when all fail the message names the cause',
      () async {
        final c1 = AiConfig.parse(
          _cfg('$base/notfound', fallbackBase: '$base/ok'),
        );
        expect(
          (await const AiClient().run(c1, taskTranslate, [])).provider.id,
          'b',
        );

        final c2 = AiConfig.parse(
          _cfg('$base/unauth', fallbackBase: '$base/notfound'),
        );
        await expectLater(
          const AiClient().run(c2, taskTranslate, []),
          throwsA(
            isA<AiException>().having(
              (e) => e.message,
              'm',
              allOf(
                contains('API Key 无效'),
                contains('404'),
                contains('does not exist'),
              ),
            ),
          ),
        );
      },
    );

    test('an unreachable service is reported', () async {
      final c = AiConfig.parse(_cfg('http://127.0.0.1:1/v1'));
      await expectLater(
        const AiClient().run(c, taskTranslate, []),
        throwsA(
          isA<AiException>().having((e) => e.message, 'm', contains('无法连接')),
        ),
      );
    });
  });

  test('AI notes and the per-set switch survive JSON round trip', () {
    final set = StudySet(
      id: 's',
      name: 'S',
      aiDisabled: true,
      aiNotes: [
        AiNote(
          id: 'n',
          docId: 'd',
          kind: AiNote.explain,
          rects: const [PageRect(1, 1, 9, 5, 2)],
          source: 'src',
          result: '解释',
          providerName: 'A',
        ),
      ],
    );
    final back = StudySet.fromJson(
      jsonDecode(set.encode()) as Map<String, dynamic>,
    );
    expect(back.aiDisabled, isTrue);
    final n = back.aiNotes.single;
    expect(
      [n.kind, n.source, n.result, n.providerName, n.rects.single.page],
      [AiNote.explain, 'src', '解释', 'A', 1],
    );
    expect(StudySet.fromJson({'id': 'x'}).aiNotes, isEmpty);
  });
}
