import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/mnote/ai/ai_settings_page.dart';
import 'package:saber/mnote/import/url_import.dart';

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
  String? openError;

  void _open() {
    setState(() => openError = null);
    StudyStore.instance().then(
      (s) {
        if (mounted) setState(() => store = s);
      },
      onError: (Object e) {
        if (mounted) setState(() => openError = '$e');
      },
    );
  }

  Widget _openFailed(MnotePalette p) => ColoredBox(
    color: p.board,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, size: 40, color: p.ink3),
            const SizedBox(height: 12),
            Text(
              openError!,
              key: const ValueKey('store-open-error'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: p.ink),
            ),
            const SizedBox(height: 8),
            Text(
              '请确认 mNote 可以写入这个文件夹（权限、磁盘空间、安全软件）。',
              style: TextStyle(fontSize: 13, color: p.ink3),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('store-retry'),
              style: FilledButton.styleFrom(backgroundColor: p.accent),
              onPressed: _open,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _saveErrorBar(MnotePalette p, StudyStore s) => Material(
    key: const ValueKey('save-error-bar'),
    color: const Color(0xFFF6DCD6),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: Color(0xFF9C2F1E)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.saveError.value!,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6E1F12)),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            iconSize: 18,
            onPressed: () => s.saveError.value = null,
            icon: const Icon(Icons.close, color: Color(0xFF6E1F12)),
          ),
        ],
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.store != null) {
      store = widget.store;
    } else {
      _open();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MnoteThemed(
      child: Builder(
        builder: (context) {
          final p = MnotePalette.of(context);
          final s = store;
          if (s == null && openError != null) return _openFailed(p);
          if (s == null)
            return ColoredBox(
              color: p.board,
              child: const Center(child: CircularProgressIndicator()),
            );
          return ListenableBuilder(
            listenable: Listenable.merge([s, s.saveError]),
            builder: (context, _) => Column(
              children: [
                if (s.saveError.value != null) _saveErrorBar(p, s),
                Expanded(child: _content(context, s, p)),
              ],
            ),
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
                OutlinedButton.icon(
                  key: const ValueKey('btn-ai-settings'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AiSettingsPage(),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('AI 服务'),
                ),
                const SizedBox(width: 12),
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
    final StudySet set;
    try {
      set = await s.createSet(name);
    } on StoreAccessException catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('store-error'),
          title: const Text('无法新建学习集'),
          content: Text('${e.message}\n\n请确认 mNote 可以写入这个文件夹（权限、磁盘空间、安全软件）。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
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
                    key: const ValueKey('btn-set-ai'),
                    tooltip: set.aiDisabled
                        ? '本学习集已关闭 AI（点击打开）'
                        : '本学习集使用 AI（点击关闭）',
                    icon: Icon(
                      set.aiDisabled
                          ? Icons.block
                          : Icons.auto_awesome_outlined,
                    ),
                    onPressed: () {
                      set.aiDisabled = !set.aiDisabled;
                      store.touch(set);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            set.aiDisabled
                                ? '这个学习集不再使用 AI：选中文字时的翻译、解释不会发送任何内容'
                                : '这个学习集可以使用 AI 翻译和解释',
                          ),
                        ),
                      );
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
                onPressed: () => _chooseImport(context),
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
                                '${set.cards.where((c) => c.docId == d.id && !c.highlightOnly).length} 张卡片'
                                '${d.sourceUrl == null ? '' : '\n来自 ${_shortSource(d.sourceUrl!)}'}',
                                key: ValueKey('doc-subtitle-${d.id}'),
                                style: TextStyle(color: p.ink3),
                              ),
                              isThreeLine: d.sourceUrl != null,
                              // Long-press to rename (e.g. a title taken from a link).
                              onLongPress: () => _docMenu(context, d),
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

  static String _shortSource(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return url;
    final path = u.path.length > 40 ? '${u.path.substring(0, 40)}…' : u.path;
    return '${u.host}$path';
  }

  Future<void> _docMenu(BuildContext context, StudyDoc d) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                d.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              key: const ValueKey('doc-rename'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              key: const ValueKey('doc-delete'),
              leading: const Icon(
                Icons.delete_outline,
                color: Color(0xFFB03A2E),
              ),
              title: const Text(
                '删除文档',
                style: TextStyle(color: Color(0xFFB03A2E)),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'rename') {
      await _renameDoc(context, d);
    } else if (choice == 'delete') {
      await _deleteDoc(context, d);
    }
  }

  Future<void> _deleteDoc(BuildContext context, StudyDoc d) async {
    final cards = set.cards
        .where((c) => c.docId == d.id && !c.highlightOnly)
        .length;
    final highlights = set.cards
        .where((c) => c.docId == d.id && c.highlightOnly)
        .length;
    final notes = set.aiNotes.where((n) => n.docId == d.id).length;
    final hasInk = store.inkFile(set, d).existsSync();
    final parts = [
      if (cards > 0) '$cards 张卡片',
      if (highlights > 0) '$highlights 处高亮',
      if (hasInk) '手写笔迹',
      if (notes > 0) '$notes 个翻译 / 解释',
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('doc-delete-confirm'),
        title: Text('删除「${d.title}」？'),
        content: Text(
          parts.isEmpty
              ? '会删除这份 PDF。'
              : '会删除这份 PDF，以及从它摘录的${parts.join('、')}。其他文档的卡片保留（原来挂在被删卡片下的会上移一级）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('doc-delete-ok'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB03A2E),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    const grace = Duration(seconds: 8);
    final undo = store.deleteDoc(set, d, grace: grace);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已删除「${d.title}」'),
          duration: grace - const Duration(milliseconds: 500),
          persist: false,
          action: SnackBarAction(
            key: const ValueKey('doc-undo'),
            label: '撤销',
            onPressed: undo,
          ),
        ),
      );
  }

  Future<void> _renameDoc(BuildContext context, StudyDoc d) async {
    final name = await promptText(context, title: '重命名文档', initial: d.title);
    if (name == null || name.trim().isEmpty) return;
    d.title = name.trim();
    store.touch(set);
  }

  Future<void> _chooseImport(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('import-local'),
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('从本机选择'),
              onTap: () => Navigator.pop(ctx, 'local'),
            ),
            ListTile(
              key: const ValueKey('import-url'),
              leading: const Icon(Icons.link),
              title: const Text('从网络链接'),
              subtitle: const Text('粘贴 PDF 或 arXiv 论文页的链接'),
              onTap: () => Navigator.pop(ctx, 'url'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'local') {
      await _import(context);
    } else if (choice == 'url') {
      await _importUrl(context);
    }
  }

  Future<void> _importUrl(BuildContext context) async {
    // Prefill with a link from the clipboard, if there is one.
    String? clip;
    try {
      clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    } catch (_) {}
    if (!context.mounted) return;
    final prefill =
        (clip != null &&
            RegExp(
              r'^(https?://|arxiv\.org/)',
              caseSensitive: false,
            ).hasMatch(clip))
        ? clip
        : '';
    final url = await showDialog<Uri>(
      context: context,
      builder: (_) => _UrlDialog(initial: prefill),
    );
    if (url == null || !context.mounted) return;

    final cancel = DownloadCancelToken();
    final progress = ValueNotifier<(int, int?)>((0, null));
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('url-progress'),
        title: const Text('正在下载'),
        content: ValueListenableBuilder<(int, int?)>(
          valueListenable: progress,
          builder: (_, v, _) {
            final (got, total) = v;
            String mb(int b) => (b / (1024 * 1024)).toStringAsFixed(1);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(url.host, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: total == null || total == 0 ? null : got / total,
                ),
                const SizedBox(height: 8),
                Text(
                  total == null
                      ? '已下载 ${mb(got)} MB'
                      : '已下载 ${mb(got)} / ${mb(total)} MB',
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            key: const ValueKey('url-cancel'),
            onPressed: cancel.cancel,
            child: const Text('取消'),
          ),
        ],
      ),
    );

    StudyDoc? doc;
    String? error;
    var cancelled = false;
    try {
      final tmpDir = Directory(
        '${(await getTemporaryDirectory()).path}/mnote-downloads',
      );
      final got = await downloadPdf(
        url,
        tempDir: tmpDir,
        cancel: cancel,
        onProgress: (r, t) => progress.value = (r, t),
      );
      try {
        var pages = 0;
        try {
          final pdf = await PdfDocument.openFile(got.file.path);
          pages = pdf.pages.length;
          await pdf.dispose();
        } catch (_) {
          throw UrlImportException('下载的文件已损坏或无法打开');
        }
        doc = await store.importPdf(
          set,
          got.file.path,
          title: got.title,
          pageCount: pages,
          sourceUrl: got.url.toString(),
        );
      } finally {
        if (got.file.existsSync()) await got.file.delete();
      }
    } on UrlImportCancelled {
      cancelled = true;
    } on UrlImportException catch (e) {
      error = e.message;
    } catch (e) {
      error = '下载失败：$e';
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await dialog;
    if (!context.mounted) return;
    if (cancelled) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已取消下载')));
    } else if (error != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('url-error'),
          title: const Text('无法导入'),
          content: Text(error!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } else if (doc != null) {
      await openDoc(context, doc);
    }
  }

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

/// Asks for a link; returns the normalized URL (see [normalizePdfUrl]).
class _UrlDialog extends StatefulWidget {
  const new({required this.initial});
  final String initial;

  @override
  State<_UrlDialog> createState() => _UrlDialogState();
}

class _UrlDialogState extends State<_UrlDialog> {
  late final controller = TextEditingController(text: widget.initial);
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _ok() {
    try {
      Navigator.pop(context, normalizePdfUrl(controller.text));
    } on UrlImportException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('从网络链接导入'),
      content: SizedBox(
        width: 480,
        child: TextField(
          key: const ValueKey('url-field'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'https://… 或 arxiv.org/abs/…',
            helperText: 'arXiv 论文页的链接会自动换成 PDF',
            errorText: error,
          ),
          onSubmitted: (_) => _ok(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('url-ok'),
          onPressed: _ok,
          child: const Text('下载'),
        ),
      ],
    );
  }
}
