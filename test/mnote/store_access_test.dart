import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/mnote/bookshelf/bookshelf_page.dart';
import 'package:saber/mnote/store/study_store.dart';

/// BUG-WIN-01 (Windows, 2026-11-27): the data folder could not be written;
/// 「新建学习集」 closed the dialog and nothing happened, without a word.
/// Now failures are reported and nothing half-created is shown.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('mnote_ro'));
  tearDown(() {
    Process.runSync('chmod', ['-R', 'u+rwx', dir.path]);
    dir.deleteSync(recursive: true);
  });
  // Saving is real disk IO: poll instead of a fixed delay (slow under load).
  Future<void> until(bool Function() ok) async {
    for (var i = 0; i < 100 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void readOnly(String path) =>
      expect(Process.runSync('chmod', ['0555', path]).exitCode, 0);

  test(
    'creating a set in a folder that cannot be written fails clearly',
    () async {
      final store = await StudyStore.open(dir);
      readOnly(dir.path);
      await expectLater(
        store.createSet('Agent'),
        throwsA(
          isA<StoreAccessException>().having(
            (e) => e.message,
            'message',
            allOf(startsWith('无法新建学习集：'), contains(dir.path)),
          ),
        ),
      );
      expect(store.sets, isEmpty, reason: 'not shown as if it existed');
    },
  );

  test(
    'a later save that fails is reported, and cleared once saving works again',
    () async {
      final store = await StudyStore.open(dir);
      final set = await store.createSet('S');
      final setDir = '${dir.path}/sets/${set.id}';
      readOnly(setDir);
      set.name = 'renamed';
      store.touch(set, delay: Duration.zero);
      await until(() => store.saveError.value != null);
      expect(store.saveError.value, startsWith('保存失败：'));
      Process.runSync('chmod', ['u+rwx', setDir]);
      store.touch(set, delay: Duration.zero);
      await until(() => store.saveError.value == null);
      expect(store.saveError.value, isNull);
    },
  );

  testWidgets('「新建学习集」 shows why it failed instead of closing silently', (
    tester,
  ) async {
    late StudyStore store;
    await tester.runAsync(() async {
      store = await StudyStore.open(dir);
    });
    readOnly(dir.path);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BookshelfPage(store: store)),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('btn-new-set')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('prompt-field')), 'Agent');
    await tester.tap(find.byKey(const ValueKey('prompt-ok')));
    for (
      var i = 0;
      i < 20 && find.byKey(const ValueKey('store-error')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('store-error')), findsOneWidget);
    expect(find.text('无法新建学习集'), findsOneWidget);
    expect(find.textContaining(dir.path), findsOneWidget, reason: 'says where');
    expect(store.sets, isEmpty);
  });
}
