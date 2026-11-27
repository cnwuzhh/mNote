import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'package:saber/mnote/ai/ai_client.dart';
import 'package:saber/mnote/ai/ai_config.dart';
import 'package:saber/mnote/ai/ai_prompts.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// Where the AI config is kept. Tests replace it with an in-memory store.
var aiConfigStore = AiConfigStore();

/// In-memory store for tests.
class MemoryAiConfigStore implements AiConfigStore {
  new([this.config]);
  AiConfig? config;
  @override
  Future<AiConfig?> load() async => config;
  @override
  Future<void> save(AiConfig c) async => config = c;
  @override
  Future<void> clear() async => config = null;
}

/// 「AI 服务」 settings: import the config file, see the services (keys only
/// as the last 4 characters), test each one, and the marker-only switch.
class AiSettingsPage extends StatefulWidget {
  const new({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  AiConfig? config;
  var loading = true;
  final testResults = <String, String>{};
  final testing = <String>{};

  @override
  void initState() {
    super.initState();
    aiConfigStore.load().then(
      (c) => setState(() {
        config = c;
        loading = false;
      }),
    );
  }

  Future<void> _import() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = f?.path;
    if (path == null) return;
    try {
      final c = AiConfig.parse(await File(path).readAsString());
      c.markerOnly = config?.markerOnly ?? c.markerOnly;
      await aiConfigStore.save(c);
      setState(() {
        config = c;
        testResults.clear();
      });
      _snack('已导入 ${c.providers.length} 个 AI 服务');
    } on AiConfigException catch (e) {
      _snack('无法导入：${e.message}');
    } catch (e) {
      _snack('无法读取文件：$e');
    }
  }

  Future<void> _test(AiProvider p) async {
    setState(() {
      testing.add(p.id);
      testResults.remove(p.id);
    });
    final sw = Stopwatch()..start();
    String result;
    try {
      final single = AiConfig(
        providers: [p],
        defaultId: p.id,
        tasks: {
          taskTranslate: config!.tasks[taskTranslate]?.providerId == p.id
              ? config!.tasks[taskTranslate]!
              : AiTaskRoute(p.id),
        },
      );
      final r = await const AiClient().run(
        single,
        taskTranslate,
        translateMessages(
          'Reading right, acting wrong.',
          targetLanguage: config!.targetLanguage,
        ),
      );
      result =
          '可用 · ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒 ·「${r.text.length > 24 ? '${r.text.substring(0, 24)}…' : r.text}」';
    } catch (e) {
      result = '不可用：$e';
    }
    if (!mounted) return;
    setState(() {
      testing.remove(p.id);
      testResults[p.id] = result;
    });
  }

  Future<void> _setMarkerOnly(bool v) async {
    final c = config;
    if (c == null) return;
    setState(() => c.markerOnly = v);
    await aiConfigStore.save(c);
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除 AI 配置？'),
        content: const Text('会删除本机保存的 AI 服务和 API Key。已经生成的翻译和解释不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await aiConfigStore.clear();
    setState(() => config = null);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return MnoteThemed(
      child: Builder(
        builder: (context) {
          final p = MnotePalette.of(context);
          final c = config;
          return Scaffold(
            backgroundColor: p.board,
            appBar: AppBar(
              backgroundColor: p.paper,
              title: const Text('AI 服务'),
            ),
            body: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        '翻译、解释会把选中的文字（以及解释时的上下文）发送给下面的 AI 服务。API Key 保存在本机的系统加密存储里，不会写入学习集数据，也不会出现在导出的文件中。',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: p.ink2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('ai-import'),
                            style: FilledButton.styleFrom(
                              backgroundColor: p.accent,
                            ),
                            onPressed: _import,
                            icon: const Icon(Icons.file_open_outlined),
                            label: Text(c == null ? '导入配置文件' : '重新导入配置文件'),
                          ),
                          const SizedBox(width: 12),
                          if (c != null)
                            TextButton(
                              key: const ValueKey('ai-clear'),
                              onPressed: _clear,
                              child: const Text('清除配置'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (c == null)
                        Text(
                          '还没有配置 AI 服务。导入一个配置文件（ai_providers.json）后即可使用翻译和解释。',
                          style: TextStyle(fontSize: 14, color: p.ink3),
                        )
                      else ...[
                        for (final pr in c.providers)
                          Card(
                            key: ValueKey('ai-provider-${pr.id}'),
                            color: p.paper,
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          pr.name,
                                          style: serifStyle(
                                            p.ink,
                                            size: 16,
                                            weight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (pr.id == c.defaultId)
                                        _Badge('默认', p.accent),
                                      if (pr.id == c.fallbackId)
                                        _Badge('备用', p.ink3),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '模型 ${pr.model} · ${Uri.parse(pr.baseUrl).host} · Key ${pr.maskedKey}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: p.ink3,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      OutlinedButton(
                                        key: ValueKey('ai-test-${pr.id}'),
                                        onPressed: testing.contains(pr.id)
                                            ? null
                                            : () => _test(pr),
                                        child: Text(
                                          testing.contains(pr.id)
                                              ? '测试中…'
                                              : '测试连接',
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      if (testResults[pr.id] != null)
                                        Expanded(
                                          child: Text(
                                            testResults[pr.id]!,
                                            key: ValueKey(
                                              'ai-test-result-${pr.id}',
                                            ),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: p.ink2,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          key: const ValueKey('ai-marker-only'),
                          tileColor: p.paper,
                          title: const Text('翻译后只显示标记（不自动展开）'),
                          subtitle: const Text('适合连续翻译几句时使用；点句子旁的「译」标记查看结果'),
                          value: c.markerOnly,
                          onChanged: _setMarkerOnly,
                        ),
                      ],
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const new(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: TextStyle(fontSize: 12, color: color)),
  );
}
