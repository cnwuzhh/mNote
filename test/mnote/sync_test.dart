import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';
import 'package:saber/mnote/ink/ink_document.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/store/atomic_file.dart';
import 'package:saber/mnote/store/saber_store_sync.dart';
import 'package:saber/mnote/store/study_store.dart';

class _FakeSync implements StoreSync {
  final uploads = <String>[], deletions = <String>[];
  final _in = StreamController<(bool, String)>.broadcast();
  @override
  void written(String path) => uploads.add(path);
  @override
  void deleted(String path) => deletions.add(path);
  @override
  Stream<(bool, String)> get incoming => _in.stream;
  void arrive(String path, {bool deleted = false}) => _in.add((deleted, path));
}

MCard _card(String id) => MCard(
  id: id,
  docId: 'd',
  title: 'Card $id',
  text: 't',
  color: ExcerptColor.definition,
  rects: const [PageRect(1, 1, 9, 5, 2)],
);

/// RESULTS-NEXTCLOUD (2026-11-27): study sets were never synced, and an
/// existing remote folder made MKCOL fail with 405.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('mnote_sync'));
  tearDown(() {
    AtomicFile.onWritten = null;
    dir.deleteSync(recursive: true);
  });

  group('migration to the synced folder', () {
    test(
      'moves existing study sets once; never overwrites newer data',
      () async {
        final legacy = Directory('${dir.path}/support/mnote');
        File('${legacy.path}/sets/s1/set.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(StudySet(id: 's1', name: 'Agent').encode());
        File('${legacy.path}/sets/s1/docs/a.pdf')
          ..createSync(recursive: true)
          ..writeAsBytesSync([1, 2, 3]);
        final synced = Directory('${dir.path}/docs/.mnote');

        await StudyStore.migrateLegacyDir(legacy, synced);
        expect(legacy.existsSync(), isFalse);
        expect(File('${synced.path}/sets/s1/docs/a.pdf').readAsBytesSync(), [
          1,
          2,
          3,
        ]);
        expect((await StudyStore.open(synced)).byId('s1')?.name, 'Agent');

        // A later stray legacy folder does not replace the synced data.
        File('${legacy.path}/sets/old/set.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(StudySet(id: 'old', name: 'Old').encode());
        await StudyStore.migrateLegacyDir(legacy, synced);
        expect(Directory('${synced.path}/sets/old').existsSync(), isFalse);
        expect(legacy.existsSync(), isTrue);
      },
    );
  });

  group('uploads and deletes', () {
    late StudyStore store;
    late _FakeSync sync;
    setUp(() async {
      store = await StudyStore.open(dir);
      sync = _FakeSync();
      store.attachSync(sync);
    });

    test(
      'every study-set file written is queued; device settings are not',
      () async {
        final set = await store.createSet('S');
        final setDir = '${dir.path}/sets/${set.id}';
        expect(sync.uploads, contains('$setDir/set.json'));

        final pdf = File('${dir.path}/src.pdf')..writeAsBytesSync([1, 2, 3]);
        final doc = await store.importPdf(set, pdf.path);
        expect(sync.uploads, contains('$setDir/docs/${doc.fileName}'));

        final img = await store.saveImage(
          set,
          Uint8List.fromList([137, 80, 78, 71]),
        );
        expect(sync.uploads, contains('$setDir/images/$img'));

        await InkDocument().save(store.inkFile(set, doc));
        expect(sync.uploads, contains(store.inkFile(set, doc).path));

        store.fingerDrawing = true;
        await store.flush();
        expect(
          sync.uploads.where((p) => p.endsWith('settings.json')),
          isEmpty,
          reason: 'per-device setting',
        );
        expect(sync.uploads.where((p) => p.endsWith('.tmp')), isEmpty);
      },
    );

    test(
      'deleting a set queues every one of its files for remote deletion',
      () async {
        final set = await store.createSet('S');
        store.addCard(set, _card('a'));
        final pdf = File('${dir.path}/src.pdf')..writeAsBytesSync([1, 2, 3]);
        final doc = await store.importPdf(set, pdf.path);
        await store.flush();
        final setDir = '${dir.path}/sets/${set.id}';
        await store.deleteSet(set);
        expect(
          sync.deletions.map((p) => p.replaceAll(r'\', '/')),
          containsAll(['$setDir/set.json', '$setDir/docs/${doc.fileName}']),
        );
      },
    );
  });

  group('downloads from another device', () {
    late StudyStore store;
    late _FakeSync sync;
    setUp(() async {
      store = await StudyStore.open(dir);
      sync = _FakeSync();
      store.attachSync(sync);
    });

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    test(
      'a changed set is applied in place (open pages keep the object)',
      () async {
        final set = await store.createSet('Mine');
        store.addCard(set, _card('a'));
        await store.flush();
        // The other device renamed it and added a card; the syncer wrote it.
        final remote = StudySet.fromJson(
          jsonDecode(
            File('${dir.path}/sets/${set.id}/set.json').readAsStringSync(),
          ) as Map<String, dynamic>,
        )..name = 'Renamed elsewhere';
        remote.cards.add(_card('b'));
        final f = File('${dir.path}/sets/${set.id}/set.json')
          ..writeAsStringSync(remote.encode());
        sync.arrive(f.path);
        await settle();
        expect(identical(store.byId(set.id), set), isTrue);
        expect(set.name, 'Renamed elsewhere');
        expect(set.cards.map((c) => c.id), ['a', 'b']);
      },
    );

    test(
      'a new set from another device appears; a deleted one disappears',
      () async {
        final other = StudySet(id: 'fromtablet', name: 'From the tablet');
        final f = File('${dir.path}/sets/fromtablet/set.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(other.encode());
        sync.arrive(f.path);
        await settle();
        expect(store.byId('fromtablet')?.name, 'From the tablet');

        f.deleteSync();
        sync.arrive(f.path, deleted: true);
        await settle();
        expect(store.byId('fromtablet'), isNull);
      },
    );

    test('other files and paths outside the study sets are ignored', () async {
      sync.arrive('${dir.path}/sets/x/docs/a.pdf');
      sync.arrive('/elsewhere/sets/y/set.json');
      await settle();
      expect(store.sets, isEmpty);
    });
  });

  test(
    'temporary files are not synced; 405 means the folder already exists',
    () {
      expect(
        SaberSyncInterface.isSyncablePath('/.mnote/sets/a/set.json'),
        isTrue,
      );
      expect(
        SaberSyncInterface.isSyncablePath('/.mnote/sets/a/set.json.tmp'),
        isFalse,
      );
      expect(
        SaberSyncInterface.isSyncablePath('/tmp/download-1.part'),
        isFalse,
      );
      expect(
        SaberSyncInterface.isSyncablePath(
          '/.mnote/sets/a/ink/d.ink.bson.corrupt-123',
        ),
        isFalse,
      );
      expect(SaberSyncInterface.isAlreadyExists(405), isTrue);
      expect(SaberSyncInterface.isAlreadyExists(404), isFalse);
    },
  );

  test(
    'paths relative to the synced folder, also with Windows backslashes',
    () {
      expect(
        SaberStoreSync.relative(
          '/data/app_flutter/mNote/.mnote/sets/x/set.json',
          root: '/data/app_flutter/mNote',
        ),
        '/.mnote/sets/x/set.json',
      );
      expect(
        SaberStoreSync.relative(
          r'C:\Users\a\Documents\mNote\.mnote\sets\x\set.json',
          root: r'C:\Users\a\Documents\mNote',
        ),
        '/.mnote/sets/x/set.json',
      );
      expect(
        SaberStoreSync.relative(
          '/other/place/set.json',
          root: '/data/app_flutter/mNote',
        ),
        isNull,
      );
    },
  );

  test("Saber's note list does not show the hidden study-set folder", () async {
    FileManager.documentsDirectory = dir.path;
    Directory('${dir.path}/.mnote/sets').createSync(recursive: true);
    Directory('${dir.path}/My notes').createSync();
    final children = await FileManager.getChildrenOfDirectory('/');
    expect(children!.directories, contains('My notes'));
    expect(children.directories.where((d) => d.contains('.mnote')), isEmpty);
  });
}
