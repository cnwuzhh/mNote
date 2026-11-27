import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/mnote/ai/ai_client.dart';
import 'package:saber/mnote/ai/ai_config.dart';
import 'package:saber/mnote/ai/ai_prompts.dart';
import 'package:saber/mnote/ai/ai_settings_page.dart';
import 'package:saber/mnote/cards/card_detail_panel.dart';
import 'package:saber/mnote/export/pdf_export.dart';
import 'package:saber/mnote/ink/ink_document.dart';
import 'package:saber/mnote/ink/ink_input_layer.dart';
import 'package:saber/mnote/ink/ink_paint.dart';
import 'package:saber/mnote/mindmap/mindmap_view.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/model/text_clean.dart';
import 'package:saber/mnote/reader/ai_notes.dart';
import 'package:saber/mnote/reader/edge_rail.dart';
import 'package:saber/mnote/reader/excerpt_menu.dart';
import 'package:saber/mnote/reader/link_preview.dart';
import 'package:saber/mnote/reader/mode_toolbar.dart';
import 'package:saber/mnote/reader/pdf_geometry.dart';
import 'package:saber/mnote/reader/reader_search.dart';
import 'package:saber/mnote/reader/side_panels.dart';
import 'package:saber/mnote/reader/source_sheet.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';
import 'package:url_launcher/url_launcher.dart';

const _railWidth = edgeRailWidth;
const _cardsPanelWidth = 330.0;

