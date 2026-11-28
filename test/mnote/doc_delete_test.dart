import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/mnote/bookshelf/bookshelf_page.dart';
import 'package:saber/mnote/ink/ink_document.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/store/study_store.dart';

class _FakeSync implements StoreSync {
  final deletions = <String>[];
  @override
  void written(String path) {}
  @override
  void deleted(String path) => deletions.add(path);
  @override
  Stream<(bool, String)> get incoming => const Stream.empty();
}

MCard _card(
  String id,
  String docId, {
  String? parent,
  String? image,
  bool hl = false,
}) => MCard(
  id: id,
  docId: docId,
  title: 'Card $id',
  text: 't',
  color: ExcerptColor.definition,
  rects: const [PageRect(1, 1, 9, 5, 2)],
  parentId: parent,
  image: image,
  highlightOnly: hl,
);

/// Deleting an imported PDF (option 1: its cards go with it).
void main() {
  late Directory dir;
  late StudyStore store;
  late StudySet set;
  late StudyDoc a, b;
  late _FakeSync sync;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('mnote_deldoc');
    store = await StudyStore.open(dir);
    sync = _FakeSync();
    store.attachSync(sync);
    set = await store.createSet('S');
    final pdf = File('${dir.path}/src.pdf')..writeAsBytesSync([1, 2, 3]);
    a = await store.importPdf(set, pdf.path, title: 'Paper A');
    b = await store.importPdf(set, pdf.path, title: 'Paper B');
    final img = await store.saveImage(set, [137, 80, 78, 71]);
    // A1 (doc A) ─┬─ B1 (doc B)
    //             └─ A2 (doc A) ── B2 (doc B)
    store
      ..addCard(set, _card('A1', a.id, image: img))
      ..addCard(set, _card('B1', b.id, parent: 'A1'))
      ..addCard(set, _card('A2', a.id, parent: 'A1'))
      ..addCard(set, _card('B2', b.id, parent: 'A2'))
      ..addCard(set, _card('Ahl', a.id, hl: true));
    set.aiNotes.add(
      AiNote(
        id: 'n',
        docId: a.id,
        kind: AiNote.translate,
        rects: const [],
        source: 's',
        result: 'r',
      ),
    );
    await InkDocument().save(store.inkFile(set, a));
    await store.flush();
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('removes the document, its cards, highlights and AI notes; other cards move up', () async {
    final pdfA = store.docFile(set, a);
    store.deleteDoc(set, a, grace: const Duration(seconds: 30));
    expect(set.docs, [b]);
    expect(set.cards.map((c) => c.id), ['B1', 'B2']);
    expect(set.aiNotes, isEmpty);
    expect(
      set.cardById('B1')!.parentId,
      isNull,
      reason: 'A1 is gone: to the root',
    );
    expect(
      set.cardById('B2')!.parentId,
      isNull,
      reason: 'A2 and A1 are gone: to the root',
    );
    expect(pdfA.existsSync(), isTrue, reason: 'files wait for the undo window');
    await store.flush(); // leaving the app finishes the deletion
    expect(pdfA.existsSync(), isFalse);
    expect(store.inkFile(set, a).existsSync(), isFalse);
    expect(
      sync.deletions,
      containsAll([pdfA.path, store.inkFile(set, a).path]),
    );
    expect(
      sync.deletions.where((p) => p.contains('/images/')),
      hasLength(1),
      reason: 'the removed card’s screenshot',
    );
    expect(store.docFile(set, b).existsSync(), isTrue);
    // Saved like that.
    final back = (await StudyStore.open(dir)).byId(set.id)!;
    expect(back.docs.map((d) => d.title), ['Paper B']);
    expect(back.cards.map((c) => c.id), ['B1', 'B2']);
  });

  test(
    'undo within the window restores everything, files and hierarchy',
    () async {
      final undo = store.deleteDoc(
        set,
        a,
        grace: const Duration(milliseconds: 300),
      );
      undo();
      expect(set.docs.map((d) => d.title), ['Paper A', 'Paper B']);
      expect(set.cards.map((c) => c.id), ['A1', 'B1', 'A2', 'B2', 'Ahl']);
      expect(set.cardById('B1')!.parentId, 'A1');
      expect(set.cardById('B2')!.parentId, 'A2');
      expect(set.aiNotes.single.id, 'n');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        store.docFile(set, a).existsSync(),
        isTrue,
        reason: 'undo cancelled the file deletion',
      );
      expect(sync.deletions, isEmpty);
    },
  );

  test(
    'after the window the files are deleted and undo does nothing',
    () async {
      final undo = store.deleteDoc(
        set,
        a,
        grace: const Duration(milliseconds: 100),
      );
      for (var i = 0; i < 40 && store.docFile(set, a).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(store.docFile(set, a).existsSync(), isFalse);
      undo();
      expect(set.docs, [b], reason: 'too late to undo');
    },
  );

  testWidgets('long-press → 删除文档 → confirm (with what goes) → 撤销', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: StudySetPage(store: store, set: set),
      ),
    );
    await tester.pump();

    await tester.longPress(find.byKey(ValueKey('doc-${a.id}')));
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('doc-delete')));
    await tester.pumpAndSettle();
    expect(find.text('删除「Paper A」？'), findsOneWidget);
    expect(find.textContaining('2 张卡片、1 处高亮、手写笔迹、1 个翻译 / 解释'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('doc-delete-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('doc-${a.id}')), findsNothing);
    expect(find.text('已删除「Paper A」'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('doc-undo')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('doc-${a.id}')), findsOneWidget);
    expect(set.cards, hasLength(5));
    // Let the (cancelled) undo window and the snack bar run out on the test clock.
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
  });
}
