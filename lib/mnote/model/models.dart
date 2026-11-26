import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Color;

import 'package:logging/logging.dart';

/// The four excerpt colours. Each colour carries a meaning, and the same
/// colour is used for the PDF highlight and for the card in the mind map.
enum ExcerptColor {
  // Values match design-demos/final.html (--y/--yd etc., light and dark).
  definition(
    '定义',
    Color(0x6BECC440),
    Color(0xFFC9A227),
    Color(0x57E8BE46),
    Color(0xFFE2BC4A),
  ),
  evidence(
    '实验证据',
    Color(0x5768A0D2),
    Color(0xFF4F86BD),
    Color(0x5C6EA0DC),
    Color(0xFF7FAEE0),
  ),
  application(
    '应用',
    Color(0x5C7AB268),
    Color(0xFF5E9A4B),
    Color(0x5782BE6E),
    Color(0xFF8FC27A),
  ),
  pitfall(
    '易错',
    Color(0x52DE6A54),
    Color(0xFFC25A45),
    Color(0x5CE66E5A),
    Color(0xFFE8826C),
  );

  new(
    this.label,
    this._highlightLight,
    this._inkLight,
    this._highlightDark,
    this._inkDark,
  );

  final String label;
  final Color _highlightLight, _inkLight, _highlightDark, _inkDark;

  /// Translucent fill painted behind the PDF text.
  Color highlight({bool dark = false}) =>
      dark ? _highlightDark : _highlightLight;

  /// Saturated version used for dots, card borders and mind-map lines.
  Color ink({bool dark = false}) => dark ? _inkDark : _inkLight;

  static ExcerptColor byName(String? name) => ExcerptColor.values.firstWhere(
    (c) => c.name == name,
    orElse: () => ExcerptColor.definition,
  );
}

/// A rectangle on a PDF page in PDF user-space points
/// (origin bottom-left, so [top] > [bottom]).
class PageRect {
  const new(this.page, this.left, this.top, this.right, this.bottom);

  final int page;
  final double left, top, right, bottom;

  Map<String, dynamic> toJson() => {
    'p': page,
    'l': left,
    't': top,
    'r': right,
    'b': bottom,
  };

  factory fromJson(Map<String, dynamic> j) => PageRect(
    (j['p'] as num).toInt(),
    (j['l'] as num).toDouble(),
    (j['t'] as num).toDouble(),
    (j['r'] as num).toDouble(),
    (j['b'] as num).toDouble(),
  );
}

/// An excerpt card. When [highlightOnly] is true it is just a highlight in the
/// PDF and does not appear in the margin rail or in the mind map.
class MCard {
  new({
    required this.id,
    required this.docId,
    required this.title,
    required this.text,
    required this.color,
    required this.rects,
    this.highlightOnly = false,
    this.parentId,
    this.order = 0,
    this.note = '',
    this.image,
    List<String>? tags,
    DateTime? createdAt,
  }) : tags = tags ?? [],
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String docId;
  String title;
  String text;
  ExcerptColor color;
  final List<PageRect> rects;
  bool highlightOnly;

  /// Parent card id in the mind map; null means a child of the root.
  String? parentId;
  int order;
  String note;

  /// File name (inside the set's `images/` folder) of a region capture made
  /// with the box-select tool; null for text excerpts.
  String? image;
  final List<String> tags;
  final DateTime createdAt;

  int get page => rects.isEmpty ? 1 : rects.map((r) => r.page).reduce(min);
  int get lastPage =>
      rects.isEmpty ? page : rects.map((r) => r.page).reduce(max);

  /// "p.2" or "p.2–3".
  String get pageLabel => page == lastPage ? 'p.$page' : 'p.$page–$lastPage';

  Map<String, dynamic> toJson() => {
    'id': id,
    'docId': docId,
    'title': title,
    'text': text,
    'color': color.name,
    'rects': rects.map((r) => r.toJson()).toList(),
    'highlightOnly': highlightOnly,
    'parentId': parentId,
    'order': order,
    'note': note,
    'image': image,
    'tags': tags,
    'createdAt': createdAt.toIso8601String(),
  };

