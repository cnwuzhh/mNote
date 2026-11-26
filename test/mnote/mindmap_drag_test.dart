import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/mnote/mindmap/mindmap_view.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

MCard _card(String id, {String? parent, int order = 0}) => MCard(
  id: id,
  docId: 'd',
  title: 'Card $id',
  text: 'text $id',
  color: ExcerptColor.definition,
  rects: const [PageRect(1, 72, 560, 290, 548)],
  parentId: parent,
  order: order,
);

/// Rules behind device cases TC-MAP-04 … TC-MAP-13.
void main() {
  group('StudyStore.moveCard / deleteCard', () {
    late Directory dir;
    late StudyStore store;
    late StudySet set;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('mnote_drag_test');
      store = await StudyStore.open(dir);
      set = await store.createSet('S');
      for (final id in ['A', 'B', 'C', 'D', 'E']) {
        store.addCard(set, _card(id));
      }
    });
    tearDown(() async {
      await store.flush();
      dir.deleteSync(recursive: true);
    });

    MCard c(String id) => set.cardById(id)!;
    List<String> kids(String? id) =>
        set.childrenOf(id).map((e) => e.id).toList();

    test(
      're-parent; dropped card goes last among its new siblings (TC-MAP-04)',
      () {
        expect(store.moveCard(set, c('B'), 'A'), isTrue);
        expect(store.moveCard(set, c('C'), 'A'), isTrue);
        expect(kids('A'), ['B', 'C']);
        expect(kids(null), ['A', 'D', 'E']);
      },
    );

    test('subtree moves together; three levels (TC-MAP-05/06)', () {
      store.moveCard(set, c('B'), 'A');
      store.moveCard(set, c('E'), 'B');
      store.moveCard(set, c('B'), 'D');
      expect(kids('D'), ['B']);
      expect(kids('B'), ['E']);
      expect(kids('A'), isEmpty);
    });

    test('cannot move into itself or a descendant (TC-MAP-07)', () {
      store.moveCard(set, c('B'), 'D');
      store.moveCard(set, c('E'), 'B');
      expect(store.moveCard(set, c('D'), 'E'), isFalse);
      expect(store.moveCard(set, c('B'), 'B'), isFalse);
      expect(c('D').parentId, isNull);
      expect(kids('D'), ['B']);
    });

    test('drop on root returns to the first level (TC-MAP-08)', () {
      store.moveCard(set, c('E'), 'A');
      expect(store.moveCard(set, c('E'), null), isTrue);
      expect(kids(null).last, 'E');
    });

    test('deleting a parent lifts its children; undo restores (TC-MAP-12)', () {
      store.moveCard(set, c('C'), 'D');
      final undo = store.deleteCard(set, c('D'));
      expect(set.cardById('D'), isNull);
      expect(c('C').parentId, isNull);
      undo();
      expect(set.cardById('D'), isNotNull);
      expect(c('C').parentId, 'D');
    });
  });

  testWidgets('recall: dragging a masked node does not reveal it (TC-MAP-13)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final set = StudySet(
      id: 's',
      name: 'Root',
      cards: [_card('a'), _card('b', order: 1)],
    );
    MCard? moved;
    String? newParent;
    final keys = <String, GlobalKey>{};
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: MnoteThemed(
          child: Scaffold(
            body: SizedBox(
              width: 900,
              height: 600,
              child: MindMapView(
                set: set,
                nodeKeys: keys,
                onOpen: (_) {},
                onJump: (_) {},
                onMove: (c, p) {
                  moved = c;
                  newParent = p;
                },
                masked: const {'a', 'b'},
                onReveal: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Card a'), findsNothing);
    expect(find.text('Card b'), findsNothing);

    final from = tester.getCenter(find.byKey(const ValueKey('mindmap-node-b')));
    final to = tester.getCenter(find.byKey(const ValueKey('mindmap-node-a')));
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveTo(Offset.lerp(from, to, 0.5)!);
    await tester.pump();
    expect(find.byKey(const ValueKey('mindmap-drag-masked')), findsOneWidget);
    expect(
      find.text('Card b'),
      findsNothing,
      reason: 'content stays hidden while dragging',
    );
    await g.moveTo(to);
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(moved?.id, 'b');
    expect(newParent, 'a');
  });
}
