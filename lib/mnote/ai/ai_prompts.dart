/// Prompts for the reading-phase AI tasks. Keep them short: they run on every
/// selection, and the answer is shown next to the text.
library;

const taskTranslate = 'translate';
const taskExplain = 'explain';

String _lang(String code) => switch (code) {
  'zh-CN' || 'zh-Hans' || 'zh' => '简体中文',
  'zh-TW' || 'zh-Hant' => '繁體中文',
  'en' || 'en-US' => 'English',
  'ja' => '日本語',
  _ => code,
};

/// Translate [text] (from page [page] of [docTitle]) into [targetLanguage].
List<Map<String, String>> translateMessages(
  String text, {
  required String targetLanguage,
  String? docTitle,
  int? page,
}) => [
  {
    'role': 'system',
    'content':
        '你是学术论文翻译。把用户给出的原文准确、通顺地译成${_lang(targetLanguage)}。'
        '保留术语、符号、数字和引用标记（如 §5.1、[12]）原样；专有名词首次出现可在译文后用括号保留原文。'
        '只输出译文，不要解释，不要加引号。',
  },
  {'role': 'user', 'content': text},
];

/// Explain [text] using only the given context.
List<Map<String, String>> explainMessages(
  String text, {
  required String targetLanguage,
  String? docTitle,
  int? page,
  String? context,
}) => [
  {
    'role': 'system',
    'content':
        '你是论文阅读助手。用${_lang(targetLanguage)}、不超过 150 字，解释用户选中的句子是什么意思、在论文里起什么作用。'
        '只依据给出的原文和上下文，不要编造原文中没有的数据或结论；提到原文位置时写成「p.页码」。'
        '直接给出解释，不要复述原句。',
  },
  {
    'role': 'user',
    'content': [
      if (docTitle != null) '文档：$docTitle',
      if (page != null) '页码：p.$page',
      if (context != null && context.isNotEmpty) '上下文：$context',
      '选中的句子：$text',
    ].join('\n'),
  },
];
