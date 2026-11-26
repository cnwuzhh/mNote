import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/mnote/ink/ink_paint.dart';
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
            ink: InkControls(
              tool: InkTool.pen,
              onTool: (_) {},
              color: penColors.first,
              onColor: (_) {},
              width: InkWidth.medium,
              onWidth: (_) {},
              canUndo: false,
              canRedo: false,
              onUndo: () {},
              onRedo: () {},
              fingerDrawing: false,
              onFingerDrawing: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('框选'), findsOneWidget);
    expect(find.byTooltip('钢笔'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mode-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mode-menu-handwrite')).last);
    await tester.pumpAndSettle();
    expect(find.text('框选'), findsNothing);
    for (final t in ['钢笔', '荧光笔', '橡皮', '套索', '撤销', '重做', '手指书写：关']) {
      expect(find.byTooltip(t), findsOneWidget, reason: t);
    }
    expect(find.text('后续版本'), findsNothing);

    // In handwrite mode the modes collapse into a menu.
    await tester.tap(find.byKey(const ValueKey('mode-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mode-menu-recall')));
    await tester.pumpAndSettle();
    expect(find.text('全部揭示'), findsOneWidget);
    expect(find.text('重新遮挡'), findsOneWidget);
  });
}
