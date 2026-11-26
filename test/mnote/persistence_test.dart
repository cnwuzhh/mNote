import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/mnote/ink/ink_document.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:sbn/tool_id.dart';

MCard _card(String id, {String? parent}) => MCard(
  id: id,
  docId: 'd',
  title: 'Card $id',
  text: 'text $id',
  color: ExcerptColor.evidence,
  rects: const [PageRect(1, 72, 560, 290, 548)],
  parentId: parent,
  note: 'note $id',
  tags: ['t$id'],
);

Stroke _stroke(InkDocument ink, double y) {
  final s = Stroke(
    color: Colors.black,
    pressureEnabled: true,
    options: StrokeOptions(size: 2, isComplete: true),
    pageIndex: 0,
    page: ink.pageSize(1, const Size(612, 792)),
    toolId: ToolId.fountainPen,
  );
  for (var x = 10.0; x < 200; x += 10) {
    s.addPoint(Offset(x, y), 0.5);
  }
  return s;
}

/// Persistence and restoring (反持久化): everything written must come back,
/// overlapping writes must not corrupt files, damaged files must not take
/// other data with them, and deleted sets must stay deleted.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('mnote_persist'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<StudyStore> reopen() => StudyStore.open(dir);

  test(
    'round trip: every field of sets, docs and cards survives a restart',
    () async {
      final store = await reopen();
      final set = await store.createSet('Agent 决策失败');
      final pdf = File('${dir.path}/src.pdf')..writeAsBytesSync([1, 2, 3]);
      final doc = await store.importPdf(set, pdf.path, pageCount: 33);
      doc
        ..lastPage = 7
        ..maxPageRead = 9;
      store
        ..addCard(set, _card('a'))
        ..addCard(set, _card('b', parent: 'a'))
        ..addCard(set, _card('c')..highlightOnly = true);
      set.cardById('a')!
        ..image = 'x.png'
        ..color = ExcerptColor.pitfall;
      store.touch(set);
      await store.flush();

      final back = (await reopen()).byId(set.id)!;
      expect(back.name, 'Agent 决策失败');
      final d = back.docById(doc.id)!;
      expect(
        [d.title, d.fileName, d.pageCount, d.lastPage, d.maxPageRead],
        ['src', doc.fileName, 33, 7, 9],
      );
      final a = back.cardById('a')!,
          b = back.cardById('b')!,
          c = back.cardById('c')!;
      expect(
        [a.title, a.text, a.note, a.tags, a.image, a.color],
        [
          'Card a',
          'text a',
          'note a',
          ['ta'],
          'x.png',
          ExcerptColor.pitfall,
        ],
      );
      expect(a.rects.single.top, 560);
      expect(b.parentId, 'a');
      expect(c.highlightOnly, isTrue);
      expect(back.cards.map((e) => e.id), [
        'a',
        'b',
        'c',
      ], reason: 'order kept');
      expect(a.createdAt.difference(set.cardById('a')!.createdAt).inSeconds, 0);
    },
  );

  test(
    'overlapping saves of the same set do not throw or corrupt set.json',
    () async {
      final store = await reopen();
      final set = await store.createSet('S');
      final futures = <Future<void>>[];
      for (var i = 0; i < 40; i++) {
        store.addCard(set, _card('c$i'));
        futures.add(store.saveNow(set));
      }
      await Future.wait(futures);
      await store.flush();
      final json = jsonDecode(
        File('${dir.path}/sets/${set.id}/set.json').readAsStringSync(),
      ) as Map;
      expect((json['cards'] as List).length, 40);
      expect((await reopen()).byId(set.id)!.cards.length, 40);
    },
  );

  test(
    'a deleted set does not come back from a save that was already running',
    () async {
      final store = await reopen();
      final set = await store.createSet('gone');
      store.addCard(set, _card('a'));
      final inFlight = store.saveNow(set); // e.g. a debounced save firing
      await store.deleteSet(set);
      await inFlight.catchError((_) {});
      store.touch(set); // e.g. an open workspace still editing it
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await store.flush();
      expect((await reopen()).byId(set.id), isNull);
      expect(Directory('${dir.path}/sets/${set.id}').existsSync(), isFalse);
    },
  );

  test('one damaged card does not lose the rest of the set', () async {
    final store = await reopen();
    final set = await store.createSet('S');
    store
      ..addCard(set, _card('a'))
      ..addCard(set, _card('b'));
    await store.flush();
    final f = File('${dir.path}/sets/${set.id}/set.json');
    final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    (json['cards'] as List).insert(1, {'id': 'broken'}); // no docId, no rects
    f.writeAsStringSync(jsonEncode(json));
    final back = (await reopen()).byId(set.id);
    expect(back, isNotNull, reason: 'set still loads');
    expect(back!.cards.map((c) => c.id), ['a', 'b']);
  });

  test(
    'numbers written as doubles (e.g. by another tool) still load',
    () async {
      final store = await reopen();
      final set = await store.createSet('S');
      store.addCard(set, _card('a'));
      await store.flush();
      final f = File('${dir.path}/sets/${set.id}/set.json');
      final s = f
          .readAsStringSync()
          .replaceAll('"order": 0', '"order": 0.0')
          .replaceAll('"p": 1', '"p": 1.0');
      f.writeAsStringSync(s);
      final back = (await reopen()).byId(set.id);
      expect(back?.cardById('a')?.rects.single.page, 1);
    },
  );

  test(
    'a truncated set.json falls back to the complete temp file if one exists',
    () async {
      final store = await reopen();
      final set = await store.createSet('S');
      store.addCard(set, _card('a'));
      await store.flush();
      final f = File('${dir.path}/sets/${set.id}/set.json');
      final good = f.readAsStringSync();
      File('${f.path}.tmp').writeAsStringSync(good);
      f.writeAsStringSync(good.substring(0, good.length ~/ 2));
      expect((await reopen()).byId(set.id)?.cardById('a'), isNotNull);
    },
  );

  test(
    'a set written by a newer mNote is loaded but never overwritten',
    () async {
      final store = await reopen();
      final set = await store.createSet('S');
      await store.flush();
      final f = File('${dir.path}/sets/${set.id}/set.json');
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>
        ..['version'] = 99
        ..['futureField'] = 'keep me';
      f.writeAsStringSync(jsonEncode(json));
      final s2 = await reopen();
      final back = s2.byId(set.id)!;
      back.name = 'changed';
      s2.touch(back);
      await s2.flush();
      expect(jsonDecode(f.readAsStringSync())['futureField'], 'keep me');
    },
  );

  test('settings survive rapid toggling', () async {
    final store = await reopen();
    for (var i = 0; i < 25; i++) {
      store.fingerDrawing = i.isEven;
    }
    await store.flush();
    expect((await reopen()).fingerDrawing, isTrue);
  });

  group('ink', () {
    test('overlapping saves do not corrupt the ink file', () async {
      final ink = InkDocument();
      final f = File('${dir.path}/ink/doc.ink.bson');
      final futures = <Future<void>>[];
      for (var i = 0; i < 30; i++) {
        ink.add(1, _stroke(ink, 10.0 + i));
        futures.add(ink.save(f));
      }
      await Future.wait(futures);
      expect((await InkDocument.load(f)).strokeCount, 30);
    });

    test(
      'a damaged ink file is set aside, not silently lost or overwritten',
      () async {
        final f = File('${dir.path}/ink/doc.ink.bson')
          ..createSync(recursive: true);
        f.writeAsBytesSync([1, 2, 3, 4, 5]);
        final d = await InkDocument.loadOrQuarantine(f);
        expect(d.isEmpty, isTrue);
        final aside = f.parent.listSync().whereType<File>().where(
          (e) => e.path.contains('.corrupt-'),
        );
        expect(
          aside,
          hasLength(1),
          reason: 'the damaged bytes are kept for recovery',
        );
        expect(aside.single.readAsBytesSync(), [1, 2, 3, 4, 5]);
      },
    );
  });
}
