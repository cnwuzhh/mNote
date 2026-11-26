import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import 'package:saber/mnote/model/models.dart';

/// Local persistence for study sets.
///
/// Layout under [rootDir]:
/// ```
/// sets/<setId>/set.json        study set, docs and cards
/// sets/<setId>/docs/<file>.pdf imported documents (copied in)
/// ```
/// Everything stays on the device; sync is a later milestone.
class StudyStore extends ChangeNotifier {
  new _(this.rootDir);

  static final log = Logger('StudyStore');

  static StudyStore? _instance;

  /// The app-wide store, created on first use.
  static Future<StudyStore> instance() async {
    if (_instance != null) return _instance!;
    final base = await getApplicationSupportDirectory();
    final store = StudyStore._(Directory('${base.path}/mnote'));
    await store.load();
    return _instance = store;
  }

  /// A store rooted at [dir], used by tests.
  @visibleForTesting
  static Future<StudyStore> open(Directory dir) async {
    final store = StudyStore._(dir);
    await store.load();
    return store;
  }

  final Directory rootDir;
  final List<StudySet> _sets = [];
  final Map<String, Timer> _pendingSaves = {};

  List<StudySet> get sets => List.unmodifiable(
    _sets..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
  );

  Directory _setDir(String id) => Directory('${rootDir.path}/sets/$id');
  File _setFile(String id) => File('${_setDir(id).path}/set.json');

  File docFile(StudySet set, StudyDoc doc) =>
      File('${_setDir(set.id).path}/docs/${doc.fileName}');

  /// Handwriting of [doc] (see InkDocument).
  File inkFile(StudySet set, StudyDoc doc) =>
      File('${_setDir(set.id).path}/ink/${doc.id}.ink.bson');

  // ---------- app-wide mNote settings (settings.json) ----------

  Map<String, dynamic> _settings = {};
  File get _settingsFile => File('${rootDir.path}/settings.json');

  /// Whether a finger draws in handwrite mode (default: only the stylus
  /// draws and fingers scroll).
  bool get fingerDrawing => _settings['fingerDrawing'] as bool? ?? false;
  set fingerDrawing(bool v) {
    _settings['fingerDrawing'] = v;
    _saveSettings();
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    await _settingsFile.parent.create(recursive: true);
    await _settingsFile.writeAsString(jsonEncode(_settings), flush: true);
  }

  File imageFile(StudySet set, String fileName) =>
      File('${_setDir(set.id).path}/images/$fileName');

  /// Saves PNG bytes of a region capture and returns the file name.
  Future<String> saveImage(StudySet set, List<int> pngBytes) async {
    final name = '${newId()}.png';
    final f = imageFile(set, name);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(pngBytes, flush: true);
    return name;
  }

  Future<void> load() async {
    try {
      if (_settingsFile.existsSync()) {
        _settings = (jsonDecode(await _settingsFile.readAsString()) as Map)
            .cast<String, dynamic>();
      }
    } catch (e) {
      log.warning('Ignoring unreadable settings.json: $e');
    }
    _sets.clear();
    final dir = Directory('${rootDir.path}/sets');
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync()) {
      if (entity is! Directory) continue;
      final f = File('${entity.path}/set.json');
      if (!f.existsSync()) continue;
      try {
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _sets.add(StudySet.fromJson(json));
      } catch (e, st) {
        log.severe('Failed to read ${f.path}', e, st);
      }
    }
    notifyListeners();
  }

  StudySet? byId(String id) {
    for (final s in _sets) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<StudySet> createSet(String name) async {
    final set = StudySet(
      id: newId(),
      name: name.trim().isEmpty ? '未命名学习集' : name.trim(),
    );
    _sets.add(set);
    await saveNow(set);
    notifyListeners();
    return set;
  }

  Future<void> deleteSet(StudySet set) async {
    _sets.remove(set);
    _pendingSaves.remove(set.id)?.cancel();
    final dir = _setDir(set.id);
    if (dir.existsSync()) await dir.delete(recursive: true);
    notifyListeners();
  }

  /// Copies [sourcePath] into the study set and registers it as a document.
  /// [pageCount] and [title] can be filled in later by the reader.
  Future<StudyDoc> importPdf(
    StudySet set,
    String sourcePath, {
    String? title,
    int pageCount = 0,
  }) async {
    final id = newId();
    final fileName = '$id.pdf';
    final dest = File('${_setDir(set.id).path}/docs/$fileName');
    await dest.parent.create(recursive: true);
    await File(sourcePath).copy(dest.path);
    final baseName = sourcePath.split(Platform.pathSeparator).last;
    final doc = StudyDoc(
      id: id,
      title:
          title ??
          baseName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
      fileName: fileName,
      pageCount: pageCount,
    );
    set.docs.add(doc);
    await saveNow(set);
    notifyListeners();
    return doc;
  }

  /// Marks [set] changed: notifies listeners now and saves shortly after,
  /// coalescing rapid edits (typing a title, scrolling) into one write.
  void touch(
    StudySet set, {
    Duration delay = const Duration(milliseconds: 400),
  }) {
    set.updatedAt = DateTime.now();
    notifyListeners();
    _pendingSaves.remove(set.id)?.cancel();
    _pendingSaves[set.id] = Timer(delay, () {
      _pendingSaves.remove(set.id);
      saveNow(set);
    });
  }

  /// Writes [set] atomically (temp file + rename).
  Future<void> saveNow(StudySet set) async {
    _pendingSaves.remove(set.id)?.cancel();
    final f = _setFile(set.id);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(set.encode(), flush: true);
    await tmp.rename(f.path);
  }

  /// Flushes all pending saves (call when the app goes to background).
  Future<void> flush() async {
    final ids = _pendingSaves.keys.toList();
    for (final id in ids) {
      final s = byId(id);
      if (s != null) await saveNow(s);
    }
  }

  // ---------- card operations ----------

  MCard addCard(StudySet set, MCard card) {
    final siblings = set.childrenOf(card.parentId);
    card.order = siblings.isEmpty ? 0 : siblings.last.order + 1;
    set.cards.add(card);
    touch(set, delay: Duration.zero);
    return card;
  }

  /// Removes [card]; its children move up to [card]'s parent.
  /// Returns a function that undoes the deletion.
  VoidCallback deleteCard(StudySet set, MCard card) {
    final index = set.cards.indexOf(card);
    final movedChildren = set.cards
        .where((c) => c.parentId == card.id)
        .toList();
    for (final c in movedChildren) {
      c.parentId = card.parentId;
    }
    set.cards.remove(card);
    touch(set, delay: Duration.zero);
    return () {
      set.cards.insert(index.clamp(0, set.cards.length), card);
      for (final c in movedChildren) {
        c.parentId = card.id;
      }
      touch(set, delay: Duration.zero);
    };
  }

  /// Moves [card] under [newParentId] (null = root). Ignored if that would
  /// put a card inside its own subtree.
  bool moveCard(StudySet set, MCard card, String? newParentId) {
    if (newParentId != null && set.isInSubtree(card.id, newParentId)) {
      return false;
    }
    card.parentId = newParentId;
    final siblings = set.childrenOf(newParentId).where((c) => c != card);
    card.order = siblings.isEmpty ? 0 : siblings.last.order + 1;
    touch(set, delay: Duration.zero);
    return true;
  }
}
