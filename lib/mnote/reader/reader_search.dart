import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:saber/mnote/theme/mnote_theme.dart';

/// Full-text search over the open PDF: query field, match count,
/// previous/next, and a list of hits with page numbers.
class ReaderSearchPanel extends StatefulWidget {
  const new({super.key, required this.searcher, required this.onClose});

  final PdfTextSearcher searcher;
  final VoidCallback onClose;

  @override
  State<ReaderSearchPanel> createState() => _ReaderSearchPanelState();
}

class _ReaderSearchPanelState extends State<ReaderSearchPanel> {
  final query = TextEditingController();
  VoidCallback? _remove;

  @override
  void initState() {
    super.initState();
    _remove = widget.searcher.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _remove?.call();
    query.dispose();
    super.dispose();
  }

  void _search(String q) {
    if (q.trim().isEmpty) {
      widget.searcher.resetTextSearch();
      return;
    }
    widget.searcher.startTextSearch(
      q.trim(),
      caseInsensitive: true,
      goToFirstMatch: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    final s = widget.searcher;
    final matches = s.matches;
    final status = query.text.trim().isEmpty
        ? ''
        : s.isSearching
        ? '搜索中… ${matches.length}'
        : matches.isEmpty
        ? '没有找到'
        : '${(s.currentIndex ?? 0) + 1} / ${matches.length}';

    return Material(
      color: p.paper2,
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 12),
                Icon(Icons.search, size: 20, color: p.ink3),
                Expanded(
                  child: TextField(
                    key: const ValueKey('search-field'),
                    controller: query,
                    autofocus: true,
                    style: TextStyle(fontSize: 15, color: p.ink),
                    decoration: const InputDecoration(
                      hintText: '搜索全文',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 14,
                      ),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: _search,
                  ),
                ),
                Text(
                  status,
                  key: const ValueKey('search-status'),
                  style: TextStyle(fontSize: 13, color: p.ink3),
                ),
                IconButton(
                  tooltip: '上一个',
                  icon: Icon(Icons.keyboard_arrow_up, color: p.ink2),
                  onPressed: matches.isEmpty ? null : s.goToPrevMatch,
                ),
                IconButton(
                  tooltip: '下一个',
                  icon: Icon(Icons.keyboard_arrow_down, color: p.ink2),
                  onPressed: matches.isEmpty ? null : s.goToNextMatch,
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: Icon(Icons.close, color: p.ink2),
                  onPressed: widget.onClose,
                ),
              ],
            ),
            if (matches.isNotEmpty) Divider(height: 1, color: p.line),
            if (matches.isNotEmpty)
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: matches.length,
                  itemBuilder: (context, i) {
                    final m = matches[i];
                    final full = m.pageText.fullText;
                    final a = (m.start - 30).clamp(0, full.length);
                    final b = (m.end + 40).clamp(0, full.length);
                    final snippet = full.substring(a, b).replaceAll('\n', ' ');
                    return ListTile(
                      key: ValueKey('search-hit-$i'),
                      dense: true,
                      selected: i == s.currentIndex,
                      selectedTileColor: p.accent.withValues(alpha: 0.08),
                      leading: Text(
                        '第 ${m.pageNumber} 页',
                        style: TextStyle(fontSize: 13, color: p.accent),
                      ),
                      title: Text(
                        '…$snippet…',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: p.ink2),
                      ),
                      onTap: () => s.goToMatchOfIndex(i),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
