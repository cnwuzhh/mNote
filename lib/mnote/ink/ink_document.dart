import 'dart:io';
import 'dart:typed_data';

import 'package:bson/bson.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:sbn/has_size.dart';

/// Handwriting on one PDF document: Saber [Stroke]s grouped by page.
///
/// Stroke points are in PDF page space: PDF points with the origin at the
/// page's top-left corner (y grows downwards), independent of zoom and screen.
/// Stored as BSON (Saber's stroke point encoding is binary), one file per
/// document: `sets/<setId>/ink/<docId>.ink.bson`.
class InkDocument {
  new();

  /// 1-based page number -> strokes in drawing order.
  final Map<int, List<Stroke>> _pages = {};

  /// Page sizes in PDF points, needed to re-create strokes when loading.
  final Map<int, Size> _sizes = {};

  final history = InkHistory();

  List<Stroke> strokesOn(int pageNumber) => _pages[pageNumber] ?? const [];

  bool get isEmpty => _pages.values.every((s) => s.isEmpty);

  int get strokeCount => _pages.values.fold(0, (n, s) => n + s.length);

  Iterable<int> get pagesWithInk =>
      _pages.entries.where((e) => e.value.isNotEmpty).map((e) => e.key);

  HasSize pageSize(int pageNumber, Size size) {
    _sizes[pageNumber] = size;
    return HasSize(size);
  }

  void _insert(int page, Stroke s, [int? index]) {
    final list = _pages.putIfAbsent(page, () => []);
    if (index == null || index > list.length) {
      list.add(s);
    } else {
      list.insert(index, s);
    }
  }

  /// Adds a finished stroke (recorded for undo).
  void add(int page, Stroke s) {
    _insert(page, s);
    history.push(InkAction(page, added: [s]));
  }

  /// Removes [strokes] from [page] (recorded for undo as one action).
  void remove(int page, List<Stroke> strokes) {
    final list = _pages[page];
    if (list == null || strokes.isEmpty) return;
    final removed = <(int, Stroke)>[];
    for (final s in strokes) {
      final i = list.indexOf(s);
      if (i >= 0) removed.add((i, s));
    }
    if (removed.isEmpty) return;
    removed.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, s) in removed.reversed) {
      list.remove(s);
    }
    history.push(InkAction(page, removed: removed));
  }

  bool undo() {
    final a = history._undo.isEmpty ? null : history._undo.removeLast();
    if (a == null) return false;
    _apply(a, reverse: true);
    history._redo.add(a);
    history.changed();
    return true;
  }

  bool redo() {
    final a = history._redo.isEmpty ? null : history._redo.removeLast();
    if (a == null) return false;
    _apply(a, reverse: false);
    history._undo.add(a);
    history.changed();
    return true;
  }

  void _apply(InkAction a, {required bool reverse}) {
    final list = _pages.putIfAbsent(a.page, () => []);
    if (!reverse) {
      list.addAll(a.added);
      for (final (_, s) in a.removed.reversed) {
        list.remove(s);
      }
    } else {
      for (final s in a.added) {
        list.remove(s);
      }
      for (final (i, s) in a.removed) {
        _insert(a.page, s, i);
      }
    }
  }

  // ---------- persistence ----------

  Uint8List toBson() {
    final pages = <String, dynamic>{};
    for (final e in _pages.entries) {
      if (e.value.isEmpty) continue;
      final size = _sizes[e.key] ?? e.value.first.page.size;
      pages['${e.key}'] = {
        'w': size.width,
        'h': size.height,
        's': [for (final s in e.value) s.toJson()],
      };
    }
    return BsonCodec.serialize({'v': EditorCoreInfo.sbnVersion, 'pages': pages})
        .byteList;
  }

  static InkDocument fromBson(Uint8List bytes) {
    final doc = InkDocument();
    final json = BsonCodec.deserialize(BsonBinary.from(bytes));
    final version = json['v'] as int? ?? EditorCoreInfo.sbnVersion;
    final pages = (json['pages'] as Map?) ?? const {};
    for (final e in pages.entries) {
      final page = int.tryParse('${e.key}');
      if (page == null) continue;
      final p = (e.value as Map).cast<String, dynamic>();
      final size = Size((p['w'] as num).toDouble(), (p['h'] as num).toDouble());
      final hasSize = doc.pageSize(page, size);
      for (final s in (p['s'] as List? ?? const [])) {
        doc._insert(
          page,
          Stroke.fromJson(
            (s as Map).cast<String, dynamic>(),
            fileVersion: version,
            pageIndex: page - 1,
            page: hasSize,
          ),
        );
      }
    }
    return doc;
  }

  static Future<InkDocument> load(File f) async {
    if (!f.existsSync()) return InkDocument();
    return fromBson(await f.readAsBytes());
  }

  Future<void> save(File f) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(toBson(), flush: true);
    await tmp.rename(f.path);
  }
}

class InkAction {
  new(this.page, {this.added = const [], this.removed = const []});
  final int page;
  final List<Stroke> added;
  final List<(int, Stroke)> removed;
}

/// Undo/redo stacks; listeners are told when availability changes.
class InkHistory extends ChangeNotifier {
  final _undo = <InkAction>[];
  final _redo = <InkAction>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void push(InkAction a) {
    _undo.add(a);
    _redo.clear();
    notifyListeners();
  }

  void changed() => notifyListeners();
}
