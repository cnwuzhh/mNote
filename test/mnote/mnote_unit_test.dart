import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/model/text_clean.dart';
import 'package:saber/mnote/reader/margin_rail.dart';
import 'package:saber/mnote/store/study_store.dart';

void main() {
  group('cleanExcerptText', () {
    test('joins a hyphenated word split across lines', () {
      expect(
        cleanExcerptText(
          'System One models choose an agent’s next ac-\ntion by scoring',
        ),
        'System One models choose an agent’s next action by scoring',
      );
    });

    test('removes PDFium hyphenation marker U+0002 and soft hyphens', () {
      expect(cleanExcerptText('next ac\u0002tion by'), 'next action by');
      expect(cleanExcerptText('next ac\u0002\ntion by'), 'next action by');
      expect(cleanExcerptText('deci\u00ADsion'), 'decision');
    });

    test('joins Latin lines with a single space', () {
      expect(
        cleanExcerptText(
          'scoring a supplied set of options in a\nsingle pass.',
        ),
        'scoring a supplied set of options in a single pass.',
      );
    });

    test('keeps en dashes, section signs and capitalised hyphen words', () {
      expect(
        cleanExcerptText('73–85% of decision errors (§5.1). Self-\nAttention'),
        '73–85% of decision errors (§5.1). Self-Attention',
      );
    });

    test('joins CJK lines without a space', () {
      expect(
        cleanExcerptText('在总学习时间相同的条件下，把学习分\n散到多个时段'),
        '在总学习时间相同的条件下，把学习分散到多个时段',
      );
    });

    test('collapses whitespace and trims', () {
      expect(
        cleanExcerptText('  U1D0  does\n\n not   show '),
        'U1D0 does not show',
      );
    });
  });

  group('defaultCardTitle', () {
    test('English: first words of the first sentence', () {
      expect(
        defaultCardTitle(
          'System One models choose an agent’s next action by scoring options.',
        ),
        'System One models choose an agent’s…',
      );
    });

    test('Chinese: first characters up to the first punctuation', () {
      expect(defaultCardTitle('间隔效应指：在总学习时间相同的条件下'), '间隔效应指');
      expect(
        defaultCardTitle('在总学习时间相同的条件下把学习分散到多个时段比集中在一个时段学习'),
        '在总学习时间相同的条件下把学习分…',
      );
    });

    test('empty text', () => expect(defaultCardTitle('  '), '摘录'));
  });

  group('placeCards', () {
    MCard card(String id) => MCard(
      id: id,
      docId: 'd',
      title: id,
      text: '',
      color: ExcerptColor.definition,
      rects: const [],
    );

    test('cards sit at their source height and never overlap', () {
      final placed = placeCards([
        (card('b'), const Rect.fromLTWH(0, 120, 10, 10)),
        (card('a'), const Rect.fromLTWH(0, 100, 10, 10)),
        (card('c'), const Rect.fromLTWH(0, 400, 10, 10)),
      ]);
      expect(placed.map((p) => p.card.id), ['a', 'b', 'c']);
      expect(placed[0].top, 100);
      expect(placed[1].top, 100 + marginCardHeight + marginGap);
      expect(placed[2].top, 400);
      for (final p in placed) {
        expect(p.top, greaterThanOrEqualTo(p.source.top));
      }
    });
  });

  group('StudyStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('mnote_store_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'create set, import PDF, cards, move, delete with undo, reload',
      () async {
        final store = await StudyStore.open(dir);
        final set = await store.createSet('Agent 决策失败');
        final src = File('${dir.path}/paper.pdf')
          ..writeAsBytesSync(List.filled(16, 1));
        final doc = await store.importPdf(set, src.path, pageCount: 33);
        expect(store.docFile(set, doc).existsSync(), isTrue);

        final a = store.addCard(
          set,
          MCard(
            id: 'a',
            docId: doc.id,
            title: 'System One 模型',
            text: 't',
            color: ExcerptColor.definition,
            rects: const [PageRect(1, 50, 700, 290, 690)],
          ),
        );
        final b = store.addCard(
          set,
          MCard(
            id: 'b',
            docId: doc.id,
            title: 'evidence',
            text: 't',
            color: ExcerptColor.evidence,
            rects: const [PageRect(2, 310, 500, 560, 490)],
          ),
        );
        store.addCard(
          set,
          MCard(
            id: 'h',
            docId: doc.id,
            title: 'hl',
            text: 't',
            color: ExcerptColor.pitfall,
            rects: const [PageRect(3, 1, 2, 3, 1)],
            highlightOnly: true,
          ),
        );
        expect(set.childrenOf(null).map((c) => c.id), ['a', 'b']);
        expect(
          set.mapCards.length,
          2,
          reason: 'highlight-only is not in the map',
        );

        expect(store.moveCard(set, b, a.id), isTrue);
        expect(set.childrenOf(a.id).single.id, 'b');
        expect(
          store.moveCard(set, a, b.id),
          isFalse,
          reason: 'cannot move into own subtree',
        );

        final undo = store.deleteCard(set, a);
        expect(set.cardById('a'), isNull);
        expect(b.parentId, isNull, reason: 'children move up');
        undo();
        expect(set.cardById('a'), isNotNull);
        expect(b.parentId, 'a');

        doc.lastPage = 13;
        await store.saveNow(set);
        final reloaded = await StudyStore.open(dir);
        final s2 = reloaded.byId(set.id)!;
        expect(s2.name, 'Agent 决策失败');
        expect(s2.docs.single.pageCount, 33);
        expect(s2.docs.single.lastPage, 13);
        expect(s2.cardById('b')!.parentId, 'a');
        expect(s2.cardById('a')!.rects.single.page, 1);
        expect(s2.cardById('h')!.highlightOnly, isTrue);
        expect(s2.cardById('b')!.pageLabel, 'p.2');
      },
    );
  });
}
