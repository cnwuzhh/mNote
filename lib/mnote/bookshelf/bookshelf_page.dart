import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/workspace_page.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// Home tab: list of study sets.
class BookshelfPage extends StatefulWidget {
  const new({super.key, this.store});

  /// Injected in tests; otherwise [StudyStore.instance] is used.
  final StudyStore? store;

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  StudyStore? store;

  @override
  void initState() {
    super.initState();
    if (widget.store != null) {
      store = widget.store;
    } else {
      StudyStore.instance().then((s) {
        if (mounted) setState(() => store = s);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MnoteThemed(
      child: Builder(
        builder: (context) {
          final p = MnotePalette.of(context);
          final s = store;
          if (s == null)
            return ColoredBox(
              color: p.board,
              child: const Center(child: CircularProgressIndicator()),
            );
          return ListenableBuilder(
            listenable: s,
            builder: (context, _) => _content(context, s, p),
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, StudyStore s, MnotePalette p) {
    final sets = s.sets;
    final docCount = sets.fold<int>(0, (n, x) => n + x.docs.length);
    return ColoredBox(
      color: p.board,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '学习集',
                      style: serifStyle(
                        p.ink,
                        size: 32,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${sets.length} 个学习集，$docCount 份文档',
                      style: TextStyle(fontSize: 14, color: p.ink3),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const ValueKey('btn-new-set'),
                  style: FilledButton.styleFrom(backgroundColor: p.accent),
                  onPressed: () => _newSet(context, s),
                  icon: const Icon(Icons.add),
                  label: const Text('新建学习集'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (sets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: Text(
                    '还没有学习集。新建一个，再把 PDF 导进去开始阅读和摘录。',
                    style: TextStyle(fontSize: 15, color: p.ink3),
                  ),
                ),
              ),
            for (final set in sets) _SetRow(store: s, set: set),
          ],
        ),
      ),
    );
  }

  Future<void> _newSet(BuildContext context, StudyStore s) async {
    final name = await promptText(
      context,
      title: '新建学习集',
      hint: '例如：Agent 决策失败',
    );
    if (name == null) return;
    final set = await s.createSet(name);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudySetPage(store: s, set: set),
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const new({required this.store, required this.set});

  final StudyStore store;
  final StudySet set;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    final cards = set.mapCards.length;
    final progress = set.docs.isEmpty
        ? 0.0
        : set.docs.map((d) => d.progress).reduce((a, b) => a + b) /
              set.docs.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: p.paper,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('set-${set.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StudySetPage(store: store, set: set),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 58,
                  decoration: BoxDecoration(
                    color: p.paper2,
                    border: Border.all(color: p.line),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.menu_book_outlined, color: p.ink3),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        set.name,
                        style: serifStyle(
                          p.ink,
                          size: 18,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        set.docs.isEmpty
                            ? '还没有文档'
                            : set.docs.map((d) => d.title).join('、'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: p.ink2),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 160,
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              color: p.accent,
                              backgroundColor: p.line,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '已读 ${(progress * 100).round()}%',
                            style: TextStyle(fontSize: 12, color: p.ink3),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$cards',
                      style: serifStyle(
                        p.ink,
                        size: 22,
                        weight: FontWeight.w600,
                      ),
                    ),
                    Text('张卡片', style: TextStyle(fontSize: 12, color: p.ink3)),
                  ],
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '0',
                      style: serifStyle(
                        p.ink3,
                        size: 22,
                        weight: FontWeight.w600,
                      ),
                    ),
                    Text('待复习', style: TextStyle(fontSize: 12, color: p.ink3)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A study set: its documents and an import button.
class StudySetPage extends StatelessWidget {
  const new({super.key, required this.store, required this.set});

  final StudyStore store;
  final StudySet set;

  @override
  Widget build(BuildContext context) {
    return MnoteThemed(
      child: Builder(
        builder: (context) {
          final p = MnotePalette.of(context);
          return ListenableBuilder(
            listenable: store,
            builder: (context, _) => Scaffold(
              backgroundColor: p.board,
              appBar: AppBar(
                title: Text(
                  set.name,
                  style: serifStyle(p.ink, size: 20, weight: FontWeight.w600),
                ),
                actions: [
                  IconButton(
                    tooltip: '重命名',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final n = await promptText(
                        context,
                        title: '重命名学习集',
                        initial: set.name,
                      );
                      if (n != null && n.trim().isNotEmpty) {
                        set.name = n.trim();
                        store.touch(set);
                      }
                    },
                  ),
                  IconButton(
                    tooltip: '删除学习集',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(context),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              floatingActionButton: FloatingActionButton.extended(
                key: const ValueKey('btn-import-pdf'),
                backgroundColor: p.accent,
                foregroundColor: Colors.white,
                onPressed: () => _import(context),
                icon: const Icon(Icons.upload_file),
                label: const Text('导入 PDF'),
              ),
              body: set.docs.isEmpty
                  ? Center(
                      child: Text(
                        '点右下角「导入 PDF」添加文档',
                        style: TextStyle(fontSize: 15, color: p.ink3),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          '${set.docs.length} 份文档，脑图「${set.name}」共 ${set.mapCards.length} 张卡片',
                          style: TextStyle(fontSize: 14, color: p.ink3),
                        ),
                        const SizedBox(height: 12),
                        for (final d in set.docs)
                          Card(
                            color: p.paper,
                            elevation: 0,
                            child: ListTile(
                              key: ValueKey('doc-${d.id}'),
                              leading: Icon(
                                Icons.picture_as_pdf_outlined,
                                color: p.accent,
                              ),
                              title: Text(
                                d.title,
                                style: serifStyle(
                                  p.ink,
                                  size: 16,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${d.pageCount == 0 ? '' : '${d.pageCount} 页，'}已读 ${(d.progress * 100).round()}%，'
                                '${set.cards.where((c) => c.docId == d.id && !c.highlightOnly).length} 张卡片',
                                style: TextStyle(color: p.ink3),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => openDoc(context, d),
                            ),
                          ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  Future<void> openDoc(BuildContext context, StudyDoc d) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MnoteThemed(
            child: WorkspacePage(store: store, set: set, doc: d),
          ),
        ),
      );

  Future<void> _import(BuildContext context) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = file?.path;
    if (path == null) return;
    final title = file!.name.replaceAll(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );
    var pages = 0;
    try {
      final pdf = await PdfDocument.openFile(path);
      pages = pdf.pages.length;
      await pdf.dispose();
    } catch (_) {
      // The page count is filled in when the reader opens the file.
    }
    final doc = await store.importPdf(
      set,
      path,
      title: title,
      pageCount: pages,
    );
    if (context.mounted) await openDoc(context, doc);
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除学习集？'),
        content: Text('「${set.name}」中的文档、卡片和脑图都会被删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.deleteSet(set);
    if (context.mounted) Navigator.of(context).pop();
  }
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? hint,
  String? initial,
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const ValueKey('prompt-field'),
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('prompt-ok'),
          onPressed: () => Navigator.pop(ctx, c.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
