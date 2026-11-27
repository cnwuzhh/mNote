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

  /// Where study sets live: a hidden folder inside the synced data folder,
  /// so Nextcloud sync (end-to-end encrypted) carries them. Set by the app.
  static Directory Function()? syncedRoot;

  /// Connects the store to sync. Set by the app; null in tests.
  static StoreSync? sync;

  static Future<StudyStore> _create() async {
    final legacy = Directory(
      '${(await getApplicationSupportDirectory()).path}/mnote',
    );
    final root = syncedRoot?.call() ?? legacy;
    if (root.path != legacy.path) await migrateLegacyDir(legacy, root);
    final store = StudyStore._(root);
    await store.load();
    store.attachSync(sync);
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

  /// Moves study sets from the old, unsynced location ([from]) to [to] once.
  /// A rename when possible, otherwise copy then delete (other volume).
  static Future<void> migrateLegacyDir(Directory from, Directory to) async {
    if (!from.existsSync() || Directory('${to.path}/sets').existsSync()) return;
    await to.parent.create(recursive: true);
    try {
      if (to.existsSync()) await to.delete(recursive: true);
      await from.rename(to.path);
      log.info('Moved study sets to ${to.path}');
      return;
    } catch (e) {
      log.info('Rename failed ($e); copying study sets to ${to.path}');
    }
    await for (final e in from.list(recursive: true)) {
      if (e is! File) continue;
      final rel = e.path.substring(from.path.length);
      final dest = File('${to.path}$rel');
      await dest.parent.create(recursive: true);
      await e.copy(dest.path);
    }
    await from.delete(recursive: true);
    log.info('Copied study sets to ${to.path}');
  }

  StreamSubscription<(bool, String)>? _incoming;

  /// Uploads every file written under [rootDir]/sets; applies downloaded
  /// study sets (changed or deleted on another device).
  void attachSync(StoreSync? s) {
    _sync = s;
    if (s == null) return;
    AtomicFile.onWritten = (f) {
      if (_inSets(f.path)) s.written(f.path);
    };
    _incoming?.cancel();
    _incoming = s.incoming.listen((e) => onIncoming(deleted: e.$1, path: e.$2));
  }

  StoreSync? _sync;

  bool _inSets(String path) => path.startsWith('${rootDir.path}/sets/');

  /// A file under [rootDir] was downloaded ([deleted]: removed remotely).
  @visibleForTesting
  Future<void> onIncoming({required bool deleted, required String path}) async {
    final m = RegExp(r'/sets/([^/]+)/set\.json$').firstMatch(path);
    if (m == null || !_inSets(path)) return;
    final id = m.group(1)!;
    if (deleted) {
      final s = byId(id);
      if (s != null) {
        _sets.remove(s);
        _pendingSaves.remove(id)?.cancel();
        notifyListeners();
      }
      return;
    }
    if (_deleted.contains(id)) return;
    final fresh = await _readSet(File(path));
    if (fresh == null) return;
    final cur = byId(id);
    if (cur == null) {
      _sets.add(fresh);
    } else {
      // Update in place: open pages keep the same object.
      cur
        ..name = fresh.name
        ..aiDisabled = fresh.aiDisabled
        ..updatedAt = fresh.updatedAt;
      cur.docs
        ..clear()
        ..addAll(fresh.docs);
      cur.cards
        ..clear()
        ..addAll(fresh.cards);
      cur.aiNotes
        ..clear()
        ..addAll(fresh.aiNotes);
    }
    notifyListeners();
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

  // Saves are numbered: a failure is only reported if no later save has
  // succeeded since (a late error must not bring the warning back).
  var _saveSeq = 0;
  var _lastOkSeq = 0;

  void _reportSaveFailure(int seq, Object e) {
    if (seq > _lastOkSeq)
      saveError.value = StoreAccessException.from(e, 'save').message;
  }

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
    _sync?.written(f.path);
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
      await saveNow(set, report: false);
    } catch (e) {
      // Not saved: do not pretend it exists (the caller explains why).
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
    final files = dir.existsSync()
        ? [
            for (final f in dir.listSync(recursive: true))
              if (f is File) f.path,
          ]
        : <String>[];
    if (dir.existsSync()) await dir.delete(recursive: true);
    // Delete them on the server too (Saber marks remote deletions).
    for (final f in files) {
      _sync?.deleted(f);
    }
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
    _sync?.written(dest.path);
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
      });
    });
  }

  /// Writes [set] atomically. Saves of the same set run one after another
  /// (the latest content wins); deleted sets and sets from a newer format
  /// version are never written.
  /// [report]: put a failure in [saveError] (off when the caller tells the
  /// user itself, e.g. creating a set).
  Future<void> saveNow(StudySet set, {bool report = true}) async {
    _pendingSaves.remove(set.id)?.cancel();
    if (_deleted.contains(set.id)) return;
    if (set.formatVersion > StudySet.currentFormatVersion) {
      log.warning(
        'Not saving ${set.id}: written by a newer mNote (format ${set.formatVersion})',
      );
      return;
    }
    final seq = ++_saveSeq;
    try {
      await AtomicFile.write(_setFile(set.id), utf8.encode(set.encode()));
    } catch (e) {
      if (report) _reportSaveFailure(seq, e);
      rethrow;
    }
    if (seq > _lastOkSeq) _lastOkSeq = seq;
    if (saveError.value != null && _lastOkSeq == _saveSeq)
      saveError.value = null;
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

/// The store's link to sync (Nextcloud): what to upload / delete, and what
/// arrived. Paths are absolute.
abstract class StoreSync {
  void written(String path);
  void deleted(String path);

  /// Downloads: (deleted?, path).
  Stream<(bool, String)> get incoming;
}
