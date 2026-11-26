/// Text clean-up for excerpts taken from PDF text layers.
///
/// PDF text comes with hard line breaks at the end of every printed line and
/// words split across lines with a hyphen ("ac-\ntion"). An excerpt card should
/// read as one continuous passage, so:
/// * a line ending in `-` followed by a lowercase letter is joined without the
///   hyphen ("ac-" + "tion" -> "action");
/// * other line breaks become a single space between Latin text and nothing
///   between CJK characters;
/// * runs of whitespace collapse to one space.
/// Other punctuation (en dashes in "73–85%", "§5.1", ligatures) is preserved.
library;

final _cjk = RegExp(
  r'[\u2E80-\u2FFF\u3000-\u303F\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]',
);

bool _isCjk(String ch) => ch.isNotEmpty && _cjk.hasMatch(ch);

String cleanExcerptText(String raw) {
  // Normalise line endings and soft hyphens.
  var s = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // PDFium marks a line-end hyphenation point with U+0002 (sometimes
  // followed by a line break); soft hyphens (U+00AD) mean the same.
  s = s.replaceAll(RegExp('[\u0002\u00AD]\n?'), '');

  final lines = s.split('\n');
  final out = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trimRight();
    if (i == 0) {
      out.write(line.trimLeft());
      continue;
    }
    final next = line.trimLeft();
    if (next.isEmpty) continue;
    final soFar = out.toString();
    if (soFar.isEmpty) {
      out.write(next);
      continue;
    }
    final last = soFar[soFar.length - 1];
    final first = next[0];
    if (last == '-' &&
        soFar.length >= 2 &&
        RegExp(r'[A-Za-z]').hasMatch(soFar[soFar.length - 2]) &&
        RegExp(r'[a-z]').hasMatch(first)) {
      // De-hyphenate a word split across lines.
      final trimmed = soFar.substring(0, soFar.length - 1);
      out
        ..clear()
        ..write(trimmed)
        ..write(next);
    } else if (last == '-' || last == '/') {
      // Compound word broken at its own hyphen ("Self-" + "Attention"): keep it.
      out.write(next);
    } else if (_isCjk(last) && _isCjk(first)) {
      out.write(next);
    } else if (last == ' ') {
      out.write(next);
    } else {
      out
        ..write(' ')
        ..write(next);
    }
  }
  return out.toString().replaceAll(RegExp(r'[ \t\u00A0]+'), ' ').trim();
}

/// A short default card title derived from the excerpt text:
/// up to [maxCjk] characters for Chinese/Japanese text, otherwise up to
/// [maxWords] words, cut at the first sentence end if that comes earlier.
String defaultCardTitle(String text, {int maxCjk = 16, int maxWords = 6}) {
  final t = text.trim();
  if (t.isEmpty) return '摘录';
  final sentenceEnd = RegExp(r'[。！？；.!?;:：]');
  final m = sentenceEnd.firstMatch(t);
  final firstSentence = m == null ? t : t.substring(0, m.start);

  final cjkCount = _cjk.allMatches(firstSentence).length;
  if (cjkCount * 2 >= firstSentence.length) {
    final chars = firstSentence.characters();
    return chars.length <= maxCjk
        ? firstSentence
        : '${chars.take(maxCjk).join()}…';
  }
  final words = firstSentence.split(RegExp(r'\s+'));
  return words.length <= maxWords
      ? firstSentence
      : '${words.take(maxWords).join(' ')}…';
}

extension on String {
  /// Splits into user-perceived characters well enough for CJK titles
  /// (surrogate pairs kept together).
  List<String> characters() => runes.map(String.fromCharCode).toList();
}
