import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/mnote/cards/card_detail_panel.dart';
import 'package:saber/mnote/export/pdf_export.dart';
import 'package:saber/mnote/ink/ink_document.dart';
import 'package:saber/mnote/ink/ink_input_layer.dart';
import 'package:saber/mnote/ink/ink_paint.dart';
import 'package:saber/mnote/mindmap/mindmap_view.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/model/text_clean.dart';
import 'package:saber/mnote/reader/excerpt_menu.dart';
import 'package:saber/mnote/reader/margin_rail.dart';
import 'package:saber/mnote/reader/mode_toolbar.dart';
import 'package:saber/mnote/reader/pdf_geometry.dart';
import 'package:saber/mnote/reader/reader_search.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

const _railWidth = 200.0;
const _mapMin = 300.0, _mapMax = 560.0, _mapCollapsed = 44.0;

/// Three-column study workspace: PDF | margin rail | mind map.
class WorkspacePage extends StatefulWidget {
  const new({
    super.key,
    required this.store,
    required this.set,
    required this.doc,
  });

  final StudyStore store;
  final StudySet set;
  final StudyDoc doc;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage>
    with WidgetsBindingObserver {
  final controller = PdfViewerController();
  late final searcher = PdfTextSearcher(controller);
  VoidCallback? _removeSearchListener;

  WorkMode mode = WorkMode.excerpt;
  ExcerptColor color = ExcerptColor.definition;
  ExcerptTool tool = ExcerptTool.text;

  /// null = automatic (open on wide screens, collapsed when narrow, e.g.
  /// portrait); set once the user toggles it.
  bool? mapOpenChoice;
  var _wide = true;
  bool get mapOpen => mapOpenChoice ?? _wide;
  double mapWidth = 424;
  var searchOpen = false;

  String? selectedId;
  String? flashNodeId;
  String? flashSourceId;
  List<PdfOutlineNode> outline = const [];

  final nodeKeys = <String, GlobalKey>{};
  final railKeys = <String, GlobalKey>{};
  final readerKey = GlobalKey();

  // Box-select (框选) state, viewer-local coordinates.
  Offset? boxStart, boxEnd;

  // Handwriting.
  InkDocument? ink;
  InkTool inkTool = InkTool.pen;
  Color penColor = penColors.first;
  Color highlighterColor = highlighterColors.first;
  InkWidth inkWidth = InkWidth.medium;
  Timer? _inkSave;

  /// Current lasso selection: page, lasso path (page space), strokes.
  (int, Path, List<Stroke>)? lassoSel;

  StudySet get set => widget.set;
  StudyDoc get doc => widget.doc;
  StudyStore get store => widget.store;

  Iterable<MCard> get docCards => set.cards.where((c) => c.docId == doc.id);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_onViewChanged);
    _removeSearchListener = searcher.addListener(_onViewChanged);
    doc.lastOpened = DateTime.now();
    store.touch(set);
    InkDocument.load(store.inkFile(set, doc)).then((d) {
      if (!mounted) return;
      d.history.addListener(_onViewChanged);
      setState(() => ink = d);
      _repaintPages();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) store.flush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_onViewChanged);
    _removeSearchListener?.call();
    searcher.dispose();
    ink?.history.removeListener(_onViewChanged);
    if (_inkSave?.isActive ?? false) {
      _inkSave!.cancel();
      ink?.save(store.inkFile(set, doc));
    }
    store.flush();
    super.dispose();
  }

  void _onViewChanged() {
    if (mounted) setState(() {});
  }

  void _repaintPages() {
    if (controller.isReady) controller.invalidate();
    setState(() {});
  }

  // ---------------- PDF callbacks ----------------

  Future<void> _onViewerReady(
    PdfDocument document,
    PdfViewerController c,
  ) async {
    if (doc.pageCount != document.pages.length) {
      doc.pageCount = document.pages.length;
      store.touch(set);
    }
    final initial = doc.lastPage.clamp(1, document.pages.length);
    if (initial > 1)
      await c.goToPage(pageNumber: initial, duration: Duration.zero);
    try {
      final o = await document.loadOutline();
      if (mounted) setState(() => outline = o);
    } catch (_) {}
  }

  void _onPageChanged(int? page) {
    if (page == null) return;
    doc.lastPage = page;
    if (page > doc.maxPageRead) doc.maxPageRead = page;
    store.touch(set, delay: const Duration(seconds: 1));
  }

  void _paintHighlights(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    final dark = MnotePalette.of(context).dark;
    for (final card in docCards) {
      final flash = card.id == flashSourceId;
      final paint = Paint()
        ..color = flash
            ? card.color.ink(dark: dark).withValues(alpha: 0.45)
            : card.color.highlight(dark: dark);
      for (final r in card.rects) {
        if (r.page != page.pageNumber) continue;
        final rect = r.toPdfRect().toRectInDocument(
          page: page,
          pageRect: pageRect,
        );
        if (card.image != null) {
          canvas.drawRect(
            rect,
            Paint()
              ..color = card.color.ink(dark: dark)
              ..style = PaintingStyle.stroke
              ..strokeWidth = flash ? 3 : 1.6,
          );
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect.inflate(1), const Radius.circular(2)),
            paint,
          );
        }
      }
    }
    final strokes = ink?.strokesOn(page.pageNumber) ?? const [];
    if (strokes.isNotEmpty) {
      final sel = lassoSel;
      canvas.save();
      canvas.translate(pageRect.left, pageRect.top);
      final k = pageRect.width / page.width;
      canvas.scale(k, k);
      paintInk(
        canvas,
        strokes,
        bounds: Rect.fromLTWH(0, 0, page.width, page.height),
        dark: dark,
        selected: sel != null && sel.$1 == page.pageNumber
            ? sel.$3.toSet()
            : const {},
        selectionColor: MnotePalette.of(context).accent,
      );
      canvas.restore();
    }
  }

  // ---------------- handwriting ----------------

  void _inkChanged() {
    _repaintPages();
    _inkSave?.cancel();
    _inkSave = Timer(const Duration(milliseconds: 600), () {
      final d = ink;
      if (d != null) d.save(store.inkFile(set, doc));
    });
  }

  void _onLasso(int page, Path path) {
    final d = ink;
    if (d == null) return;
    final hits = strokesInLasso(d, page, path);
    if (hits.isEmpty) {
      setState(() => lassoSel = null);
      _toast('没有选中笔迹');
      _repaintPages();
      return;
    }
    setState(() => lassoSel = (page, path, hits));
    _repaintPages();
  }

  void _clearLasso() {
    setState(() => lassoSel = null);
    _repaintPages();
  }

  void _deleteLasso() {
    final sel = lassoSel;
    if (sel == null) return;
    ink?.remove(sel.$1, sel.$3);
    lassoSel = null;
    _inkChanged();
  }

  /// Turns the lasso selection (and the page content under it) into an image
  /// card, like the box-select tool.
  Future<void> _lassoToCard() async {
    final sel = lassoSel;
    if (sel == null || !controller.isReady) return;
    final (pageNo, _, strokes) = sel;
    final page = controller.pages[pageNo - 1];
    var region = strokes
        .map(strokeBounds)
        .reduce((a, b) => a.expandToInclude(b))
        .inflate(8);
    region = Rect.fromLTRB(
      region.left.clamp(0, page.width),
      region.top.clamp(0, page.height),
      region.right.clamp(0, page.width),
      region.bottom.clamp(0, page.height),
    );
    if (region.width < 2 || region.height < 2) return;
    const s = 3.0;
    final base = await page.renderForDisplay(
      x: (region.left * s).round(),
      y: (region.top * s).round(),
      width: (region.width * s).round(),
      height: (region.height * s).round(),
      fullWidth: page.width * s,
      fullHeight: page.height * s,
      backgroundColor: 0xFFFFFFFF,
    );
    if (base == null) {
      _toast('截取失败');
      return;
    }
    final composed = await composeRegion(base, region, s, strokes);
    base.dispose();
    final bytes = await composed.toByteData(format: ui.ImageByteFormat.png);
    composed.dispose();
    if (bytes == null) return;
    final name = await store.saveImage(set, bytes.buffer.asUint8List());
    final card = MCard(
      id: newId(),
      docId: doc.id,
      title: '手写摘录 p.$pageNo',
      text: '',
      color: color,
      // PageRect uses PDF coordinates (origin bottom-left).
      rects: [
        PageRect(
          pageNo,
          region.left,
          page.height - region.top,
          region.right,
          page.height - region.bottom,
        ),
      ],
      image: name,
    );
    store.addCard(set, card);
    lassoSel = null;
    _repaintPages();
    _flyIn(card);
  }

  Rect? _lassoBoundsInViewer() {
    final sel = lassoSel;
    if (sel == null || !hasPageLayout(controller)) return null;
    final space = PageSpace(controller);
    final b = sel.$2.getBounds();
    final r = space.pageRectInDocument(sel.$1);
    final k = r.width / space.pageSize(sel.$1).width;
    Offset toLocal(Offset pt) => controller.documentToLocal(r.topLeft + pt * k);
    return Rect.fromPoints(toLocal(b.topLeft), toLocal(b.bottomRight));
  }

  Future<void> _export() async {
    if (!controller.isReady) return;
    final progress = ValueNotifier<(int, int)>((0, controller.pageCount));
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Theme(
        data: theme,
        child: AlertDialog(
          title: const Text('导出带批注的 PDF'),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (_, v, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: v.$2 == 0 ? null : v.$1 / v.$2),
                const SizedBox(height: 12),
                Text('第 ${v.$1} / ${v.$2} 页'),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final bytes = await exportAnnotatedPdf(
        document: controller.document,
        cards: docCards.toList(),
        ink: ink ?? InkDocument(),
        onProgress: (d, t) => progress.value = (d, t),
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final safeTitle = doc.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      await FileManager.exportFile(
        '${safeTitle}_mNote.pdf',
        bytes,
        context: context,
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _toast('导出失败：$e');
      }
    }
  }

  Widget? _buildMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    final d = params.textSelectionDelegate;
    if (!params.isTextSelectionEnabled || !d.hasSelectedText) return null;
    if (mode != WorkMode.excerpt) return null;
    final menu = ExcerptMenu(
      initialColor: color,
      onAction: (action, c) async {
        params.dismissContextMenu();
        await _excerptSelection(d, action, c);
      },
    );
    return Align(
      alignment: Alignment.topLeft,
      child: CustomSingleChildLayout(
        delegate: _MenuLayout(anchor: params.anchorA),
        child: Theme(data: Theme.of(this.context), child: menu),
      ),
    );
  }

  // ---------------- excerpt ----------------

  Future<void> _excerptSelection(
    PdfTextSelectionDelegate d,
    ExcerptAction action,
    ExcerptColor c,
  ) async {
    if (action == ExcerptAction.copy) {
      await d.copyTextSelection();
      await d.clearTextSelection();
      _toast('已复制');
      return;
    }
    final ranges = await d.getSelectedTextRanges();
    final raw = await d.getSelectedText();
    final rects = lineRectsForRanges(ranges);
    if (rects.isEmpty) return;
    final text = cleanExcerptText(raw);
    final card = MCard(
      id: newId(),
      docId: doc.id,
      title: defaultCardTitle(text),
      text: text,
      color: c,
      rects: rects,
      highlightOnly:
          action == ExcerptAction.highlight || tool == ExcerptTool.highlight,
    );
    color = c;
    store.addCard(set, card);
    await d.clearTextSelection();
    _repaintPages();
    if (!card.highlightOnly) _flyIn(card);
  }

  Future<void> _finishBox() async {
    final a = boxStart, b = boxEnd;
    setState(() => boxStart = boxEnd = null);
    if (a == null || b == null || (a - b).distance < 12) return;
    final ha = controller.getPdfPageHitTestResult(
      a,
      useDocumentLayoutCoordinates: false,
    );
    final hb = controller.getPdfPageHitTestResult(
      b,
      useDocumentLayoutCoordinates: false,
    );
    if (ha == null || hb == null || ha.page.pageNumber != hb.page.pageNumber) {
      _toast('框选需在同一页内');
      return;
    }
    final page = ha.page;
    final l = ha.offset.x < hb.offset.x ? ha.offset.x : hb.offset.x;
    final r = ha.offset.x > hb.offset.x ? ha.offset.x : hb.offset.x;
    final t = ha.offset.y > hb.offset.y ? ha.offset.y : hb.offset.y;
    final bt = ha.offset.y < hb.offset.y ? ha.offset.y : hb.offset.y;
    const s = 3.0;
    final img = await page.renderForDisplay(
      x: (l * s).round(),
      y: ((page.height - t) * s).round(),
      width: ((r - l) * s).round(),
      height: ((t - bt) * s).round(),
      fullWidth: page.width * s,
      fullHeight: page.height * s,
      backgroundColor: 0xFFFFFFFF,
    );
    if (img == null) {
      _toast('截取失败');
      return;
    }
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (bytes == null) return;
    final name = await store.saveImage(set, bytes.buffer.asUint8List());
    final card = MCard(
      id: newId(),
      docId: doc.id,
      title: '图片摘录 p.${page.pageNumber}',
      text: '',
      color: color,
      rects: [PageRect(page.pageNumber, l, t, r, bt)],
      image: name,
    );
    store.addCard(set, card);
    _repaintPages();
    _flyIn(card);
  }

  /// Animates a ghost card from the margin rail into its mind-map node,
  /// then flashes the node.
  void _flyIn(MCard card) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final overlay = Overlay.of(context);
      final overlayBox = overlay.context.findRenderObject() as RenderBox?;
      Rect? rectOf(GlobalKey? k) {
        final box = k?.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.attached || overlayBox == null) return null;
        final tl = box.localToGlobal(Offset.zero, ancestor: overlayBox);
        return tl & box.size;
      }

      final start = rectOf(railKeys[card.id]);
      final end = mapOpen ? rectOf(nodeKeys[card.id]) : null;
      if (start == null || end == null) {
        _flash(card.id);
        return;
      }
      final p = MnotePalette.of(context);
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (_) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 720),
          curve: Curves.easeInOutCubic,
          onEnd: () {
            entry.remove();
            _flash(card.id);
          },
          builder: (context, t, _) {
            // Quadratic Bézier with the control point above the midpoint.
            final c = Offset(
              (start.center.dx + end.center.dx) / 2,
              start.center.dy - 120,
            );
            final pt = Offset.lerp(
              Offset.lerp(start.center, c, t)!,
              Offset.lerp(c, end.center, t)!,
              t,
            )!;
            final size = Size.lerp(start.size, end.size, t)!;
            return Positioned(
              left: pt.dx - size.width / 2,
              top: pt.dy - size.height / 2,
              width: size.width,
              height: size.height,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 1 - t * 0.3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: card.color.ink(dark: p.dark),
                        width: 1.5,
                      ),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 14),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      overlay.insert(entry);
    });
  }

  void _flash(String id) {
    if (!mounted) return;
    setState(() => flashNodeId = id);
    Timer(const Duration(milliseconds: 900), () {
      if (mounted && flashNodeId == id) setState(() => flashNodeId = null);
    });
  }

  Future<void> _jumpTo(MCard card) async {
    if (card.docId != doc.id) {
      _toast('这张卡片来自另一份文档');
      return;
    }
    setState(() {
      selectedId = card.id;
      flashSourceId = card.id;
    });
    await goToCard(controller, card);
    _repaintPages();
    Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || flashSourceId != card.id) return;
      flashSourceId = null;
      _repaintPages();
    });
  }

  void _moveCard(MCard card, String? parentId) {
    if (store.moveCard(set, card, parentId)) setState(() {});
  }

  Future<void> _openCard(MCard card) async {
    setState(() => selectedId = card.id);
    final theme = Theme.of(context);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black26,
      pageBuilder: (ctx, _, _) => Align(
        alignment: Alignment.centerRight,
        child: Theme(
          data: theme,
          child: Material(
            color: MnotePalette.of(context).paper,
            elevation: 12,
            child: SafeArea(
              child: SizedBox(
                width: 440,
                child: CardDetailPanel(
                  key: ValueKey(card.id),
                  store: store,
                  set: set,
                  card: card,
                  onJump: () {
                    Navigator.of(ctx).pop();
                    _jumpTo(card);
                  },
                  onDelete: () {
                    Navigator.of(ctx).pop();
                    _deleteCard(card);
                  },
                  onOpenCard: (c) {
                    Navigator.of(ctx).pop();
                    _openCard(c);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Colour or other edits in the panel change highlights: repaint pages.
    if (mounted) _repaintPages();
  }

  void _deleteCard(MCard card) {
    final undo = store.deleteCard(set, card);
    _repaintPages();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已删除「${card.title}」及其高亮'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              undo();
              _repaintPages();
            },
          ),
        ),
      );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _showOutline() async {
    if (outline.isEmpty) {
      _toast('这份文档没有目录书签');
      return;
    }
    final theme = Theme.of(context);
    final p = MnotePalette.of(context);
    final dest = await showModalBottomSheet<PdfDest?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.paper,
      builder: (ctx) => Theme(
        data: theme,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (ctx, sc) => ListView(
            controller: sc,
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  '目录',
                  style: serifStyle(p.ink, size: 20, weight: FontWeight.w600),
                ),
              ),
              for (final (node, depth) in _flatten(outline))
                ListTile(
                  dense: depth > 0,
                  contentPadding: EdgeInsets.only(
                    left: 20.0 + depth * 18,
                    right: 20,
                  ),
                  title: Text(
                    node.title,
                    style: serifStyle(
                      depth == 0 ? p.ink : p.ink2,
                      size: depth == 0 ? 16 : 15,
                    ),
                  ),
                  trailing: node.dest == null
                      ? null
                      : Text(
                          '${node.dest!.pageNumber}',
                          style: TextStyle(color: p.ink3, fontSize: 13),
                        ),
                  onTap: () => Navigator.of(ctx).pop(node.dest),
                ),
            ],
          ),
        ),
      ),
    );
    if (dest != null) await controller.goToDest(dest);
  }

  Iterable<(PdfOutlineNode, int)> _flatten(
    List<PdfOutlineNode> nodes, [
    int depth = 0,
  ]) sync* {
    for (final n in nodes) {
      yield (n, depth);
      yield* _flatten(n.children, depth + 1);
    }
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    _wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      backgroundColor: p.board,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(p),
            Divider(height: 1, color: p.line),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _reader(p)),
                  _splitter(p),
                  _mapPanel(p),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(MnotePalette p) {
    final page = controller.isReady
        ? (controller.pageNumber ?? doc.lastPage)
        : doc.lastPage;
    final total = doc.pageCount;
    final TextStyle small = TextStyle(fontSize: 12, color: p.ink3);
    final TextStyle value = TextStyle(
      fontSize: 15,
      color: p.ink,
      fontWeight: FontWeight.w600,
    );
    Widget crumb(String label, String v) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: small),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(v, style: value, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    Widget sep() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text('/', style: TextStyle(color: p.line, fontSize: 18)),
    );
    return Container(
      color: p.paper,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            icon: Icon(Icons.arrow_back, color: p.ink2),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  crumb('学习集', set.name),
                  sep(),
                  crumb('文档', doc.title),
                  sep(),
                  crumb('脑图', set.name),
                ],
              ),
            ),
          ),
          Text(
            total == 0
                ? ''
                : '第 $page / $total 页，已读 ${(doc.progress * 100).round()}%',
            key: const ValueKey('page-indicator'),
            style: TextStyle(fontSize: 14, color: p.ink2),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const ValueKey('btn-outline'),
            tooltip: '目录',
            icon: Icon(Icons.toc, color: p.ink2),
            onPressed: _showOutline,
          ),
          IconButton(
            key: const ValueKey('btn-search'),
            tooltip: '搜索',
            icon: Icon(Icons.search, color: searchOpen ? p.accent : p.ink2),
            onPressed: () => setState(() {
              searchOpen = !searchOpen;
              if (!searchOpen) searcher.resetTextSearch();
            }),
          ),
          IconButton(
            key: const ValueKey('btn-export'),
            tooltip: '导出',
            icon: Icon(Icons.ios_share, color: p.ink2),
            onPressed: _export,
          ),
          IconButton(
            key: const ValueKey('btn-night'),
            tooltip: p.dark ? '日间' : '夜读',
            icon: Icon(
              p.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: p.ink2,
            ),
            onPressed: () {
              mnoteNight.value = !mnoteNight.value;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _repaintPages(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _reader(MnotePalette p) {
    final file = store.docFile(set, doc);
    return LayoutBuilder(
      builder: (context, cons) {
        final viewW = cons.maxWidth - _railWidth;
        final placed = hasPageLayout(controller)
            ? layoutMarginCards(
                controller,
                set.mapCards.where((c) => c.docId == doc.id),
                viewHeight: cons.maxHeight,
              )
            : const <PlacedCard>[];
        return Stack(
          key: readerKey,
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: viewW,
              child: ColoredBox(
                color: p.gap,
                child: PdfViewer.file(
                  file.path,
                  controller: controller,
                  params: PdfViewerParams(
                    backgroundColor: p.gap,
                    pageImageColorFilter: p.dark
                        ? const ColorFilter.matrix([
                            -0.86, 0, 0, 0, 236, //
                            0, -0.86, 0, 0, 229,
                            0, 0, -0.86, 0, 216,
                            0, 0, 0, 1, 0,
                          ])
                        : null,
                    textSelectionParams: PdfTextSelectionParams(
                      enabled:
                          mode == WorkMode.excerpt && tool != ExcerptTool.box,
                    ),
                    buildContextMenu: _buildMenu,
                    pagePaintCallbacks: [
                      _paintHighlights,
                      searcher.pageTextMatchPaintCallback,
                    ],
                    onViewerReady: _onViewerReady,
                    onPageChanged: _onPageChanged,
                  ),
                ),
              ),
            ),
            // Margin rail.
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _railWidth,
              child: ClipRect(
                child: ColoredBox(
                  color: p.paper,
                  child: Stack(
                    children: [
                      if (placed.isEmpty)
                        Positioned(
                          left: 14,
                          right: 14,
                          top: 20,
                          child: Text(
                            '在左侧选中文字，选颜色后「摘录为卡片」，卡片会停在原文同一高度。',
                            style: TextStyle(
                              fontSize: 14,
                              color: p.ink3,
                              height: 1.6,
                            ),
                          ),
                        ),
                      for (final pc in placed)
                        Positioned(
                          key: ValueKey('rail-${pc.card.id}'),
                          left: 10,
                          right: 10,
                          top: pc.top,
                          child: MarginCardTile(
                            key: railKeys.putIfAbsent(
                              pc.card.id,
                              GlobalKey.new,
                            ),
                            card: pc.card,
                            selected: pc.card.id == selectedId,
                            onTap: () => _openCard(pc.card),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Lead lines across viewer and rail.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: LeadLinePainter(
                    placed: placed,
                    railLeft: viewW + 10,
                    dark: p.dark,
                  ),
                ),
              ),
            ),
            if (mode == WorkMode.handwrite && ink != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: viewW,
                child: InkInputLayer(
                  key: const ValueKey('ink-layer'),
                  controller: controller,
                  ink: ink!,
                  tool: inkTool,
                  color: inkTool == InkTool.highlighter
                      ? highlighterColor
                      : penColor,
                  width: inkWidth,
                  fingerDrawing: store.fingerDrawing,
                  dark: p.dark,
                  onChanged: _inkChanged,
                  onLasso: _onLasso,
                ),
              ),
            if (lassoSel != null) ..._lassoMenu(p, viewW),
            if (mode == WorkMode.excerpt && tool == ExcerptTool.box)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: viewW,
                child: GestureDetector(
                  key: const ValueKey('box-select-layer'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) =>
                      setState(() => boxStart = boxEnd = d.localPosition),
                  onPanUpdate: (d) => setState(() => boxEnd = d.localPosition),
                  onPanEnd: (_) => _finishBox(),
                  child: CustomPaint(
                    painter: _BoxPainter(
                      boxStart,
                      boxEnd,
                      color.ink(dark: p.dark),
                    ),
                  ),
                ),
              ),
            if (searchOpen)
              Positioned(
                top: 12,
                right: _railWidth + 12,
                width: 360,
                child: ReaderSearchPanel(
                  searcher: searcher,
                  onClose: () => setState(() {
                    searchOpen = false;
                    searcher.resetTextSearch();
                  }),
                ),
              ),
            Positioned(
              left: 16,
              bottom: 16,
              right: _railWidth + 16,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: ModeToolbar(
                  ink: ink == null
                      ? null
                      : InkControls(
                          tool: inkTool,
                          onTool: (t) {
                            setState(() => inkTool = t);
                            if (lassoSel != null) _clearLasso();
                          },
                          color: inkTool == InkTool.highlighter
                              ? highlighterColor
                              : penColor,
                          onColor: (c) => setState(() {
                            if (inkTool == InkTool.highlighter) {
                              highlighterColor = c;
                            } else {
                              penColor = c;
                            }
                          }),
                          width: inkWidth,
                          onWidth: (w) => setState(() => inkWidth = w),
                          canUndo: ink!.history.canUndo,
                          canRedo: ink!.history.canRedo,
                          onUndo: () {
                            if (ink!.undo()) _inkChanged();
                          },
                          onRedo: () {
                            if (ink!.redo()) _inkChanged();
                          },
                          fingerDrawing: store.fingerDrawing,
                          onFingerDrawing: (v) =>
                              setState(() => store.fingerDrawing = v),
                        ),
                  mode: mode,
                  onMode: (m) {
                    setState(() => mode = m);
                    if (m == WorkMode.organize || m == WorkMode.recall) {
                      _toast('「${m.label}」模式将在后续版本提供');
                    }
                    if (m != WorkMode.handwrite && lassoSel != null)
                      _clearLasso();
                  },
                  color: color,
                  onColor: (c) => setState(() => color = c),
                  tool: tool,
                  onTool: (t) {
                    setState(() => tool = t);
                    if (t == ExcerptTool.box) _toast('在页面上拖出一个矩形来截取区域');
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _lassoMenu(MnotePalette p, double viewW) {
    final b = _lassoBoundsInViewer();
    if (b == null) return const [];
    final top = (b.top - 56).clamp(8.0, double.infinity);
    final left = b.left.clamp(8.0, (viewW - 330).clamp(8.0, double.infinity));
    Widget btn(
      String key,
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? fill,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: fill ?? Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return [
      Positioned(
        left: left,
        top: top,
        child: Material(
          color: const Color(0xFF2A251E),
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                btn(
                  'lasso-to-card',
                  Icons.note_add_outlined,
                  '摘录为卡片',
                  _lassoToCard,
                  fill: p.accent,
                ),
                btn('lasso-delete', Icons.delete_outline, '删除', _deleteLasso),
                btn('lasso-cancel', Icons.close, '取消', _clearLasso),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _splitter(MnotePalette p) {
    if (!mapOpen) return VerticalDivider(width: 1, color: p.line);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const ValueKey('map-splitter'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => setState(
          () => mapWidth = (mapWidth - d.delta.dx).clamp(_mapMin, _mapMax),
        ),
        child: Container(
          width: 12,
          color: p.paper,
          alignment: Alignment.center,
          child: Container(
            width: 4,
            height: 44,
            decoration: BoxDecoration(
              color: p.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mapPanel(MnotePalette p) {
    if (!mapOpen) {
      return Container(
        width: _mapCollapsed,
        color: p.paper,
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 8),
        child: IconButton(
          key: const ValueKey('map-expand'),
          tooltip: '展开脑图',
          icon: Icon(Icons.account_tree_outlined, color: p.ink2),
          onPressed: () => setState(() => mapOpenChoice = true),
        ),
      );
    }
    final count = set.mapCards.length;
    return Container(
      width: mapWidth,
      color: p.paper,
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Text('脑图', style: TextStyle(fontSize: 13, color: p.ink3)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${set.name}，$count 张卡片',
                    overflow: TextOverflow.ellipsis,
                    style: serifStyle(p.ink, size: 15, weight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  key: const ValueKey('map-collapse'),
                  tooltip: '收起脑图',
                  icon: Icon(Icons.last_page, color: p.ink2),
                  onPressed: () => setState(() => mapOpenChoice = false),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.line),
          Expanded(
            child: MindMapView(
              set: set,
              nodeKeys: nodeKeys,
              flashId: flashNodeId,
              selectedId: selectedId,
              onOpen: _openCard,
              onJump: _jumpTo,
              onMove: _moveCard,
            ),
          ),
        ],
      ),
    );
  }
}

/// Places the excerpt menu above the selection anchor, kept inside the view.
class _MenuLayout extends SingleChildLayoutDelegate {
  new({required this.anchor});
  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var dx = anchor.dx - childSize.width / 2;
    dx = dx.clamp(
      8.0,
      (size.width - childSize.width - 8).clamp(8.0, double.infinity),
    );
    var dy = anchor.dy - childSize.height - 14;
    if (dy < 8) dy = anchor.dy + 28; // no room above: show below
    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.anchor != anchor;
}

class _BoxPainter extends CustomPainter {
  new(this.a, this.b, this.color);
  final Offset? a, b;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (a == null || b == null) return;
    final r = Rect.fromPoints(a!, b!);
    canvas.drawRect(r, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawRect(
      r,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.a != a || old.b != b || old.color != color;
}
