import 'dart:async';
import 'dart:io';

/// Atomic, serialized file writes.
///
/// * Atomic: bytes go to `<file>.tmp`, which is then renamed over the file,
///   so a crash leaves either the old or the new content, never a mix.
/// * Serialized: writes to the same path run one after another in call
///   order (the last call's content ends up on disk). Without this, two
///   overlapping saves share one temp file and can corrupt it or fail on
///   rename.
class AtomicFile {
  new _();

  static final _queues = <String, Future<void>>{};

  /// Called after each successful write (used to queue sync uploads).
  static void Function(File file)? onWritten;

  static String _key(File f) => f.absolute.path;

  /// Queues writing [bytes] to [file]. The returned future completes when
  /// this write is on disk and fails if this write failed.
  static Future<void> write(File file, List<int> bytes) {
    final key = _key(file);
    final prev = _queues[key] ?? Future<void>.value();
    final next = prev
        .then((_) {}, onError: (_) {})
        .then((_) => _write(file, bytes));
    final tracked = next.then((_) {}, onError: (_) {});
    _queues[key] = tracked;
    unawaited(
      tracked.whenComplete(() {
        if (identical(_queues[key], tracked)) _queues.remove(key);
      }),
    );
    return next;
  }

  static Future<void> _write(File f, List<int> bytes) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
    onWritten?.call(f);
  }

  /// Completes when every queued write to [file] has finished.
  static Future<void> idle(File file) =>
      _queues[_key(file)] ?? Future<void>.value();

  /// Completes when every queued write has finished.
  static Future<void> allIdle() async {
    while (_queues.isNotEmpty) {
      await Future.wait(_queues.values.toList());
    }
  }
}
