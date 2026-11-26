import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/mnote/mindmap/mindmap_view.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/excerpt_menu.dart';
import 'package:saber/mnote/reader/mode_toolbar.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

Widget _host(Widget child) => MaterialApp(
  theme: mnoteTheme(ThemeData.light(), night: false),
  home: Scaffold(body: Center(child: child)),
);

MCard _card(
  String id, {
  String? parent,
  ExcerptColor color = ExcerptColor.definition,
}) => MCard(
  id: id,
  docId: 'd',
  title: 'Card $id',
  text: 'text $id',
  color: color,
  rects: const [PageRect(1, 0, 10, 10, 0)],
  parentId: parent,
);

void main() {
  testWidgets('excerpt menu: pick a colour, then 摘录为卡片', (tester) async {
    ExcerptAction? action;
    ExcerptColor? color;
    await tester.pumpWidget(
      _host(
        ExcerptMenu(
          initialColor: ExcerptColor.definition,
          onAction: (a, c) {
            action = a;
            color = c;
          },
        ),
      ),
    );
    expect(find.text('摘录为卡片'), findsOneWidget);
    expect(find.text('仅高亮'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('excerpt-color-evidence')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('excerpt-to-card')));
    expect(action, ExcerptAction.card);
    expect(color, ExcerptColor.evidence);

    await tester.tap(find.byKey(const ValueKey('excerpt-highlight')));
    expect(action, ExcerptAction.highlight);
  });

  testWidgets('mind map: long-press drag a card onto another re-parents it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final set = StudySet(
      id: 's',
      name: 'Agent 决策失败',
      cards: [
        _card('a'),
        _card('b', color: ExcerptColor.evidence),
      ],
    );
    set.cards[1].order = 1;
    MCard? moved;
    String? newParent = 'unset';
    MCard? jumped;
    final keys = <String, GlobalKey>{};

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 600,
          height: 500,
          child: MindMapView(
            set: set,
            nodeKeys: keys,
            onOpen: (_) {},
            onJump: (c) => jumped = c,
            onMove: (c, p) {
              moved = c;
              newParent = p;
            },
          ),
        ),
      ),
    );
    expect(find.text('Agent 决策失败'), findsOneWidget);
    expect(find.text('Card a'), findsOneWidget);
    expect(find.text('Card b'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mindmap-jump-a')));
    expect(jumped?.id, 'a');

    final from = tester.getCenter(find.text('Card b'));
    final to = tester.getCenter(find.text('Card a'));
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveTo(Offset.lerp(from, to, 0.5)!);
    await tester.pump();
    await g.moveTo(to);
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(moved?.id, 'b');
    expect(newParent, 'a');
  });

  testWidgets('toolbar: switching mode swaps the whole tool group', (
    tester,
  ) async {
    var mode = WorkMode.excerpt;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _host(
          ModeToolbar(
            mode: mode,
            onMode: (m) => setState(() => mode = m),
            color: ExcerptColor.definition,
            onColor: (_) {},
            tool: ExcerptTool.text,
            onTool: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('框选'), findsOneWidget);
    expect(find.text('钢笔'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mode-handwrite')));
    await tester.pump();
    expect(find.text('框选'), findsNothing);
    expect(find.text('钢笔'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mode-recall')));
    await tester.pump();
    expect(find.text('揭示'), findsOneWidget);
  });
}
