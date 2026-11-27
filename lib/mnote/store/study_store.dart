import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/store/atomic_file.dart';

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

  static Future<StudyStore>? _instance;

  /// The app-wide store, created on first use. Concurrent callers get the
  /// same store (two stores over the same files would overwrite each other).
  /// A failed open is not cached, so 「重试」 really tries again.
  static Future<StudyStore> instance() => _instance ??= _create().then(
    (s) => s,
    onError: (Object e, StackTrace st) {
      _instance = null;
      Error.throwWithStackTrace(StoreAccessException.from(e, 'open'), st);
    },
  );

  static Future<StudyStore> _create() async {
    final base = await getApplicationSupportDirectory();
    final store = StudyStore._(Directory('${base.path}/mnote'));
    await store.load();
    // Write pending edits whenever the app leaves the foreground: Android
    // may kill it in the background without further notice.
    // The binding keeps the listener alive for the lifetime of the app.
    AppLifecycleListener(
      onInactive: store.flush,
      onHide: store.flush,
      onPause: store.flush,
      onDetach: store.flush,
    );
    return store;
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

  /// The last save failure (shown to the user), cleared by the next
  /// successful save. Null while saving works.
  final saveError = ValueNotifier<String?>(null);
  final Map<String, Timer> _pendingSaves = {};

  /// Ids of deleted sets: later saves (an open workspace, a debounced save
  /// already scheduled) must not bring them back.
  final Set<String> _deleted = {};

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

  Future<void> _saveSettings() => AtomicFile.write(
    _settingsFile,
    utf8.encode(jsonEncode(_settings)),
  ).catchError((Object e) => log.warning('Could not save settings.json: $e'));

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
      final set = await _readSet(File('${entity.path}/set.json'));
      if (set != null) _sets.add(set);
    }
    notifyListeners();
  }

  /// Reads a set from `set.json`, or from `set.json.tmp` when that is the
  /// newer readable copy (the app stopped between writing the temp file and
  /// renaming it) or `set.json` itself is damaged.
  Future<StudySet?> _readSet(File f) async {
    final tmp = File('${f.path}.tmp');
    Future<StudySet?> parse(File file) async {
      if (!file.existsSync()) return null;
      try {
        return StudySet.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
      } catch (e) {
        log.severe('Cannot read ${file.path}: $e');
        return null;
      }
    }

    final main = await parse(f), fromTmp = await parse(tmp);
    if (fromTmp != null &&
        (main == null || fromTmp.updatedAt.isAfter(main.updatedAt))) {
      log.warning('Recovered ${f.path} from its temp file');
      try {
        await tmp.rename(f.path);
      } catch (_) {}
      return fromTmp;
    }
    if (main == null && f.existsSync()) {
      log.severe(
        '${f.path} is damaged and no temp copy is readable; leaving it untouched',
      );
    }
    return main;
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
    try {
      await saveNow(set);
    } catch (e) {
      // Not saved: do not pretend it exists.
      _sets.remove(set);
      throw StoreAccessException.from(e, 'create');
    }
    notifyListeners();
    return set;
  }

  Future<void> deleteSet(StudySet set) async {
    _deleted.add(set.id);
    _sets.remove(set);
    _pendingSaves.remove(set.id)?.cancel();
    // Let a save that is already running finish before removing the folder.
    await AtomicFile.idle(_setFile(set.id));
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
    String? sourceUrl,
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
      sourceUrl: sourceUrl,
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
    if (_deleted.contains(set.id)) return;
    set.updatedAt = DateTime.now();
    notifyListeners();
    _pendingSaves.remove(set.id)?.cancel();
    _pendingSaves[set.id] = Timer(delay, () {
      _pendingSaves.remove(set.id);
      saveNow(set).catchError((Object e) {
        log.severe('Saving ${set.id} failed: $e');
        saveError.value = StoreAccessException.from(e, 'save').message;
      });
    });
  }

  /// Writes [set] atomically. Saves of the same set run one after another
  /// (the latest content wins); deleted sets and sets from a newer format
  /// version are never written.
  Future<void> saveNow(StudySet set) async {
    _pendingSaves.remove(set.id)?.cancel();
    if (_deleted.contains(set.id)) return;
    if (set.formatVersion > StudySet.currentFormatVersion) {
      log.warning(
        'Not saving ${set.id}: written by a newer mNote (format ${set.formatVersion})',
      );
      return;
    }
    await AtomicFile.write(_setFile(set.id), utf8.encode(set.encode()));
    if (saveError.value != null) saveError.value = null;
  }

  /// Writes all pending changes and waits until every write is on disk
  /// (called when the app leaves the foreground and when a document closes).
  Future<void> flush() async {
    final ids = _pendingSaves.keys.toList();
    for (final id in ids) {
      final s = byId(id);
      if (s != null) {
        try {
          await saveNow(s);
        } catch (e) {
          log.severe('Saving $id failed: $e');
          saveError.value = StoreAccessException.from(e, 'save').message;
        }
      }
    }
    await AtomicFile.allIdle();
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

/// The data folder cannot be opened or written (permissions, disk full, …).
/// [message] is meant for the user: what failed, where, and why.
class StoreAccessException implements Exception {
  new(this.message, {this.path});

  final String message;
  final String? path;

  /// [what]: 'open' (data folder at startup), 'create' (new study set),
  /// 'save' (saving changes).
  factory from(Object e, String what) {
    if (e is StoreAccessException) return e;
    final action = switch (what) {
      'open' => '无法打开 mNote 的数据文件夹',
      'create' => '无法新建学习集',
      _ => '保存失败',
    };
    if (e is FileSystemException) {
      final reason = e.osError?.message.trim().isNotEmpty == true
          ? e.osError!.message.trim()
          : e.message;
      return StoreAccessException(
        '$action：$reason（${e.path ?? '未知位置'}）',
        path: e.path,
      );
    }
    return StoreAccessException('$action：$e');
  }

  @override
  String toString() => message;
}
