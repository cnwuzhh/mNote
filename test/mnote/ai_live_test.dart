import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/mnote/ai/ai_client.dart';
import 'package:saber/mnote/ai/ai_config.dart';
import 'package:saber/mnote/ai/ai_prompts.dart';

/// Calls the real AI services with the private config (never in the repo):
///   MNOTE_AI_CONFIG=~/mnote-secrets/ai_providers.json https_proxy=… flutter test test/mnote/ai_live_test.dart
/// Skipped when MNOTE_AI_CONFIG is not set.
void main() {
  final path = Platform.environment['MNOTE_AI_CONFIG'];
  final skip = path == null || !File(path).existsSync()
      ? 'set MNOTE_AI_CONFIG to run against the real services'
      : false;
  const sentence =
      'Across seventeen fast systems and a reasoning model, the answer is consistent: most wrong actions follow correct reading, and the more accurate a system, the more of its errors take this form.';

  test(
    'every configured service translates and explains',
    () async {
      final cfg = AiConfig.parse(File(path!).readAsStringSync());
      for (final p in cfg.providers) {
        // Route each task to this provider only (no fallback), with the task's extra body.
        for (final task in [taskTranslate, taskExplain]) {
          final single = AiConfig(
            providers: [p],
            defaultId: p.id,
            tasks: {
              task: AiTaskRoute(
                p.id,
                cfg.tasks[task]?.providerId == p.id
                    ? cfg.tasks[task]!.extraBody
                    : const {},
              ),
            },
          );
          final msgs = task == taskTranslate
              ? translateMessages(sentence, targetLanguage: cfg.targetLanguage)
              : explainMessages(
                  sentence,
                  targetLanguage: cfg.targetLanguage,
                  docTitle: 'arxiv-2610.18579v1',
                  page: 1,
                );
          final sw = Stopwatch()..start();
          Duration? first;
          final r = await const AiClient().run(
            single,
            task,
            msgs,
            onDelta: (_, _) => first ??= sw.elapsed,
          );
          // ignore: avoid_print
          print(
            '${p.id} $task: first ${first?.inMilliseconds} ms, total ${sw.elapsedMilliseconds} ms — ${r.text.replaceAll('\n', ' ')}',
          );
          expect(r.text, isNotEmpty);
          expect(
            RegExp(r'[\u4e00-\u9fff]').hasMatch(r.text),
            isTrue,
            reason: 'answer is in Chinese',
          );
        }
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