  factory fromJson(Map<String, dynamic> j) => MCard(
    id: j['id'] as String,
    docId: j['docId'] as String,
    title: j['title'] as String? ?? '',
    text: j['text'] as String? ?? '',
    color: ExcerptColor.byName(j['color'] as String?),
    rects: [
      for (final r in (j['rects'] as List? ?? const []))
        PageRect.fromJson((r as Map).cast<String, dynamic>()),
    ],
    highlightOnly: j['highlightOnly'] as bool? ?? false,
    parentId: j['parentId'] as String?,
    order: _int(j['order'], 0),
    note: j['note'] as String? ?? '',
    image: j['image'] as String?,
    tags: [
      for (final t in (j['tags'] as List? ?? const []))
        if (t is String) t,
    ],
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
  );
}

class StudyDoc {
  new({
    required this.id,
    required this.title,
    required this.fileName,
    this.pageCount = 0,
    this.lastPage = 1,
    this.maxPageRead = 1,
    DateTime? lastOpened,
  }) : lastOpened = lastOpened ?? DateTime.now();

  final String id;
  String title;
  final String fileName;
  int pageCount;
  int lastPage;
  int maxPageRead;
  DateTime lastOpened;

  double get progress =>
      pageCount == 0 ? 0 : (maxPageRead / pageCount).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'fileName': fileName,
    'pageCount': pageCount,
    'lastPage': lastPage,
    'maxPageRead': maxPageRead,
    'lastOpened': lastOpened.toIso8601String(),
  };

  factory fromJson(Map<String, dynamic> j) => StudyDoc(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    fileName: j['fileName'] as String,
    pageCount: _int(j['pageCount'], 0),
    lastPage: _int(j['lastPage'], 1),
    maxPageRead: _int(j['maxPageRead'], 1),
    lastOpened: DateTime.tryParse(j['lastOpened'] as String? ?? ''),
  );
}

/// A study set: a few documents plus one mind map made of their cards.
class StudySet {
  new({
    required this.id,
    required this.name,
    List<StudyDoc>? docs,
    List<MCard>? cards,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.formatVersion = StudySet.currentFormatVersion,
  }) : docs = docs ?? [],
       cards = cards ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String name;
  final List<StudyDoc> docs;
  final List<MCard> cards;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Version of the set.json format this app writes.
  static const currentFormatVersion = 1;

  /// Format version the set was loaded from. A set written by a newer mNote
  /// may contain data this version does not know about, so it is never
  /// written back (see StudyStore.saveNow).
  final int formatVersion;

  /// Cards that appear in the margin rail and mind map.
  Iterable<MCard> get mapCards => cards.where((c) => !c.highlightOnly);

  /// Children of [parentId] (null = root) sorted by [MCard.order].
  List<MCard> childrenOf(String? parentId) =>
      mapCards.where((c) => c.parentId == parentId).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  MCard? cardById(String id) {
    for (final c in cards) {
      if (c.id == id) return c;
    }
    return null;
  }

  StudyDoc? docById(String id) {
    for (final d in docs) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Whether [maybeDescendant] is [ancestorId] itself or lies below it.
  bool isInSubtree(String ancestorId, String maybeDescendant) {
    String? cur = maybeDescendant;
    final seen = <String>{};
    while (cur != null && seen.add(cur)) {
      if (cur == ancestorId) return true;
      cur = cardById(cur)?.parentId;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'version': currentFormatVersion,
    'id': id,
    'name': name,
    'docs': docs.map((d) => d.toJson()).toList(),
    'cards': cards.map((c) => c.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Damaged entries (a card or document that cannot be read) are skipped
  /// and logged instead of making the whole set unreadable.
  factory fromJson(Map<String, dynamic> j) => StudySet(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    docs: _each(j['docs'], StudyDoc.fromJson, 'document'),
    cards: _each(j['cards'], MCard.fromJson, 'card'),
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
    formatVersion: _int(j['version'], 1),
  );

  String encode() => const JsonEncoder.withIndent(' ').convert(toJson());
}

final _log = Logger('mnote.models');

int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;

List<T> _each<T>(
  Object? list,
  T Function(Map<String, dynamic>) parse,
  String what,
) {
  final out = <T>[];
  for (final e in (list as List? ?? const [])) {
    try {
      out.add(parse((e as Map).cast<String, dynamic>()));
    } catch (err) {
      _log.warning('Skipping unreadable $what: $err');
    }
  }
  return out;
}

final _rng = Random.secure();

/// Short random id, good enough for local objects.
String newId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = List.generate(6, (_) => chars[_rng.nextInt(chars.length)]).join();
  return '$t$r';
}
