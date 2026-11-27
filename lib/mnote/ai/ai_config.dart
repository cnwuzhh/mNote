import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One OpenAI-compatible chat service.
class AiProvider {
  new({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.timeoutSeconds = 60,
    this.temperature = 0.3,
    this.maxTokens = 2048,
  });

  final String id, name, baseUrl, apiKey, model;
  final int timeoutSeconds, maxTokens;
  final double temperature;

  /// "…dLHZ": never show a whole key in the UI.
  String get maskedKey => apiKey.length <= 4
      ? '••••'
      : '••••${apiKey.substring(apiKey.length - 4)}';

  factory fromJson(Map<String, dynamic> j) {
    String req(String k) {
      final v = j[k];
      if (v is! String || v.trim().isEmpty)
        throw AiConfigException('服务「${j['id'] ?? '?'}」缺少 $k');
      return v.trim();
    }

    final type = j['type'] as String? ?? 'openai-compatible';
    if (type != 'openai-compatible') throw AiConfigException('不支持的服务类型：$type');
    final base = req('baseUrl');
    final uri = Uri.tryParse(base);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      throw AiConfigException('服务「${j['id']}」的 baseUrl 不是有效的网址');
    }
    return AiProvider(
      id: req('id'),
      name: (j['name'] as String?)?.trim().isNotEmpty == true
          ? (j['name'] as String).trim()
          : req('id'),
      baseUrl: base.replaceAll(RegExp(r'/+$'), ''),
      apiKey: req('apiKey'),
      model: req('model'),
      timeoutSeconds: (j['timeoutSeconds'] as num?)?.toInt() ?? 60,
      temperature: (j['temperature'] as num?)?.toDouble() ?? 0.3,
      maxTokens: (j['maxTokens'] as num?)?.toInt() ?? 2048,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': 'openai-compatible',
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'timeoutSeconds': timeoutSeconds,
    'temperature': temperature,
    'maxTokens': maxTokens,
  };
}

/// What to use for one task (translate / explain / summary): a provider and
/// optional extra request fields (e.g. `{"reasoning_effort": "minimal"}`).
class AiTaskRoute {
  new(this.providerId, [this.extraBody = const {}]);
  final String providerId;
  final Map<String, dynamic> extraBody;

  factory fromJson(Object? v) {
    if (v is String) return AiTaskRoute(v);
    if (v is Map) {
      final p = v['provider'];
      if (p is! String) throw AiConfigException('tasks 里的条目缺少 provider');
      return AiTaskRoute(
        p,
        (v['extraBody'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
    }
    throw AiConfigException('tasks 里的条目格式不对');
  }

  Object toJson() => extraBody.isEmpty
      ? providerId
      : {'provider': providerId, 'extraBody': extraBody};
}

class AiConfigException implements Exception {
  new(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The whole AI setup: same format as `ai_providers.template.json`.
class AiConfig {
  new({
    required this.providers,
    required this.defaultId,
    this.fallbackId,
    this.tasks = const {},
    this.targetLanguage = 'zh-CN',
    this.markerOnly = false,
  });

  final List<AiProvider> providers;
  final String defaultId;
  final String? fallbackId;
  final Map<String, AiTaskRoute> tasks;
  final String targetLanguage;

  /// 「翻译后只显示标记（不自动展开）」.
  bool markerOnly;

  AiProvider? provider(String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Providers to try for [task], in order: the task's (or default) provider,
  /// then the fallback. Each with the extra body for that task.
  List<(AiProvider, Map<String, dynamic>)> routeFor(String task) {
    final r = tasks[task] ?? AiTaskRoute(defaultId);
    final out = <(AiProvider, Map<String, dynamic>)>[];
    final first = provider(r.providerId) ?? provider(defaultId);
    if (first != null) out.add((first, r.extraBody));
    final fb = fallbackId == null ? null : provider(fallbackId!);
    if (fb != null && fb.id != first?.id) out.add((fb, const {}));
    return out;
  }

  factory parse(String text) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException catch (e) {
      throw AiConfigException('不是有效的 JSON：${e.message}');
    }
    if (raw is! Map) throw AiConfigException('配置文件最外层应是一个对象');
    final j = raw.cast<String, dynamic>();
    final ps = [
      for (final p in (j['providers'] as List? ?? const []))
        AiProvider.fromJson((p as Map).cast<String, dynamic>()),
    ];
    if (ps.isEmpty) throw AiConfigException('配置里没有任何服务（providers 为空）');
    final ids = <String>{};
    for (final p in ps) {
      if (!ids.add(p.id)) throw AiConfigException('服务 id 重复：${p.id}');
    }
    final def = j['default'] as String? ?? ps.first.id;
    if (!ids.contains(def)) throw AiConfigException('default 指向不存在的服务：$def');
    final fb = j['fallback'] as String?;
    if (fb != null && !ids.contains(fb))
      throw AiConfigException('fallback 指向不存在的服务：$fb');
    final tasks = <String, AiTaskRoute>{};
    for (final e in ((j['tasks'] as Map?) ?? const {}).entries) {
      final r = AiTaskRoute.fromJson(e.value);
      if (!ids.contains(r.providerId))
        throw AiConfigException('tasks.${e.key} 指向不存在的服务：${r.providerId}');
      tasks['${e.key}'] = r;
    }
    return AiConfig(
      providers: ps,
      defaultId: def,
      fallbackId: fb,
      tasks: tasks,
      targetLanguage:
          ((j['translation'] as Map?)?['targetLanguage'] as String?) ?? 'zh-CN',
      markerOnly: (j['markerOnly'] as bool?) ?? false,
    );
  }

  String encode() => jsonEncode({
    'version': 1,
    'default': defaultId,
    if (fallbackId != null) 'fallback': fallbackId,
    'providers': [for (final p in providers) p.toJson()],
    'tasks': {for (final e in tasks.entries) e.key: e.value.toJson()},
    'translation': {'targetLanguage': targetLanguage},
    'markerOnly': markerOnly,
  });
}

/// Keeps the AI config (with API keys) in the platform's encrypted storage
/// (Android Keystore-backed), never in plain files or the study set data.
class AiConfigStore {
  new({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'mnote.ai.config.v1';
  final FlutterSecureStorage _storage;

  /// Null when nothing is configured or the encrypted storage is unavailable
  /// (then AI features ask the user to import a config instead of failing).
  Future<AiConfig?> load() async {
    final String? s;
    try {
      s = await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
    if (s == null || s.isEmpty) return null;
    try {
      return AiConfig.parse(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(AiConfig c) => _storage.write(key: _key, value: c.encode());

  Future<void> clear() => _storage.delete(key: _key);
}
