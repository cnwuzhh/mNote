import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/mnote/store/study_store.dart';

/// Connects mNote's study sets to Saber's Nextcloud sync, which encrypts
/// paths and contents end to end and syncs every file in the data folder.
class SaberStoreSync implements StoreSync {
  /// Path relative to the synced data folder, with forward slashes (Windows
  /// lists directories with backslashes). Null when outside of it.
  static String? relative(String absolutePath, {String? root}) {
    final a = absolutePath.replaceAll(r'\', '/');
    final d = (root ?? FileManager.documentsDirectory).replaceAll(r'\', '/');
    if (!a.startsWith(d)) return null;
    final rel = a.substring(d.length);
    return rel.startsWith('/') ? rel : '/$rel';
  }

  void _enqueue(String path) {
    if (!stows.loggedIn) return;
    final rel = relative(path);
    if (rel == null || !SaberSyncInterface.isSyncablePath(rel)) return;
    syncer.uploader.enqueueRel(rel);
  }

  @override
  void written(String path) => _enqueue(path);

  /// The file is gone locally: the uploader then marks it deleted remotely.
  @override
  void deleted(String path) => _enqueue(path);

  @override
  Stream<(bool, String)> get incoming => FileManager.fileWriteStream.stream.map(
    (op) => (
      op.type == FileOperationType.delete,
      FileManager.documentsDirectory + op.filePath,
    ),
  );
}