/// Study workspace, layout v2 (design/layout-v2, option D):
/// * reading (excerpt / handwrite): the PDF fills the width; a narrow edge
///   rail shows where the cards are; the cards list and the mind map open as
///   overlays on top of the PDF, which never re-lays out;
/// * organize: the mind map fills the screen; "回到原文" opens a side sheet
///   with the zoomed source paragraph;
/// * recall: the mind map with card contents hidden until tapped.
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

  /// Open overlay in reading modes: 'cards', 'map' or null.
  String? panel;

  /// Edge rail tucked away into a small handle.
  var railHidden = false;

  /// Organize mode: card whose source is shown in the side sheet.
  MCard? sourceCard;

  /// Recall mode: ids of cards still hidden.
  Set<String> masked = {};

  /// "已加入：…" feedback after an excerpt, near where it was made.
  ({MCard card, Offset at})? added;
  Timer? _addedTimer;
  Offset? _menuAnchor;
  final panelCardKeys = <String, GlobalKey>{};

  bool get reading => mode == WorkMode.excerpt || mode == WorkMode.handwrite;

  // AI translate / explain.
  AiConfig? aiConfig;
  final aiRuns = <String, AiRunState>{};
  final _aiCancel = <String, AiCancelToken>{};
  String? openNoteId;
  var hideAiMarks = false;
  Offset? _scrimDown;

  /// How far the page is slid left for the cards overlay (0 = not slid).
  double _shiftedBy = 0;

  // Immersive reading: scrolling down hides the top bar and toolbar; a tap
  // brings them back.
  var immersive = false;
  double? _scrollAnchor;
  Offset? _tapDown;

  // Link preview.
  Future<int?>? _refsPage;
  Offset? _lastPointer;
  LinkTarget? linkPreview;
  PdfDest? _linkDest;

  /// Where to go back to after following a link, and that page number.
  (Matrix4, int)? returnTo;
  Iterable<AiNote> get docNotes => set.aiNotes.where((n) => n.docId == doc.id);
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
    aiConfigStore.load().then((c) {
      if (mounted) setState(() => aiConfig = c);
    });
    InkDocument.loadOrQuarantine(store.inkFile(set, doc)).then((d) {
      if (!mounted) return;
      if (d.recoveredFromDamage) {
        _toast('这份文档的笔迹文件已损坏：已另存备份，笔迹从空白开始');
      }
      d.history.addListener(_onViewChanged);
      setState(() => ink = d);
      _repaintPages();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      store.flush();
      _saveInkNow();
    }
  }

  /// Writes pending handwriting immediately (leaving the app / the page).
  void _saveInkNow() {
    if (!(_inkSave?.isActive ?? false)) return;
    _inkSave!.cancel();
    final d = ink;
    if (d != null) {
      d
          .save(store.inkFile(set, doc))
          .catchError((Object e) => _toast('笔迹保存失败：$e'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_onViewChanged);
    _removeSearchListener?.call();
    searcher.dispose();
    _addedTimer?.cancel();
    ink?.history.removeListener(_onViewChanged);
    if (_inkSave?.isActive ?? false) {
      _inkSave!.cancel();
      ink?.save(store.inkFile(set, doc)).catchError((Object _) {});
    }
    store.flush();
    super.dispose();
  }

  void _onViewChanged() {
    if (!mounted) return;
    if (controller.isReady && reading) {
      final y = controller.value.getTranslation().y;
      final a = _scrollAnchor ??= y;
      final busy =
          panel != null ||
          openNoteId != null ||
          linkPreview != null ||
          searchOpen ||
          lassoSel != null;
      if (a - y > 48) {
        // Content moved up: reading on. Hide the bars.
        _scrollAnchor = y;
        if (!immersive && !busy) immersive = true;
      } else if (y - a > 48) {
        _scrollAnchor = y;
      }
    }
    setState(() {});
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
      _refsPage = findReferencesPage(document);
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
    if (!hideAiMarks) {
      final dash = Paint()
        ..color = MnotePalette.of(context).accent.withValues(alpha: 0.75)
        ..strokeWidth = 1.2;
      for (final n in docNotes) {
        for (final r in n.rects) {
          if (r.page != page.pageNumber) continue;
          final rect = r.toPdfRect().toRectInDocument(
            page: page,
            pageRect: pageRect,
          );
          for (var x = rect.left; x < rect.right; x += 6) {
            canvas.drawLine(
              Offset(x, rect.bottom + 1.5),
              Offset((x + 3).clamp(x, rect.right), rect.bottom + 1.5),
              dash,
            );
          }
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
      if (d != null) {
        d
            .save(store.inkFile(set, doc))
            .catchError((Object e) => _toast('笔迹保存失败：$e'));
      }
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
    final at = _lassoBoundsInViewer()?.topLeft;
    lassoSel = null;
    _repaintPages();
    _showAdded(card, at);
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
    _menuAnchor = params.anchorA;
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
    if (action == ExcerptAction.translate || action == ExcerptAction.explain) {
      await _aiOnSelection(
        d,
        action == ExcerptAction.translate ? AiNote.translate : AiNote.explain,
      );
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
    if (!card.highlightOnly) {
      _showAdded(card, _menuAnchor);
      _flyIn(card);
    }
  }

  void _showAdded(MCard card, Offset? at) {
    _addedTimer?.cancel();
    setState(() => added = (card: card, at: at ?? const Offset(120, 120)));
    _addedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => added = null);
    });
  }

  void _undoAdded() {
    final a = added;
    if (a == null) return;
    store.deleteCard(set, a.card);
    setState(() => added = null);
    _repaintPages();
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
    _showAdded(card, boxStart ?? a);
    _flyIn(card);
  }

  /// Animates a ghost card from the excerpt's source text into its bar on the
  /// edge rail (or, with the map overlay open, into its mind-map node).
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

      final readerBox =
          readerKey.currentContext?.findRenderObject() as RenderBox?;
      final src = cardBoundsInViewer(controller, card);
      final start = (readerBox == null || src == null || overlayBox == null)
          ? null
          : Rect.fromLTWH(
              readerBox.localToGlobal(src.topLeft, ancestor: overlayBox).dx,
              readerBox.localToGlobal(src.topLeft, ancestor: overlayBox).dy,
              src.width.clamp(40.0, 260.0),
              src.height.clamp(20.0, 80.0),
            );
      final end = panel == 'map'
          ? rectOf(nodeKeys[card.id])
          : railHidden
          ? null
          : rectOf(railKeys[card.id]);
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

  /// Organize mode: show the source next to the mind map instead of leaving it.
  void _showSource(MCard card) => setState(() {
    selectedId = card.id;
    sourceCard = card;
  });

  Future<void> _readAt(MCard card) async {
    if (panel == 'cards') _slideBack();
    setState(() {
      mode = WorkMode.excerpt;
      sourceCard = null;
      panel = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    await _jumpTo(card);
  }

  void _setMode(WorkMode m) {
    if (panel == 'cards') _slideBack();
    setState(() {
      immersive = false;
      mode = m;
      panel = null;
      sourceCard = null;
      if (m == WorkMode.recall) masked = set.mapCards.map((c) => c.id).toSet();
    });
    if (m != WorkMode.handwrite && lassoSel != null) _clearLasso();
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
          behavior: SnackBarBehavior.floating,
          margin: _snackMargin,
          content: Text('已删除「${card.title}」及其高亮'),
          // Flutter keeps snack bars with an action on screen until tapped
          // unless told otherwise; this one should go away by itself.
          persist: false,
          duration: const Duration(seconds: 5),
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

  /// Hints float above the bottom toolbar instead of covering it.
  EdgeInsets get _snackMargin =>
      const EdgeInsets.fromLTRB(16, 0, _railWidth + 16, 84);

  // ---------------- overlays ----------------

  /// Opens / closes the cards or mind-map overlay. Opening the cards overlay
  /// slides the page left so the right column (which it would cover) stays
  /// readable next to it; closing slides it back.
  void _setPanel(String? v) {
    final was = panel;
    setState(() => panel = v);
    if (v == 'cards' && was != 'cards') _slideForCards();
    if (was == 'cards' && v != 'cards') _slideBack();
  }

  Future<void> _slideForCards() async {
    if (!hasPageLayout(controller)) return;
    final box = readerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pageNo = (controller.pageNumber ?? 1).clamp(1, controller.pageCount);
    final pr = controller.layout.pageLayouts[pageNo - 1];
    final left = controller.documentToLocal(pr.topLeft).dx;
    final right = controller.documentToLocal(pr.topRight).dx;
    // Text of a two-column paper ends about 10% before the page edge.
    final textRight = left + (right - left) * 0.9;
    final panelLeft = box.size.width - _cardsPanelWidth;
    final dx = textRight - panelLeft + 12;
    if (dx <= 0) return;
    setState(() => _shiftedBy = dx);
    await WidgetsBinding.instance.endOfFrame;
    await controller.goTo(
      Matrix4.translationValues(-dx, 0, 0)..multiply(controller.value),
      duration: const Duration(milliseconds: 320),
    );
  }

  Future<void> _slideBack() async {
    final dx = _shiftedBy;
    if (dx <= 0) return;
    await controller.goTo(
      Matrix4.translationValues(dx, 0, 0)..multiply(controller.value),
      duration: const Duration(milliseconds: 280),
    );
    if (mounted) setState(() => _shiftedBy = 0);
  }

  // ---------------- links ----------------

  Future<void> _onLinkTap(PdfLink link) async {
    final url = link.url;
    if (url != null) {
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(url.toString(), key: const ValueKey('link-url')),
              ),
              ListTile(
                key: const ValueKey('link-open-browser'),
                leading: const Icon(Icons.open_in_browser),
                title: const Text('在浏览器打开'),
                onTap: () {
                  Navigator.pop(ctx);
                  launchUrl(url, mode: LaunchMode.externalApplication);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('复制链接'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: url.toString()));
                  Navigator.pop(ctx);
                  _toast('已复制');
                },
              ),
            ],
          ),
        ),
      );
      return;
    }
    if (!controller.isReady) return;
    final at = _lastPointer;
    final from = at == null
        ? controller.pageNumber
        : controller
              .getPdfPageHitTestResult(at, useDocumentLayoutCoordinates: false)
              ?.page
              .pageNumber;
    final t = await resolveLink(
      controller.document,
      link,
      fromPage: from,
      referencesFrom: await (_refsPage ??= findReferencesPage(
        controller.document,
      )),
    );
    if (!mounted) return;
    if (t == null) {
      await controller.goToDest(link.dest);
      return;
    }
    setState(() {
      linkPreview = t;
      _linkDest = link.dest;
      openNoteId = null;
    });
  }

  Future<void> _followLink() async {
    final dest = _linkDest;
    if (dest == null) return;
    setState(() {
      returnTo = (
        controller.value.clone(),
        controller.pageNumber ?? doc.lastPage,
      );
      linkPreview = null;
    });
    await controller.goToDest(dest);
  }

  Future<void> _goBack() async {
    final r = returnTo;
    if (r == null) return;
    setState(() => returnTo = null);
    await controller.goTo(r.$1);
  }

  List<Widget> _linkPopover(MnotePalette p, double viewW, double viewH) {
    final t = linkPreview!;
    final page = controller.pages[t.page - 1];
    final w = t.kind == LinkKind.figure || t.kind == LinkKind.table
        ? 520.0
        : 420.0;
    final estH = t.kind == LinkKind.figure || t.kind == LinkKind.table
        ? 360.0
        : (t.kind == LinkKind.reference ? 190.0 : 220.0);
    final at = _lastPointer ?? Offset(viewW / 2, viewH / 3);
    final left = (at.dx - w / 2).clamp(
      12.0,
      (viewW - w - 12).clamp(12.0, double.infinity),
    );
    final below = at.dy + 18 + estH < viewH - 70;
    final top = below
        ? at.dy + 18
        : (at.dy - 18 - estH).clamp(8.0, double.infinity);
    return [
      Positioned.fill(
        child: Listener(
          key: const ValueKey('link-preview-scrim'),
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) => _scrimDown = e.position,
          onPointerUp: (e) {
            final d = _scrimDown;
            _scrimDown = null;
            if (d != null && (e.position - d).distance < 12)
              setState(() => linkPreview = null);
          },
        ),
      ),
      Positioned(
        left: left,
        top: top,
        child: LinkPreviewCard(
          target: t,
          page: page,
          onGo: _followLink,
          onCopy: () {
            Clipboard.setData(ClipboardData(text: t.text));
            _toast('已复制');
          },
          onClose: () => setState(() => linkPreview = null),
        ),
      ),
    ];
  }

  Widget _returnPill(MnotePalette p) => Positioned(
    left: 16,
    bottom: 80,
    child: Material(
      color: p.ink,
      borderRadius: BorderRadius.circular(20),
      elevation: 6,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const ValueKey('btn-return'),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(20),
            ),
            onTap: _goBack,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
              child: Row(
                children: [
                  Icon(Icons.undo, size: 16, color: p.paper),
                  const SizedBox(width: 6),
                  Text(
                    '返回第 ${returnTo!.$2} 页',
                    style: TextStyle(fontSize: 14, color: p.paper),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('btn-return-dismiss'),
            tooltip: '不返回',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => returnTo = null),
            icon: Icon(Icons.close, color: p.paper.withValues(alpha: 0.8)),
          ),
        ],
      ),
    ),
  );

  // ---------------- AI translate / explain ----------------

  Future<void> _aiOnSelection(PdfTextSelectionDelegate d, String kind) async {
    if (set.aiDisabled) {
      _toast('这个学习集已关闭 AI（在学习集页右上角可以打开）');
      return;
    }
    if (aiConfig == null) {
      aiConfig = await aiConfigStore.load();
      if (aiConfig == null) {
        if (!mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('还没有配置 AI 服务'),
            content: const Text(
              '翻译和解释需要一个 AI 服务。导入配置文件（ai_providers.json）后即可使用。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('以后再说'),
              ),
              FilledButton(
                key: const ValueKey('ai-go-settings'),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('去设置'),
              ),
            ],
          ),
        );
        if (go == true) await _openAiSettings();
        return;
      }
    }
    final ranges = await d.getSelectedTextRanges();
    final raw = await d.getSelectedText();
    final rects = lineRectsForRanges(ranges);
    if (rects.isEmpty) return;
    final text = cleanExcerptText(raw);
    // Context for explanations: the text around the selection on its page.
    String? pageContext;
    if (ranges.isNotEmpty) {
      final full = ranges.first.pageText.fullText;
      final a = (ranges.first.start - 500).clamp(0, full.length);
      final b = (ranges.last.end + 500).clamp(0, full.length);
      pageContext = cleanExcerptText(full.substring(a, b));
    }
    await d.clearTextSelection();
    startAiNote(kind, rects, text, context: pageContext);
  }

  /// Creates an AI note for a passage and starts generating it. Public so
  /// widget tests can drive the flow without simulating a text selection.
  AiNote startAiNote(
    String kind,
    List<PageRect> rects,
    String text, {
    String? context,
  }) {
    final note = AiNote(
      id: newId(),
      docId: doc.id,
      kind: kind,
      rects: rects,
      source: text,
    );
    set.aiNotes.add(note);
    store.touch(set);
    setState(() {
      if (!(aiConfig?.markerOnly ?? false)) openNoteId = note.id;
    });
    _repaintPages();
    _runAi(note, context: context);
    return note;
  }

  Future<void> _runAi(AiNote note, {String? context}) async {
    final cfg = aiConfig;
    if (cfg == null) return;
    _aiCancel[note.id]?.cancel();
    final cancel = _aiCancel[note.id] = AiCancelToken();
    final run = aiRuns[note.id] = AiRunState();
    setState(() {});
    final msgs = note.kind == AiNote.explain
        ? explainMessages(
            note.source,
            targetLanguage: cfg.targetLanguage,
            docTitle: doc.title,
            page: note.page,
            context: context,
          )
        : translateMessages(
            note.source,
            targetLanguage: cfg.targetLanguage,
            docTitle: doc.title,
            page: note.page,
          );
    try {
      final r = await const AiClient().run(
        cfg,
        note.kind == AiNote.explain ? taskExplain : taskTranslate,
        msgs,
        cancel: cancel,
        onDelta: (t, p) {
          if (!mounted) return;
          setState(() {
            run.partial = t;
            run.provider = p.name;
          });
        },
      );
      note
        ..result = r.text
        ..providerName = r.provider.name;
      run
        ..status = AiRunStatus.done
        ..provider = r.provider.name;
      store.touch(set);
    } on AiCancelled {
      return;
    } on AiException catch (e) {
      run
        ..status = AiRunStatus.error
        ..error = e.message;
    }
    if (mounted) setState(() {});
  }

  AiRunStatus _statusOf(AiNote n) =>
      aiRuns[n.id]?.status ??
      (n.result.isEmpty ? AiRunStatus.error : AiRunStatus.done);

  void _deleteNote(AiNote n) {
    _aiCancel.remove(n.id)?.cancel();
    aiRuns.remove(n.id);
    set.aiNotes.remove(n);
    store.touch(set);
    setState(() {
      if (openNoteId == n.id) openNoteId = null;
    });
    _repaintPages();
  }

  Future<void> _confirmDeleteNote(AiNote n) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListTile(
          key: const ValueKey('ai-delete-marker'),
          leading: const Icon(Icons.delete_outline),
          title: Text('删除这个「${aiNoteLabel(n)}」标记'),
          onTap: () => Navigator.pop(ctx, true),
        ),
      ),
    );
    if (ok == true) _deleteNote(n);
  }

  /// The card whose source overlaps [n]'s passage, if any.
  MCard? _cardFor(AiNote n) {
    for (final c in docCards) {
      for (final a in c.rects) {
        for (final b in n.rects) {
          if (a.page == b.page &&
              a.left < b.right &&
              b.left < a.right &&
              a.bottom < b.top &&
              b.bottom < a.top)
            return c;
        }
      }
    }
    return null;
  }

  String _noteText(AiNote n) =>
      n.result.isNotEmpty ? n.result : aiRuns[n.id]?.partial ?? '';

  void _saveNoteToCard(AiNote n) {
    final c = _cardFor(n);
    if (c == null) {
      _toast('这句话还没有卡片：可以点「摘录为卡片」');
      return;
    }
    final label = n.kind == AiNote.explain ? '【AI 解释】' : '【AI 译文】';
    c.note = c.note.trim().isEmpty
        ? '$label${_noteText(n)}'
        : '${c.note.trim()}\n$label${_noteText(n)}';
    store.touch(set);
    _toast('已存入卡片「${c.title}」的批注');
  }

  void _noteToCard(AiNote n) {
    final label = n.kind == AiNote.explain ? '【AI 解释】' : '【AI 译文】';
    final card = MCard(
      id: newId(),
      docId: doc.id,
      title: defaultCardTitle(n.source),
      text: n.source,
      color: color,
      rects: List.of(n.rects),
      note: '$label${_noteText(n)}',
    );
    store.addCard(set, card);
    setState(() => openNoteId = null);
    _repaintPages();
    _showAdded(card, null);
    _flyIn(card);
  }

  Future<void> _openAiSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const AiSettingsPage()));
    final c = await aiConfigStore.load();
    if (mounted) setState(() => aiConfig = c);
  }

  /// Rects of [rects] in viewer-local coordinates.
  List<Rect> _localRects(List<PageRect> rects) {
    if (!hasPageLayout(controller)) return const [];
    final out = <Rect>[];
    for (final r in rects) {
      if (r.page < 1 || r.page > controller.pageCount) continue;
      final docRect = controller.calcRectForRectInsidePage(
        pageNumber: r.page,
        rect: r.toPdfRect(),
      );
      final tl = controller.documentToLocal(docRect.topLeft);
      final br = controller.documentToLocal(docRect.bottomRight);
      out.add(Rect.fromPoints(tl, br));
    }
    return out;
  }

  /// Markers sit next to the passage's last line: in the gutter for a left
  /// column, in the right margin otherwise, so they never cover text.
  Offset? _markerPos(AiNote n, int indexAmongSame) {
    final rs = _localRects(n.rects);
    if (rs.isEmpty) return null;
    final last = rs.last;
    final r = n.rects.last;
    final pageRect = controller.layout.pageLayouts[r.page - 1];
    final pTL = controller.documentToLocal(pageRect.topLeft);
    final pBR = controller.documentToLocal(pageRect.bottomRight);
    final pw = pBR.dx - pTL.dx;
    final inLeftHalf = last.center.dx < pTL.dx + pw * 0.5;
    final x = inLeftHalf ? pTL.dx + pw * 0.5 - 13 : pTL.dx + pw * 0.925 - 13;
    return Offset(x + indexAmongSame * 30, last.center.dy - 11);
  }

  List<Widget> _aiMarkers(MnotePalette p) {
    final out = <Widget>[];
    final seen = <String, int>{};
    for (final n in docNotes) {
      final key = n.rects.isEmpty
          ? n.id
          : '${n.rects.last.page}-${n.rects.last.top.round()}';
      final i = seen[key] = (seen[key] ?? -1) + 1;
      final pos = _markerPos(n, i);
      if (pos == null || pos.dy < -30 || pos.dy > 3000) continue;
      out.add(
        Positioned(
          key: ValueKey('ai-marker-${n.id}'),
          left: pos.dx,
          top: pos.dy,
          child: AiMarker(
            note: n,
            status: _statusOf(n),
            onTap: () =>
                setState(() => openNoteId = openNoteId == n.id ? null : n.id),
            onLongPress: () => _confirmDeleteNote(n),
          ),
        ),
      );
    }
    return out;
  }

  List<Widget> _aiPanel(MnotePalette p, double viewW, double viewH) {
    AiNote? n;
    for (final x in docNotes) {
      if (x.id == openNoteId) n = x;
    }
    if (n == null) return const [];
    final note = n;
    final rs = _localRects(note.rects);
    if (rs.isEmpty) return const [];
    final bounds = rs.reduce((a, b) => a.expandToInclude(b));
    const w = 440.0, estH = 230.0;
    final left = bounds.left.clamp(
      12.0,
      (viewW - w - 12).clamp(12.0, double.infinity),
    );
    // Above the passage when there is room, else below it.
    final above = bounds.top - estH - 10 > 8;
    final top = above
        ? bounds.top - estH - 10
        : (bounds.bottom + 10).clamp(
            8.0,
            (viewH - estH - 80).clamp(8.0, double.infinity),
          );
    return [
      // Tap anywhere else: collapse back into the marker. A raw listener
      // (not a tap recognizer) so it reacts at once and never competes with
      // the PDF viewer's gestures; a drag (scrolling) keeps the panel open.
      Positioned.fill(
        child: Listener(
          key: const ValueKey('ai-panel-scrim'),
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) => _scrimDown = e.position,
          onPointerUp: (e) {
            final d = _scrimDown;
            _scrimDown = null;
            if (d != null && (e.position - d).distance < 12)
              setState(() => openNoteId = null);
          },
        ),
      ),
      Positioned(
        left: left,
        top: top,
        child: AiNotePanel(
          note: note,
          run: aiRuns[note.id],
          targetLanguageLabel: '英译中',
          onClose: () => setState(() => openNoteId = null),
          onSaveAsNote: () => _saveNoteToCard(note),
          onMakeCard: () => _noteToCard(note),
          onCopy: () {
            Clipboard.setData(ClipboardData(text: _noteText(note)));
            _toast('已复制');
          },
          onRegenerate: () {
            note.result = '';
            _runAi(note);
          },
          onDelete: () => _deleteNote(note),
          onOpenSettings: _openAiSettings,
        ),
      ),
    ];
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: _snackMargin,
        ),
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
    return Scaffold(
      backgroundColor: p.board,
      body: SafeArea(
        child: Column(
          children: [
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: immersive && reading
                    ? const SizedBox(
                        width: double.infinity,
                        key: ValueKey('top-bar-hidden'),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _topBar(p),
                          Divider(height: 1, color: p.line),
                        ],
                      ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, cons) =>
                    _body(p, cons.maxWidth, cons.maxHeight),
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
    final hiddenCount = masked.length;
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
                  if (reading)
                    crumb('文档', doc.title)
                  else
                    crumb('脑图', set.name),
                ],
              ),
            ),
          ),
          if (reading) ...[
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
            if (docNotes.isNotEmpty)
              IconButton(
                key: const ValueKey('btn-ai-marks'),
                tooltip: hideAiMarks ? '显示翻译 / 解释标记' : '隐藏全部标记',
                icon: Icon(
                  hideAiMarks
                      ? Icons.subtitles_off_outlined
                      : Icons.subtitles_outlined,
                  color: p.ink2,
                ),
                onPressed: () {
                  setState(() {
                    hideAiMarks = !hideAiMarks;
                    if (hideAiMarks) openNoteId = null;
                  });
                  _repaintPages();
                },
              ),
            IconButton(
              key: const ValueKey('btn-export'),
              tooltip: '导出',
              icon: Icon(Icons.ios_share, color: p.ink2),
              onPressed: _export,
            ),
          ],
          if (mode == WorkMode.recall) ...[
            Text(
              hiddenCount == 0 ? '已全部揭开' : '点灰条回忆后揭开，未揭开 $hiddenCount 张',
              key: const ValueKey('recall-status'),
              style: TextStyle(fontSize: 14, color: p.ink2),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: const ValueKey('btn-start-review'),
              style: FilledButton.styleFrom(backgroundColor: p.accent),
              onPressed: () => _toast('复习（间隔重复）将在后续版本提供'),
              child: Text('开始复习（${set.mapCards.length}）'),
            ),
            const SizedBox(width: 8),
          ],
          PopupMenuButton<ReadingTheme>(
            key: const ValueKey('btn-theme'),
            tooltip: '主题：${mnoteReadingTheme.value.label}',
            initialValue: mnoteReadingTheme.value,
            onSelected: (t) {
              mnoteReadingTheme.value = t;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _repaintPages(),
              );
            },
            itemBuilder: (_) => [
              for (final t in ReadingTheme.values)
                CheckedPopupMenuItem(
                  key: ValueKey('theme-${t.name}'),
                  value: t,
                  checked: t == mnoteReadingTheme.value,
                  child: Text(t.label),
                ),
            ],
            icon: Icon(switch (mnoteReadingTheme.value) {
              ReadingTheme.day => Icons.light_mode_outlined,
              ReadingTheme.paper => Icons.menu_book_outlined,
              ReadingTheme.night => Icons.dark_mode_outlined,
            }, color: p.ink2),
          ),
        ],
      ),
    );
  }

  /// Every map card of this document with its source rect in the reader.
  List<(MCard, Rect)> _positions() {
    if (!hasPageLayout(controller)) return const [];
    return [
      for (final c in set.mapCards.where((c) => c.docId == doc.id))
        if (cardBoundsInViewer(controller, c) case final r?) (c, r),
    ];
  }

  Widget _body(MnotePalette p, double w, double h) {
    final file = store.docFile(set, doc);
    final viewW = w - _railWidth;
    final positions = _positions();
    final marks = [
      for (final (c, r) in positions)
        if (r.bottom > 0 && r.top < h)
          RailMark(c, r.top.clamp(0.0, h), r.height.clamp(6.0, 120.0)),
    ];
    final mapW = (w * 0.48).clamp(380.0, 680.0);
    final mapCount = set.mapCards.length;

    return Stack(
      children: [
        // ---- reader (kept mounted in every mode, so its position is kept) ----
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: viewW,
          child: Stack(
            key: readerKey,
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: p.gap,
                  child: PdfViewer.file(
                    file.path,
                    controller: controller,
                    params: PdfViewerParams(
                      backgroundColor: p.gap,
                      pageImageColorFilter: pageFilterFor(p),
                      // Room to slide the page left while the cards overlay is open.
                      boundaryMargin: _shiftedBy > 0
                          ? const EdgeInsets.only(right: 480)
                          : null,
                      linkHandlerParams: PdfLinkHandlerParams(
                        onLinkTap: _onLinkTap,
                        linkColor: Colors.transparent,
                      ),
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
                    onPanUpdate: (d) =>
                        setState(() => boxEnd = d.localPosition),
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

              if (searchOpen && reading)
                Positioned(
                  top: 12,
                  right: 12,
                  width: 360,
                  child: ReaderSearchPanel(
                    searcher: searcher,
                    onClose: () => setState(() {
                      searchOpen = false;
                      searcher.resetTextSearch();
                    }),
                  ),
                ),
              if (added != null && reading) _addedChip(p, viewW),
              if (reading && !hideAiMarks) ..._aiMarkers(p),
              if (reading && openNoteId != null) ..._aiPanel(p, viewW, h),
              if (reading && linkPreview != null) ..._linkPopover(p, viewW, h),
              if (reading && returnTo != null) _returnPill(p),
              // Remembers where the finger went down (to place link previews);
              // in immersive mode a tap (no drag) brings the bars back.
              Positioned.fill(
                child: Listener(
                  key: const ValueKey('reader-pointer'),
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (e) {
                    _lastPointer = e.localPosition;
                    _tapDown = e.position;
                  },
                  onPointerUp: (e) {
                    final d = _tapDown;
                    _tapDown = null;
                    if (immersive &&
                        d != null &&
                        (e.position - d).distance < 12) {
                      setState(() {
                        immersive = false;
                        _scrollAnchor = controller.isReady
                            ? controller.value.getTranslation().y
                            : null;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ),

        // ---- edge rail ----
        if (reading && !railHidden)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: _railWidth,
            child: EdgeRail(
              count: mapCount,
              marks: marks,
              barKeys: railKeys,
              panel: panel,
              onCards: () => _setPanel(panel == 'cards' ? null : 'cards'),
              onMap: () => _setPanel(panel == 'map' ? null : 'map'),
              onHide: () {
                _setPanel(null);
                setState(() => railHidden = true);
              },
              onDragOpen: () => _setPanel('cards'),
            ),
          ),
        if (reading && railHidden)
          Positioned(
            right: 0,
            top: h / 2 - 36,
            child: EdgeHandle(onShow: () => setState(() => railHidden = false)),
          ),

        // ---- overlays on top of the PDF (the PDF does not move) ----
        if (reading && panel != null) ...[
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            right: _railWidth,
            // Mind map: dimmed, blocks the page. Cards: the page stays usable
            // (drag scrolls it); a tap outside closes the overlay.
            child: panel == 'map'
                ? GestureDetector(
                    key: const ValueKey('panel-scrim'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _setPanel(null),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.12),
                    ),
                  )
                : Listener(
                    key: const ValueKey('panel-scrim'),
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (e) => _scrimDown = e.position,
                    onPointerUp: (e) {
                      final d = _scrimDown;
                      _scrimDown = null;
                      if (d != null && (e.position - d).distance < 12)
                        _setPanel(null);
                    },
                  ),
          ),
          Positioned(
            right: _railWidth,
            top: 0,
            bottom: 0,
            width: panel == 'map' ? mapW : _cardsPanelWidth,
            child: OverlayPanel(
              panel: panel!,
              subtitle: panel == 'cards'
                  ? '本文 ${positions.length} 张'
                  : '可拖拽节点，点回退图标回到原文',
              onPanel: _setPanel,
              onClose: () => _setPanel(null),
              child: panel == 'cards'
                  ? CardsOverlayBody(
                      positions: positions,
                      bodyTop: overlayHeaderHeight + 1,
                      selectedId: selectedId,
                      cardKeys: panelCardKeys,
                      onOpen: _openCard,
                      onJump: _jumpTo,
                    )
                  : MindMapView(
                      set: set,
                      nodeKeys: nodeKeys,
                      flashId: flashNodeId,
                      selectedId: selectedId,
                      onOpen: _openCard,
                      onJump: _jumpTo,
                      onMove: _moveCard,
                    ),
            ),
          ),
        ],

        // ---- organize / recall: the mind map fills the screen ----
        if (!reading)
          Positioned.fill(
            child: ColoredBox(
              key: ValueKey('map-view-${mode.name}'),
              color: p.paper,
              child: MindMapView(
                set: set,
                nodeKeys: nodeKeys,
                flashId: flashNodeId,
                selectedId: selectedId,
                onOpen: _openCard,
                onJump: _showSource,
                onMove: _moveCard,
                masked: mode == WorkMode.recall ? masked : null,
                // Keep the tree clear of the source sheet.
                rightInset: mode == WorkMode.organize && sourceCard != null
                    ? (w * 0.36).clamp(360.0, 480.0)
                    : 0,
                fill: true,
                onReveal: (c) => setState(() => masked.remove(c.id)),
              ),
            ),
          ),
        if (mode == WorkMode.organize && sourceCard != null)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: (w * 0.36).clamp(360.0, 480.0),
            child: SourceSheet(
              key: ValueKey('source-${sourceCard!.id}'),
              store: store,
              set: set,
              card: sourceCard!,
              page:
                  controller.isReady && sourceCard!.page <= controller.pageCount
                  ? controller.pages[sourceCard!.page - 1]
                  : null,
              onRead: () => _readAt(sourceCard!),
              onClose: () => setState(() => sourceCard = null),
            ),
          ),

        // ---- bottom toolbar ----
        Positioned(
          left: 16,
          bottom: 16,
          right: (reading ? _railWidth : 0) + 16,
          child: IgnorePointer(
            ignoring: immersive && reading,
            child: AnimatedSlide(
              key: const ValueKey('toolbar-slide'),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              offset: immersive && reading ? const Offset(0, 2) : Offset.zero,
              child: Align(
                alignment: reading
                    ? Alignment.bottomLeft
                    : Alignment.bottomCenter,
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
                  onMode: _setMode,
                  color: color,
                  onColor: (c) => setState(() => color = c),
                  onRevealAll: () => setState(() => masked = {}),
                  onRemask: () => setState(
                    () => masked = set.mapCards.map((c) => c.id).toSet(),
                  ),
                  tool: tool,
                  onTool: (t) {
                    setState(() => tool = t);
                    if (t == ExcerptTool.box) _toast('在页面上拖出一个矩形来截取区域');
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// "已加入：<标题>　编辑　撤销", shown for 3 s next to where the excerpt was made.
  Widget _addedChip(MnotePalette p, double viewW) {
    final a = added!;
    final left = (a.at.dx - 40).clamp(
      12.0,
      (viewW - 380).clamp(12.0, double.infinity),
    );
    final top = (a.at.dy - 52).clamp(8.0, double.infinity);
    return Positioned(
      left: left,
      top: top,
      child: Material(
        key: const ValueKey('added-chip'),
        color: const Color(0xFF2A251E),
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: a.card.color.ink(dark: p.dark),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  '已加入：${a.card.title}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              TextButton(
                key: const ValueKey('added-edit'),
                onPressed: () {
                  setState(() => added = null);
                  _openCard(a.card);
                },
                child: Text(
                  '编辑',
                  style: TextStyle(
                    color: p.accent == const Color(0xFFB4532A)
                        ? const Color(0xFFF0A07A)
                        : p.accent,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('added-undo'),
                onPressed: _undoAdded,
                child: const Text(
                  '撤销',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
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
