import 'package:material_ui/material_ui.dart';

import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/store/study_store.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// Card details: editable title, excerpt (text or region image), source,
/// note, tags, colour and child cards.
class CardDetailPanel extends StatefulWidget {
  const new({
    super.key,
    required this.store,
    required this.set,
    required this.card,
    required this.onJump,
    required this.onDelete,
    required this.onOpenCard,
  });

  final StudyStore store;
  final StudySet set;
  final MCard card;
  final VoidCallback onJump;
  final VoidCallback onDelete;
  final void Function(MCard card) onOpenCard;

  @override
  State<CardDetailPanel> createState() => _CardDetailPanelState();
}

class _CardDetailPanelState extends State<CardDetailPanel> {
  late final title = TextEditingController(text: widget.card.title);
  late final note = TextEditingController(text: widget.card.note);
  final tag = TextEditingController();

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    tag.dispose();
    super.dispose();
  }

  void _changed() => widget.store.touch(widget.set);

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    final card = widget.card;
    final doc = widget.set.docById(card.docId);
    final children = widget.set.childrenOf(card.id);
    final labelStyle = TextStyle(fontSize: 13, color: p.ink3);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: card.color.ink(dark: p.dark),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(card.color.label, style: labelStyle),
            const Spacer(),
            IconButton(
              tooltip: '删除卡片',
              icon: Icon(Icons.delete_outline, color: p.ink3),
              onPressed: widget.onDelete,
            ),
          ],
        ),
        TextField(
          key: const ValueKey('card-title'),
          controller: title,
          style: serifStyle(p.ink, size: 22, weight: FontWeight.w600),
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: '卡片标题',
          ),
          onChanged: (v) {
            card.title = v.trim().isEmpty ? '摘录' : v.trim();
            _changed();
          },
        ),
        const SizedBox(height: 8),
        if (card.image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              widget.store.imageFile(widget.set, card.image!),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) =>
                  Text('图片丢失', style: labelStyle),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: card.color.highlight(dark: p.dark),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              card.text,
              style: serifStyle(p.ink, size: 16, height: 1.7),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '${doc?.title ?? '文档'} · 第 ${card.page}${card.lastPage != card.page ? '–${card.lastPage}' : ''} 页',
                style: labelStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('card-jump'),
              onPressed: widget.onJump,
              icon: Icon(
                Icons.subdirectory_arrow_left,
                size: 18,
                color: p.accent,
              ),
              label: Text('回到原文', style: TextStyle(color: p.accent)),
            ),
          ],
        ),
        const Divider(height: 28),
        Text('颜色', style: labelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final c in ExcerptColor.values)
              ChoiceChip(
                label: Text(c.label),
                selected: card.color == c,
                avatar: CircleAvatar(
                  backgroundColor: c.ink(dark: p.dark),
                  radius: 6,
                ),
                onSelected: (_) {
                  setState(() => card.color = c);
                  _changed();
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('批注', style: labelStyle),
        TextField(
          key: const ValueKey('card-note'),
          controller: note,
          minLines: 2,
          maxLines: 6,
          style: TextStyle(fontSize: 15, color: p.ink),
          decoration: const InputDecoration(hintText: '写下你的想法'),
          onChanged: (v) {
            card.note = v;
            _changed();
          },
        ),
        const SizedBox(height: 16),
        Text('标签', style: labelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final t in card.tags)
              InputChip(
                label: Text(t),
                onDeleted: () {
                  setState(() => card.tags.remove(t));
                  _changed();
                },
              ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: tag,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '+ 添加',
                  isDense: true,
                ),
                onSubmitted: (v) {
                  final t = v.trim();
                  if (t.isEmpty || card.tags.contains(t)) return;
                  setState(() => card.tags.add(t));
                  tag.clear();
                  _changed();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('子卡片 ${children.length}', style: labelStyle),
        for (final c in children)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: c.color.ink(dark: p.dark),
              radius: 5,
            ),
            title: Text(c.title, style: serifStyle(p.ink, size: 15)),
            trailing: Text(c.pageLabel, style: labelStyle),
            onTap: () => widget.onOpenCard(c),
          ),
      ],
    );
  }
}
